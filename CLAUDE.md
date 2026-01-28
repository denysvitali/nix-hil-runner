# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

NixOS Raspberry Pi 4 - GitHub Actions self-hosted runner for the gps-tracker-tr003-v2 project. A reproducible, updatable NixOS SD image with pre-configured runner and embedded development tools.

## Build Commands

```bash
# Build SD image for flashing
nix build .#pi4-sd-image

# Build system toplevel (for remote deployment)
nix build .#nixosConfigurations.pi4-aarch64.config.system.build.toplevel

# Validate flake configuration
nix flake check

# Show available flake outputs
nix flake show
```

## Remote Deployment

```bash
# Atomic remote upgrade via SSH
nixos-rebuild switch --flake .#pi4-aarch64 \
  --target-host pi@<PI_IP> \
  --use-remote-sudo

# Rollback via SSH (run on the Pi)
sudo nixos-rebuild switch --rollback
```

## Architecture

- **Flake-based**: Uses `flake.nix` with nixpkgs/nixos-unstable
- **Target**: `aarch64-linux` (Raspberry Pi 4)
- **No A/B partitioning**: Relies on NixOS generation system for rollbacks
- **Module structure**:
  - `hosts/pi4/configuration.nix` (main config)
  - `hosts/pi4/hardware.nix` (Pi-specific)
  - `modules/github-runner.nix` (GitHub Actions runner)
  - `modules/ci-tools.nix` (CI/Embedded tools)
  - `modules/base-packages.nix` (Base packages)

## Key Configuration Points

- **SSH keys**: Add in `hosts/pi4/configuration.nix` under `users.users.pi.openssh.authorizedKeys.keys`
- **GitHub runner**: Pre-configured for https://github.com/denysvitali/gps-tracker-tr003-v2
- **Runner token**: Must be added at `/var/lib/github-runner/.token` after first boot
- **CI tools**: probe-rs-tools, espflash, cargo, rustc, clippy, rustfmt

## Setting the Runner Token After First Boot

The GitHub Actions runner is enabled by default but needs a token to connect:

1. **SSH into the Pi**:
   ```bash
   ssh pi@<PI_IP>
   ```

2. **Add the runner token**:
   ```bash
   # Get token from: https://github.com/denysvitali/gps-tracker-tr003-v2/settings/actions/runners/new
   echo -n 'YOUR_TOKEN_HERE' | sudo tee /var/lib/github-runner/.token
   sudo chmod 0600 /var/lib/github-runner/.token
   ```

3. **Restart the runner service**:
   ```bash
   sudo systemctl restart github-runner-pi4.service
   ```

**Token types**: Use a fine-grained Personal Access Token (PAT) with "Read and Write access to self-hosted runners" scope. Classic PATs with `repo` scope also work.

## Persistent Paths

- `/var/lib/github-runner/` - Runner data + token (persists across rebuilds)
- `/home/pi/` - User files
- `/root/` - Root files

## Module System

When making changes, prefer adding to or modifying modules rather than adding to `configuration.nix`:

- **GitHub runner changes**: `modules/github-runner.nix`
- **CI tool changes**: `modules/ci-tools.nix`
- **Package additions**: `modules/base-packages.nix`
- **System settings**: `hosts/pi4/configuration.nix`
