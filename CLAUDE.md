# CLAUDE.md

## Project Overview

Generic NixOS image for ARM SBCs that boots unconfigured and is provisioned
into a GitHub Actions self-hosted runner via an interactive first-boot wizard.
All per-device state lives on the `/perm` layer; CI ships a single image for
every device.

## Build commands

```bash
nix build .#packages.aarch64-linux.pi4-sd-image
nix flake check --no-build
```

## State machine

- `/perm/configured` absent → **first-boot mode**
  - root password = "root", PasswordAuthentication forced on via sshd drop-in
  - `/etc/motd` shows setup banner
  - User runs `hil-setup` (interactive), which writes `/perm/*` and reboots
- `/perm/configured` present → **hardened mode**
  - root password locked, sshd drop-in removed
  - `hil-perm-sync` syncs keys + hostname from `/perm`
  - `hil-runner.service` registers the runner and starts it

## Module map

| Module | Responsibility |
|---|---|
| `modules/perm.nix` | `/perm` tmpfiles + `hil-perm-sync.service` |
| `modules/firstboot.nix` | `hil-firstboot.service` (mode toggle, sshd drop-in, motd) |
| `modules/hil-setup.nix` | packages the `hil-setup` wizard |
| `modules/users.nix` | `hil` user, sshd defaults (key-only by default) |
| `modules/runner.nix` | `hil-runner.service` — runtime-configured runner unit |
| `modules/self-update.nix` | hourly `nixos-rebuild` from upstream |
| `modules/ci-tools.nix` | probe-rs, espflash, USB udev rules |
| `modules/base-packages.nix` | baseline CLI tools |

## Important: NixOS settings vs runtime config

The runner URL, labels, and token are NOT part of the NixOS configuration —
they're consumed at runtime by `hil-runner.service` via `EnvironmentFile=/perm/runner.env`
and `cat /perm/runner.token`. This bypasses `services.github-runners` because
that module bakes URL/name/labels at build time.

The hostname uses `lib.mkDefault "hil-runner"` so `hostnamectl set-hostname`
at runtime works without conflicts.

## /perm contents

- `configured`        — marker file
- `hostname`          — one line
- `authorized_keys`   — synced to `/etc/ssh/authorized_keys.d/{root,hil}`
- `runner.token`      — registration token (read by runner unit at start)
- `runner.env`        — `URL=`, `NAME=`, `LABELS=`
- `self-update.env`   — optional overrides for self-update

## Rotating credentials

```bash
sudoedit /perm/authorized_keys && sudo systemctl restart hil-perm-sync
sudoedit /perm/runner.token    && sudo systemctl restart hil-runner
```

## Stage 2 (not yet implemented)

`/perm` is currently a directory on the rootfs (survives rebuilds, not
reflashes). Stage 2 will promote it to a dedicated partition using
`systemd-repart`, alongside A/B nix-store partitions and `systemd-sysupdate`
for OTA partial reflashing.
