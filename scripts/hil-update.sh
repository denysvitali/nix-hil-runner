#!/usr/bin/env bash
# In-place A/B update for hil-runner devices that don't have systemd-sysupdate
# wired up yet. Pulls the latest store image + UKI from the rolling 'updates'
# release, writes the store into the inactive slot, relabels its GPT partition,
# drops the new UKI next to the existing one, and leaves the boot decision to
# systemd-boot's newest-UKI default. Old slot stays intact for rollback.
set -euo pipefail

BASE=${BASE:-https://github.com/denysvitali/nix-hil-runner/releases/download/updates}
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
  echo "Refusing to update: new version equals running version."
  exit 1
fi

INACTIVE=$(lsblk -lnpo NAME,PARTLABEL "$DISK" \
  | awk -v a="$ACTIVE" '$1!=a && ($2=="_empty" || $2 ~ /^store_/) {print $1; exit}')
[[ -n "$INACTIVE" ]] || { echo "no inactive store slot found"; exit 1; }
PARTNUM=$(echo "$INACTIVE" | grep -oE '[0-9]+$')
echo "Inactive: $INACTIVE (partition #$PARTNUM on $DISK)"

# UKI is small (~30 MB), fits in tmpfs — download + verify locally.
curl -fsSLO "$BASE/hil-runner_${NEW}.efi"
sha256sum --ignore-missing -c <(grep "hil-runner_${NEW}.efi" SHA256SUMS)

# Store image is ~2 GB compressed — too big for /tmp tmpfs. Stream it
# straight through xz into the inactive partition, no on-disk copy.
# We skip the .xz sha256 check (TLS protects transit, and a corrupt
# squashfs will fail to mount on boot — at which point pick the old UKI
# from the systemd-boot menu and retry).
echo "Streaming store image to $INACTIVE ..."
curl -fsSL "$BASE/hil-runner_${NEW}.store.raw.xz" \
  | xz -dc \
  | dd of="$INACTIVE" bs=4M conv=fsync status=progress

# Rename the GPT partition label so the new UKI's fileSystems entry
# (mounted by /dev/disk/by-partlabel/store_<version>) resolves on boot.
# Use sfdisk from util-linux — always present, unlike sgdisk.
sfdisk --part-label "$DISK" "$PARTNUM" "store_${NEW}"
udevadm settle

install -m0444 "hil-runner_${NEW}.efi" "/boot/EFI/Linux/hil-runner_${NEW}.efi"

echo "Update staged ($NEW). Reboot to switch."
