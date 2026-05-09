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

## Updating an already-flashed device

`scripts/hil-update.sh` is the manual bridge until `systemd-sysupdate` is wired
up everywhere. It pulls the latest store image and UKI from the rolling
`updates` GitHub release, streams the xz-compressed store into the inactive
A/B slot, relabels its GPT partition (`store_<version>`), and drops the new
UKI alongside the existing one in `/boot/EFI/Linux`. The old slot stays
intact for rollback; reboot to switch — systemd-boot defaults to the newest
UKI.

One-liner (needs `sudo`; otherwise non-interactive):

```bash
curl -fsSL https://raw.githubusercontent.com/denysvitali/nix-hil-runner/master/scripts/hil-update.sh \
  | sudo bash
```

Or save and run:

```bash
wget https://raw.githubusercontent.com/denysvitali/nix-hil-runner/master/scripts/hil-update.sh
chmod +x hil-update.sh
sudo ./hil-update.sh
```

Use this when `updatectl`/sysupdate isn't yet active on the device. Once
sysupdate is wired in (see below), prefer that path.

## Rollback

`scripts/hil-rollback.sh` flips the next boot to the other UKI without
touching the default. It uses `bootctl set-oneshot` so the change applies to
exactly one boot; pass `--persistent` to make it sticky.

```bash
sudo scripts/hil-rollback.sh --list      # show available UKIs / slots
sudo scripts/hil-rollback.sh             # one-shot rollback on next boot
sudo reboot
```

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

## Troubleshooting

- **Setup wizard can't be reached.** Attach a serial console or plug in
  wired ethernet; check link/DHCP with `nmcli device status`.
- **Runner not connecting.** Inspect `journalctl -u hil-runner` and
  `cat /perm/runner.env`. Re-enter the registration token with:
  ```bash
  sudoedit /perm/runner.token
  sudo systemctl restart hil-runner
  ```
- **After OTA, `/nix/store` mount fails.** From the systemd-boot menu pick
  the previous UKI to boot back into the old slot, then make it sticky:
  ```bash
  sudo scripts/hil-rollback.sh --persistent
  ```
- **Stuck in first-boot mode.** Confirm the marker file is present:
  ```bash
  ls -la /perm/
  ```
  If `/perm/configured` is missing, re-run `hil-setup` (or `sudo touch
  /perm/configured` once the rest of `/perm` is populated) and reboot.

## Contributing

Contributions welcome — see [`CONTRIBUTING.md`](CONTRIBUTING.md) for the
development workflow, build/test expectations, and commit conventions.

## Caveats

Real-hardware coverage is still limited; expect rough edges. Likely
iteration points:

- exact pftf payload layout staged on the ESP
- `sysupdate.nix` `Path` URL — currently a GitHub Releases pattern; adjust
  to your release strategy (e.g. GitHub Pages, signed releases)
- size budgets (256M ESP, 3G store) — bump if the closure outgrows them
- UKI generation under cross-compile
