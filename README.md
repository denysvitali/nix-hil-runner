# nix-hil-runner

Reproducible NixOS image for ARM SBCs that boots into a generic, unconfigured
state and is provisioned interactively into a GitHub Actions self-hosted
runner. All per-device customisation (hostname, SSH keys, runner registration)
lives on a persistent `/perm` layer, so the same CI-built image goes to every
device.

## How it works

1. **CI builds one generic image.** No per-host data is baked in.
2. **First boot — insecure mode.** The device:
   - accepts SSH password login as `root` / `root`
   - shows a setup banner with instructions
3. **`hil-setup`** (run as root) prompts for:
   - hostname
   - SSH authorized keys (paste, or `gh:<username>` to fetch from GitHub)
   - GitHub runner repo URL, name, labels, and registration token
   All values are written to `/perm/` and the device reboots.
4. **Subsequent boots — hardened mode.** Because `/perm/configured` exists:
   - root password is locked, password auth is disabled
   - SSH keys are synced from `/perm/authorized_keys`
   - hostname is set from `/perm/hostname`
   - the runner is registered (using `/perm/runner.{env,token}`) and started

## Building

```bash
# Native ARM build
nix build .#packages.aarch64-linux.pi4-sd-image

# Cross-compile from x86_64
nix build .#packages.x86_64-linux.pi4-sd-image
```

CI publishes the same artifact on every push to `master` and on `v*` tags.

## Flashing & first boot

```bash
sudo dd if=result/sd-image/*.img of=/dev/sdX bs=4M status=progress conv=fsync
```

Boot the device, find its IP, then:

```bash
ssh root@<device-ip>     # password: root
hil-setup                # follow the prompts
# device reboots into hardened mode
```

Re-running `hil-setup` after configuration is supported — it will rewrite
`/perm/` and reboot. To wipe configuration entirely:

```bash
sudo rm /perm/configured
sudo reboot              # device returns to first-boot mode
```

## /perm layout

| Path                       | Purpose                                       |
|----------------------------|-----------------------------------------------|
| `/perm/configured`         | marker file — gates first-boot vs hardened    |
| `/perm/hostname`           | one line, set via `hostnamectl` at boot       |
| `/perm/authorized_keys`    | SSH keys, synced to `/etc/ssh/authorized_keys.d/{root,hil}` |
| `/perm/runner.token`       | GitHub runner registration token              |
| `/perm/runner.env`         | `URL=`, `NAME=`, `LABELS=` (sourced by runner unit) |
| `/perm/self-update.env`    | optional `REPO_URL=`, `BRANCH=`, `FLAKE_ATTR=` overrides |

> The legacy SD image (`pi4-sd-image`) backs `/perm` with a directory on the
> rootfs — survives `nixos-rebuild`, not a full reflash. The A/B image
> (`pi4-ab-image`, see below) backs it with a real partition that survives
> OTA updates.

## A/B image with OTA updates (experimental)

`nix build .#pi4-ab-image` produces a `systemd-repart`-built raw image with:

| Partition | Purpose                                        |
|-----------|-----------------------------------------------|
| `ESP`     | pftf RPi4 UEFI firmware + systemd-boot + UKI  |
| `store_1` | nix-store slot A (squashfs, read-only)        |
| `_empty`  | nix-store slot B (filled by first OTA update) |
| `perm`    | persistent `/perm` (survives OTA)             |
| `root`    | mutable root filesystem                       |

Boot path: Pi GPU → pftf `RPI_EFI.fd` → systemd-boot → UKI from `/EFI/Linux`.

OTA updates are driven by `systemd-sysupdate`:

```bash
updatectl check
updatectl update
```

Updates fetch a versioned `*.store.raw` (new nix store slot) and a versioned
`*.efi` (new UKI), written into the inactive partition / ESP folder. Reboot
selects the new version; rolling back is a `systemd-boot` menu choice.

CI publishes per-tag releases (`v*`):
- `pi4-ab-image` — full bootable raw
- `pi4-ab-update-package` — `*.store.raw` + `*.efi` + `SHA256SUMS` for OTA

> ⚠️ **Untested on hardware.** This drop ships the design end-to-end and
> evaluates cleanly, but it has not been booted on a real Pi 4. Expect to
> iterate on:
> - exact pftf payload layout (the whole tree is staged at the ESP root)
> - sysupdate `Path` URL — currently points at the GitHub Releases
>   `latest` tag; adjust to your release strategy
> - UKI/kernel size vs ESP size (256MB) and store partition size (2GB)
>
> The legacy `pi4-sd-image` build remains the default and is unchanged.

## Repository layout

```
flake.nix                       # inputs + nixosConfigurations
hosts/pi4/
  configuration.nix             # imports modules + nix/network defaults
  hardware.nix                  # Pi 4 kernel/firmware
modules/
  perm.nix                      # /perm + hil-perm-sync.service
  firstboot.nix                 # hil-firstboot.service (mode toggle)
  hil-setup.nix                 # the interactive setup wizard
  users.nix                     # hil user, sshd defaults
  runner.nix                    # hil-runner.service (runtime-configured)
  self-update.nix               # hourly nixos-rebuild from upstream
  ci-tools.nix                  # probe-rs, espflash, udev rules
  base-packages.nix             # baseline CLI tools
```

## Rotating credentials without reboot

```bash
# Rotate SSH keys
sudoedit /perm/authorized_keys
sudo systemctl restart hil-perm-sync.service

# Rotate runner token
sudoedit /perm/runner.token
sudo systemctl restart hil-runner.service
```

## Rollback

```bash
sudo nixos-rebuild switch --rollback
```
