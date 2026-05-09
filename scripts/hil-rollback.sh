#!/usr/bin/env bash
# Manual rollback for hil-runner devices. Lists UKIs in /boot/EFI/Linux,
# detects the running version from the partlabel of /nix/store, and asks
# systemd-boot to boot a chosen UKI on next boot. Default: the previous UKI.
# --persistent flips set-default instead of set-oneshot. --list just prints.
set -euo pipefail

ESP_DIR=/boot/EFI/Linux
UKI_PREFIX=hil-runner

usage() {
  cat <<EOF
Usage: $(basename "$0") [--list] [--persistent] [--help]

Rolls back the hil-runner UKI choice for the next boot.

  --list         List available UKIs and exit.
  --persistent   Use 'bootctl set-default' (sticky) instead of set-oneshot.
  --help         Show this help.

With no flags, prompts interactively and defaults to the UKI that is NOT
currently running. Re-run with --persistent to make the choice stick.
EOF
}

PERSISTENT=0
LIST_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --list)        LIST_ONLY=1 ;;
    --persistent)  PERSISTENT=1 ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

# Need root for bootctl writes to the ESP. Re-exec under sudo if not already.
if [[ $EUID -ne 0 ]]; then
  exec sudo "$0" "$@"
fi

[[ -d "$ESP_DIR" ]] || { echo "ERROR: $ESP_DIR not found — is the ESP mounted?" >&2; exit 1; }

# Detect currently running version from the partlabel of /nix/store.
ACTIVE=$(awk '$2=="/nix/store"{print $1; exit}' /proc/mounts)
[[ -L "$ACTIVE" ]] && ACTIVE=$(readlink -f "$ACTIVE")
ACTIVE_LABEL=$(lsblk -no PARTLABEL "$ACTIVE" 2>/dev/null || true)
ACTIVE_VER=${ACTIVE_LABEL#store_}
if [[ -z "$ACTIVE_VER" || "$ACTIVE_VER" == "$ACTIVE_LABEL" ]]; then
  echo "WARNING: could not derive running version from $ACTIVE (label='$ACTIVE_LABEL')" >&2
  ACTIVE_VER=""
fi

# Enumerate UKIs. Sort newest-first to match systemd-boot's default policy.
mapfile -t UKIS < <(
  find "$ESP_DIR" -maxdepth 1 -type f -name "${UKI_PREFIX}_*.efi" -printf '%f\n' \
    | sort -r
)
[[ ${#UKIS[@]} -gt 0 ]] || { echo "ERROR: no ${UKI_PREFIX}_*.efi UKIs found in $ESP_DIR" >&2; exit 1; }

# Snapshot store_* partlabels once for sanity-checking.
STORE_LABELS=$(lsblk -no PARTLABEL 2>/dev/null | grep -E '^store_' || true)

print_list() {
  local i name ver mark store_ok
  for i in "${!UKIS[@]}"; do
    name=${UKIS[$i]}
    ver=${name#${UKI_PREFIX}_}
    ver=${ver%.efi}
    mark=" "
    [[ "$ver" == "$ACTIVE_VER" ]] && mark="*"
    if grep -qx "store_${ver}" <<<"$STORE_LABELS"; then
      store_ok="store_${ver} present"
    else
      store_ok="store_${ver} MISSING"
    fi
    printf '  [%d] %s %s  (%s)\n' "$i" "$mark" "$name" "$store_ok"
  done
  echo "  (* = currently running)"
}

if [[ $LIST_ONLY -eq 1 ]]; then
  echo "UKIs in $ESP_DIR:"
  print_list
  exit 0
fi

# Pick the default selection: first UKI whose version != ACTIVE_VER.
DEFAULT_IDX=0
for i in "${!UKIS[@]}"; do
  ver=${UKIS[$i]#${UKI_PREFIX}_}; ver=${ver%.efi}
  if [[ "$ver" != "$ACTIVE_VER" ]]; then
    DEFAULT_IDX=$i
    break
  fi
done

echo "UKIs in $ESP_DIR:"
print_list
echo
read -r -p "Select UKI to boot [${DEFAULT_IDX}]: " CHOICE
CHOICE=${CHOICE:-$DEFAULT_IDX}
if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || (( CHOICE < 0 || CHOICE >= ${#UKIS[@]} )); then
  echo "ERROR: invalid selection: $CHOICE" >&2
  exit 1
fi

PICK=${UKIS[$CHOICE]}
PICK_VER=${PICK#${UKI_PREFIX}_}; PICK_VER=${PICK_VER%.efi}

if [[ "$PICK_VER" == "$ACTIVE_VER" ]]; then
  echo "WARNING: selected UKI matches the currently running version ($PICK_VER)."
fi

# Refuse if the matching store partition isn't on disk — booting it would
# leave /nix/store unmounted. Point the user at the recovery path.
if ! grep -qx "store_${PICK_VER}" <<<"$STORE_LABELS"; then
  cat >&2 <<EOF
ERROR: no GPT partition labelled 'store_${PICK_VER}' is present on this device.
       Booting $PICK would fail to mount /nix/store.
       Re-stage that store image first (see scripts/hil-update.sh) or pick
       a different UKI.
EOF
  exit 1
fi

if [[ $PERSISTENT -eq 1 ]]; then
  echo "Setting default boot entry to $PICK ..."
  bootctl set-default "$PICK"
else
  echo "Setting one-shot boot entry to $PICK ..."
  bootctl set-oneshot "$PICK"
fi

echo "Done. Reboot to take effect."
