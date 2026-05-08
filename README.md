# nix-hil-runner

Reproducible NixOS A/B image for ARM SBCs (Raspberry Pi 4) that boots into
a generic, unconfigured state and is provisioned interactively into a
GitHub Actions self-hosted runner. CI publishes a single generic raw image
artifact for every device.

## How it works

1. **CI builds one generic image.** No per-device data is baked in.
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

## Image layout

`nix build .#image` produces a `systemd-repart`-built raw image:

| Partition | Purpose                                            |
|-----------|---------------------------------------------------|
| `ESP`     | pftf RPi4 UEFI firmware + systemd-boot + UKI       |
| `store_1` | nix-store slot A (squashfs, read-only)             |
| `_empty`  | nix-store slot B (filled by first OTA update)      |
| `perm`    | persistent `/perm` (survives OTA)                  |
| `root`    | mutable root filesystem                            |

Boot path: Pi GPU → pftf `RPI_EFI.fd` → systemd-boot → UKI from `/EFI/Linux`.

## Building

```bash
# Native ARM build
nix build .#packages.aarch64-linux.image

# Cross-compile from x86_64
nix build .#packages.x86_64-linux.image
```

CI (`release.yml`) builds the same image on every push to `master` and
publishes a gzip-compressed raw image on release tags.

## Flashing & first boot

```bash
gzip -dc result/*.raw.gz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

Boot the device, find its IP, then:

```bash
ssh root@<device-ip>     # password: root
hil-setup                # follow the prompts
# device reboots into hardened mode
```

To return to first-boot mode: `sudo rm /perm/configured && sudo reboot`.

## OTA updates

`systemd-sysupdate` swaps the inactive nix-store partition and the UKI
on update; `/perm` is untouched.

```bash
updatectl check
updatectl update
sudo reboot
```

Updates fetch versioned `*.store.raw` and `*.efi` from the URL configured
in `modules/sysupdate.nix`. Reboot selects the new version via
systemd-boot; rolling back is a boot menu choice.

## /perm layout

| Path                       | Purpose                                       |
|----------------------------|-----------------------------------------------|
| `/perm/configured`         | marker — gates first-boot vs hardened         |
| `/perm/hostname`           | one line, set via `hostnamectl` at boot       |
| `/perm/authorized_keys`    | synced to `/etc/ssh/authorized_keys.d/{root,hil}` |
| `/perm/runner.token`       | GitHub runner registration token              |
| `/perm/runner.env`         | `URL=`, `NAME=`, `LABELS=`                    |

## Repository layout

```
flake.nix                     # inputs + nixosConfigurations
hosts/pi4/configuration.nix   # imports modules + nix/network defaults
modules/
  image-ab.nix                # systemd-repart partition layout
  uki-boot.nix                # systemd-boot + UKI
  sysupdate.nix               # systemd-sysupdate transfers + update package
  pi-uefi.nix                 # pftf RPi4 UEFI firmware staging
  perm.nix                    # /perm + hil-perm-sync.service
  firstboot.nix               # hil-firstboot.service (mode toggle)
  hil-setup.nix               # interactive setup wizard
  users.nix                   # hil user, sshd defaults
  runner.nix                  # hil-runner.service (runtime-configured)
  ci-tools.nix                # probe-rs, espflash, udev rules
  base-packages.nix           # baseline CLI tools
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

## Caveats

This image has not been booted on real hardware yet. Likely iteration points:

- exact pftf payload layout staged on the ESP
- `sysupdate.nix` `Path` URL — currently a GitHub Releases pattern; adjust
  to your release strategy (e.g. GitHub Pages, signed releases)
- size budgets (256M ESP, 3G store) — bump if the closure outgrows them
- UKI generation under cross-compile
