#!/usr/bin/env bash
# In-place A/B update for hil-runner devices that don't have systemd-sysupdate
# wired up yet. Pulls the latest store image + UKI from the rolling 'updates'
# release, writes the store into the inactive slot, relabels its GPT partition,
# drops the new UKI next to the existing one, and leaves the boot decision to
# systemd-boot's newest-UKI default. Old slot stays intact for rollback.
set -euo pipefail

usage() {
  cat <<EOF
Usage: hil-update [OPTIONS]

In-place A/B update for hil-runner. Streams the latest store image + UKI
from the 'updates' release into the inactive slot, relabels its GPT
partlabel, and installs the new UKI. Reboot to switch.

Options:
  -h, --help        Show this help and exit.
      --dry-run     Plan only — no dd, no sfdisk, no UKI install.
      --force       Skip the "new == running" guard (re-flash same version).
      --base URL    Release base URL (default: \$BASE or the upstream rolling
                    'updates' release). Env var BASE= still works as fallback.
EOF
}

DRY=0
FORCE=0
BASE=${BASE:-https://github.com/denysvitali/nix-hil-runner/releases/download/updates}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)    usage; exit 0 ;;
    --dry-run)    DRY=1; shift ;;
    --force)      FORCE=1; shift ;;
    --base)       BASE=${2:?--base needs URL}; shift 2 ;;
    --base=*)     BASE=${1#--base=}; shift ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

TMP=$(mktemp -d) && cd "$TMP"
trap 'rm -rf "$TMP"' EXIT

curl -fsSLO "$BASE/SHA256SUMS"
NEW=$(awk '{print $2}' SHA256SUMS \
       | grep -oE 'hil-runner_[^ ]+\.store\.raw\.xz' \
       | head -1 | sed 's/hil-runner_//;s/\.store\.raw\.xz//')
[[ -n "$NEW" ]] || { echo "no store asset in SHA256SUMS"; exit 1; }

# /nix/store is mounted twice on NixOS (initrd + systemd remount); awk+exit
# returns the first match only, avoiding multi-line `findmnt -no SOURCE`.
ACTIVE=$(awk '$2=="/nix/store"{print $1; exit}' /proc/mounts)
[[ -L "$ACTIVE" ]] && ACTIVE=$(readlink -f "$ACTIVE")
[[ -b "$ACTIVE" ]] || { echo "active device not a block device: $ACTIVE"; exit 1; }

DISK=$(lsblk -no PKNAME "$ACTIVE" 2>/dev/null || true)
if [[ -z "$DISK" ]]; then
  case "$ACTIVE" in
    *mmcblk*p[0-9]*|*nvme*p[0-9]*) DISK=${ACTIVE%p*} ;;
    *)                              DISK=$(echo "$ACTIVE" | sed -E 's/[0-9]+$//') ;;
  esac
  DISK=${DISK#/dev/}
fi
DISK=/dev/${DISK#/dev/}
[[ -b "$DISK" ]] || { echo "ERROR: $DISK not a block device"; exit 1; }

ACTIVE_LABEL=$(lsblk -no PARTLABEL "$ACTIVE" 2>/dev/null || true)
ACTIVE_VER=${ACTIVE_LABEL#store_}
echo "Active: $ACTIVE  (label=$ACTIVE_LABEL, version=$ACTIVE_VER)"
echo "New:    $NEW"

if [[ "$NEW" == "$ACTIVE_VER" ]]; then
  if (( FORCE )); then
    echo "Note: new == running, but --force given; continuing."
  else
    echo "Refusing to update: new version equals running version. Use --force to override."
    exit 1
  fi
fi

INACTIVE=$(lsblk -lnpo NAME,PARTLABEL "$DISK" \
  | awk -v a="$ACTIVE" '$1!=a && ($2=="_empty" || $2 ~ /^store_/) {print $1; exit}')
[[ -n "$INACTIVE" ]] || { echo "no inactive store slot found"; exit 1; }
PARTNUM=$(echo "$INACTIVE" | grep -oE '[0-9]+$')
echo "Inactive: $INACTIVE (partition #$PARTNUM on $DISK)"

# UKI is small (~30 MB), fits in tmpfs — download + verify locally.
curl -fsSLO "$BASE/hil-runner_${NEW}.efi"
sha256sum --ignore-missing -c <(grep "hil-runner_${NEW}.efi" SHA256SUMS)

# Expected sha256 of the .xz, pulled from SHA256SUMS for post-stream verify.
XZ_NAME="hil-runner_${NEW}.store.raw.xz"
EXPECT=$(awk -v f="$XZ_NAME" '$2==f {print $1; exit}' SHA256SUMS)
[[ -n "$EXPECT" ]] || { echo "no sha256 entry for $XZ_NAME"; exit 1; }

if (( DRY )); then
  echo "[dry-run] would stream $BASE/$XZ_NAME -> $INACTIVE (verify sha256=$EXPECT)"
  echo "[dry-run] would: sfdisk --part-label $DISK $PARTNUM store_${NEW}"
  echo "[dry-run] would: install -m0444 hil-runner_${NEW}.efi /boot/EFI/Linux/hil-runner_${NEW}.efi"
  echo "[dry-run] done."
  exit 0
fi

# Store image is ~2 GB compressed — too big for /tmp tmpfs. Stream it
# straight through xz into the inactive partition, no on-disk copy.
# tee branches the compressed bytes to sha256sum so we verify integrity
# without buffering the whole .xz to disk.
echo "Streaming store image to $INACTIVE ..."
curl -fsSL "$BASE/$XZ_NAME" \
  | tee >(sha256sum | awk '{print $1}' > sum.txt) \
  | xz -dc \
  | dd of="$INACTIVE" bs=4M conv=fsync status=progress
# Wait for the tee subshell to finish flushing sum.txt.
wait
GOT=$(cat sum.txt)
if [[ "$GOT" != "$EXPECT" ]]; then
  echo "ERROR: sha256 mismatch on $XZ_NAME"
  echo "  expected: $EXPECT"
  echo "  got:      $GOT"
  echo "Inactive slot ($INACTIVE) still carries its previous label — previous"
  echo "UKI keeps booting fine. Re-run hil-update to retry."
  exit 1
fi
echo "sha256 ok: $GOT"

# Rename the GPT partition label so the new UKI's fileSystems entry
# (mounted by /dev/disk/by-partlabel/store_<version>) resolves on boot.
# Use sfdisk from util-linux — always present, unlike sgdisk.
sfdisk --part-label "$DISK" "$PARTNUM" "store_${NEW}"
udevadm settle

# Remove any previously-staged UKIs from /boot/EFI/Linux/ before
# installing the new one. The ESP is a fixed 256 MB partition; without
# this the two UKI files (~30 MB each) plus BOOTAA64.EFI fill it and
# block the install. Keep the currently-running UKI so we can still boot
# the old slot if something goes wrong.
INSTALL_DIR="/boot/EFI/Linux"
# Keep the currently-running UKI so we can still boot the old slot if
# something goes wrong. The running UKI has the active store version in
# its name (e.g. hil-runner_2026.5.8.2333.efi).
RUNNING_EFI="hil-runner_${ACTIVE_VER}.efi"
shopt -s nullglob
for f in "$INSTALL_DIR"/hil-runner_*.efi; do
  [[ "${f##*/}" == "$RUNNING_EFI" ]] && continue
  echo "Removing stale UKI: ${f##*/}"
  rm -f "$f"
done
shopt -u nullglob

install -m0444 "hil-runner_${NEW}.efi" "/boot/EFI/Linux/hil-runner_${NEW}.efi"

echo "Update staged ($NEW). Reboot to switch."
