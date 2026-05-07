# nix-hil-runner

Reproducible, updatable NixOS image for ARM SBCs running a GitHub Actions
self-hosted runner with embedded development tools (probe-rs, espflash, Rust).

The shipped host (`hosts/pi4`) targets a Raspberry Pi 4, but the modules are
generic — adding another board is one host directory + a few `hil.*` settings.

## Design

- **NixOS unstable** flake-based config.
- **Generation-based rollback** today; A/B image partitioning is planned in
  Stage 2 (see `STAGE2.md` once it lands).
- **Runtime configuration via the firmware partition.** SSH keys and the
  GitHub runner registration token are read at boot from
  `/boot/firmware/hil-config/` — no rebuild needed to rotate keys or tokens.
- **Self-update timer** pulls this flake hourly and runs `nixos-rebuild switch`.

## Repository layout

```
flake.nix                       # inputs + nixosConfigurations
hosts/pi4/
  configuration.nix             # sets `hil.*` for this host
  hardware.nix                  # board-specific kernel/firmware
modules/
  settings.nix                  # `hil.*` option declarations
  persistent-config.nix         # syncs /boot/firmware/hil-config -> runtime
  users.nix                     # primary user + sshd
  github-runner.nix             # runner service, uses hil.runner.*
  ci-tools.nix                  # probe-rs, espflash, udev rules
  base-packages.nix             # baseline CLI tools
  self-update.nix               # hourly nixos-rebuild from upstream
```

## Building

```bash
# Native ARM build
nix build .#packages.aarch64-linux.pi4-sd-image

# Cross-compile from x86_64
nix build .#packages.x86_64-linux.pi4-sd-image
```

The image lands at `result/sd-image/*.img.zst`.

## First boot setup

The image ships with no SSH keys and no runner token baked in. Both are read
from a `hil-config/` directory on the firmware partition (FAT32 — mountable
from any OS).

### 1. Drop your config onto the SD card

After flashing, mount the FAT32 partition labeled `FIRMWARE` and create:

```
hil-config/
  authorized_keys     # one SSH public key per line, for root and the user
  runner.token        # GitHub runner registration token (no trailing newline)
```

You can also do this after first boot — the `hil-config-sync.service`
re-syncs on every boot.

### 2. Boot

```bash
sudo dd if=result/sd-image/*.img of=/dev/sdX bs=4M status=progress conv=fsync
```

On boot, `hil-config-sync.service` copies:
- `authorized_keys` → `/etc/ssh/authorized_keys.d/{root,<user>}` (mode 0600)
- `runner.token`    → `/var/lib/github-runner/.token` (mode 0600)

then sshd and the runner start.

### Getting a runner token

`https://github.com/<owner>/<repo>/settings/actions/runners/new` →
copy the token (just the token, not the whole `./config.sh` line).

Tokens expire (~1h) — to update, drop a new `runner.token` and
`systemctl restart hil-config-sync github-runner-<name>`.

## Per-host configuration

Each host sets its identity through `hil.*`:

```nix
hil = {
  hostname = "pi4-hil-runner";
  user = "hil";

  runner = {
    url = "https://github.com/<owner>/<repo>";
    name = "pi4-hil-runner";
    labels = [ "pi4" "aarch64" "nixos" ];
  };

  selfUpdate = {
    repoUrl = "https://github.com/<your-fork>/nix-hil-runner.git";
    flakeAttr = "pi4-aarch64";
  };
};
```

See `modules/settings.nix` for the full option set.

## Remote upgrades

```bash
nixos-rebuild switch --flake .#pi4-aarch64 \
  --target-host hil@<host> --use-remote-sudo
```

## Rollback

```bash
sudo nixos-rebuild switch --rollback     # on the device
```
