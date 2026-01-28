# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

NixOS Raspberry Pi 4 Smoke Test Image - a reproducible, updatable NixOS SD image for Raspberry Pi 4 with GitHub Actions self-hosted runner support.

## Build Commands

```bash
# Build SD image for flashing
nix build .#packages.aarch64-linux.pi4-sd-image

# Build system toplevel (for remote deployment)
nix build .#nixosConfigurations.pi4.config.system.build.toplevel

# Validate flake configuration
nix flake check

# Show available flake outputs
nix flake show
```

## Remote Deployment

```bash
# Atomic remote upgrade via SSH
nixos-rebuild switch --flake .#pi4 \
  --target-host pi@<PI_IP> \
  --use-remote-sudo

# Rollback via SSH
nixos-rebuild switch --rollback
```

## Architecture

- **Flake-based**: Uses `flake.nix` with nixpkgs/nixos-unstable
- **Target**: `aarch64-linux` (Raspberry Pi 4)
- **No A/B partitioning**: Relies on NixOS generation system for rollbacks
- **Module structure**: `hosts/pi4/configuration.nix` (main config) + `hosts/pi4/hardware.nix` (Pi-specific)

## Key Configuration Points

- **SSH keys**: Add in `users.users.pi.openssh.authorizedKeys.keys`
- **CI tools**: `probe-rs-tools`, `espflash`, `cargo`, `rustc`

## Enabling GitHub Runner After First Boot

The GitHub Actions runner is disabled by default in the SD image. To enable it after first boot:

1. **SSH into the Pi**:
   ```bash
   ssh pi@<PI_IP>
   ```

2. **Edit the configuration**:
   ```bash
   sudo nano /etc/nixos/configuration.nix
   ```

3. **Modify the github-runners section**:
   ```nix
   services.github-runners.pi4-smoke-test = {
     enable = true;  # Change from false to true
     name = "pi4-smoke-test";
     # Set your GitHub repository or organization URL
     url = "https://github.com/your-org/your-repo";
     # Set token file path (create this file next)
     tokenFile = "/var/lib/github-runner/.runner_token";
     # ... keep other settings
   };
   ```

4. **Create the token file**:
   ```bash
   sudo mkdir -p /var/lib/github-runner
   sudo nano /var/lib/github-runner/.runner_token
   # Paste your token (no newline)
   echo -n 'YOUR_TOKEN_HERE' | sudo tee /var/lib/github-runner/.runner_token
   sudo chmod 0600 /var/lib/github-runner/.runner_token
   ```

5. **Rebuild and switch**:
   ```bash
   sudo nixos-rebuild switch
   ```

**Token types**: Use a fine-grained Personal Access Token (PAT) with "Read and Write access to self-hosted runners" scope. Classic PATs with `repo` scope also work.

## Persistent Paths

- `/var/lib/github-runner/` - Runner data + token
- `/home/pi/` - User files
- `/root/` - Root files
