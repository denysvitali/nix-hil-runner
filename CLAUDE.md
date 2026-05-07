# CLAUDE.md

## Project Overview

NixOS image for ARM SBCs hosting a GitHub Actions self-hosted runner with
embedded-dev tooling (probe-rs, espflash, Rust). Generic via `hil.*` options;
shipped host is `hosts/pi4` (Raspberry Pi 4).

## Build commands

```bash
nix build .#packages.aarch64-linux.pi4-sd-image
nix build .#nixosConfigurations.pi4-aarch64.config.system.build.toplevel
nix flake check
```

## Architecture

- Flake-based, nixpkgs/nixos-unstable.
- Modules under `modules/` are board-agnostic; per-host config in `hosts/<name>/`.
- All host parameters flow through `hil.*` options declared in `modules/settings.nix`.
- SSH keys and runner token are NOT baked into the image — they live on the
  FAT32 firmware partition under `/boot/firmware/hil-config/` and are synced
  to runtime locations by `hil-config-sync.service` on every boot.

## Module map

- `modules/settings.nix` — declares `hil.*` options
- `modules/persistent-config.nix` — `hil-config-sync.service`, the only thing
  that touches `/boot/firmware/hil-config/`
- `modules/users.nix` — primary user (`hil.user`), sshd config
- `modules/github-runner.nix` — registers runner using `hil.runner.*`
- `modules/self-update.nix` — hourly `nixos-rebuild` from `hil.selfUpdate.repoUrl`
- `modules/ci-tools.nix` — probe-rs/espflash + USB udev rules
- `modules/base-packages.nix` — baseline CLI tools

## Persistent paths

- `/boot/firmware/hil-config/` — source of truth (authorized_keys, runner.token)
- `/var/lib/github-runner/` — runner state (also written by config-sync)
- `/var/lib/nix-hil-runner/` — self-update flake checkout

## Rotating keys / tokens

Edit `/boot/firmware/hil-config/authorized_keys` or `runner.token`, then:

```bash
sudo systemctl restart hil-config-sync.service github-runner-<name>.service
```

No rebuild required.
