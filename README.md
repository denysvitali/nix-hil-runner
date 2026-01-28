# NixOS Raspberry Pi 4 - GPS Tracker Runner

Reproducible, updatable NixOS SD image for Raspberry Pi 4 with GitHub Actions self-hosted runner for the [gps-tracker-tr003-v2](https://github.com/denysvitali/gps-tracker-tr003-v2) project.

## Features

- **NixOS unstable** (rolling release)
- **Immutable rootfs** via NixOS generation system
- **Atomic remote upgrades** via SSH with native rollback
- **CI Tools**: probe-rs, cargo, espflash, rustc
- **GitHub Actions** self-hosted runner (pre-configured)
- **Aarch64 emulation** support for x86_64 build machines
- **Modular configuration** for easy customization

## Architecture

No A/B partitioning needed - NixOS provides "A/B-like" behavior through its **generation system**:
- Each `nixos-rebuild` creates a new generation
- Rollbacks are native - select an older generation at boot
- See: https://nixos.org/manual/nixos/stable/#sec-rollback

## Directory Structure

```
nix-hil-runner/
├── flake.nix                 # Flake inputs and outputs
├── hosts/
│   └── pi4/
│       ├── configuration.nix  # Main system config
│       └── hardware.nix       # Pi 4 specific hardware
├── modules/
│   ├── github-runner.nix     # GitHub Actions runner module
│   ├── ci-tools.nix          # CI/Embedded development tools
│   └── base-packages.nix     # Base system packages
└── README.md                 # This file
```

## Prerequisites

- **Build machine**: x86_64 Linux with aarch64 emulation, or native ARM machine
- **Target**: Raspberry Pi 4 with >= 16GB SD card
- **GitHub token**: Personal Access Token with `repo` scope (for GitHub Actions runner)

## Building

### On x86_64 Linux (with emulation)

```bash
# Build the SD image
nix build .#pi4-sd-image

# Result is in result/sd-image/nixos.img
```

### On Native ARM

```bash
nix build .#pi4-sd-image
```

## Flashing the SD Card

```bash
# Identify your SD card device (BE CAREFUL!)
lsblk

# Flash to SD card (replace /dev/sdX with your device)
sudo dd if=result/sd-image/nixos.img of=/dev/sdX bs=1M status=progress conv=fsync

# Or use bmaptool (faster)
sudo bmaptool copy result/sd-image/nixos.img /dev/sdX
```

## Initial Setup

### Step 1: Add Your SSH Keys

Before flashing, edit `hosts/pi4/configuration.nix` and add your SSH public key:

```nix
users.users.pi.openssh.authorizedKeys.keys = [
  "ssh-ed25519 AAAAC3Nza... your-public-key-here"
];
```

Then rebuild the image with your changes:

```bash
nix build .#pi4-sd-image
```

### Step 2: Boot and Configure Runner Token

1. Insert SD card and power on the Pi
2. SSH into the Pi: `ssh pi@pi4-gps-tracker.local` (find the IP via your router)
3. Add your GitHub runner token:

```bash
# Edit the token file (replace with your actual token)
echo -n "YOUR_GITHUB_PAT_TOKEN" | sudo tee /var/lib/github-runner/.token

# Restart the runner service
sudo systemctl restart github-runner-pi4.service
```

### Getting the Runner Token

1. Go to https://github.com/denysvitali/gps-tracker-tr003-v2/settings/actions/runners/new
2. Click "New self-hosted runner"
3. Copy the token (not the entire command, just the token)

### Verify Runner is Running

```bash
# Check runner status
sudo systemctl status github-runner-pi4.service

# View logs
sudo journalctl -u github-runner-pi4.service -f
```

## Remote Upgrades

From your workstation (requires SSH access):

```bash
nixos-rebuild switch --flake .#pi4-aarch64 \
  --target-host pi@<PI_IP> \
  --use-remote-sudo
```

This will:
1. Build on your workstation (with aarch64 emulation)
2. Transfer closure to the Pi
3. Atomically activate new generation
4. Keep old generation for rollback

## Updating the System

### 1. Update Flake Inputs

This updates `nixpkgs` and other inputs to their latest versions:

```bash
# On your workstation
cd /path/to/nix-hil-runner
nix flake update
```

### 2. Rebuild with New Configuration

Apply the updated inputs or local config changes:

```bash
# Remote deployment
nixos-rebuild switch --flake .#pi4-aarch64 \
  --target-host pi@pi4-gps-tracker.local \
  --use-remote-sudo
```

### Rollback if Something Breaks

If an upgrade causes issues, rollback to the previous generation:

```bash
# On the Pi
sudo nixos-rebuild switch --rollback
```

## Persistence

These paths survive `nixos-rebuild`:

- `/var/lib/github-runner/` - Runner data + token (persistent)
- `/home/pi/` - User files
- `/root/` - Root files

The runner token file (`/var/lib/github-runner/.token`) persists across system updates.

## Installed Packages

| Package | Description |
|---------|-------------|
| `probe-rs` | JTAG/SWD debugger |
| `espflash` | Espressif chip flasher |
| `cargo`, `rustc`, `rustfmt`, `clippy` | Rust toolchain |
| `git` | Version control |
| `vim`, `nano` | Text editors |
| `htop` | Process viewer |

## Troubleshooting

### Can't SSH after first boot

- Ensure you added your SSH key before building the image
- Check the authorized_keys file: `cat ~/.ssh/authorized_keys`
- Verify SSH service is running: `sudo systemctl status sshd`

### Runner not starting

```bash
# Check runner status
sudo systemctl status github-runner-pi4.service

# View logs
sudo journalctl -u github-runner-pi4.service -f

# Check if token file exists
cat /var/lib/github-runner/.token
```

### Runner needs new token

Tokens expire after a certain time. To update:

```bash
# Get a new token from GitHub Actions settings
echo -n "NEW_TOKEN" | sudo tee /var/lib/github-runner/.token
sudo systemctl restart github-runner-pi4.service
```

### Build fails with "unsupported platform"

Ensure you're not cross-compiling without emulation:

```bash
# On x86_64, ensure binfmt is registered
sudo systemctl restart systemd-binfmt.service
```

## Customization

### Adding System Packages

Edit `modules/base-packages.nix`:

```nix
{ config, pkgs, ... }:
{
  config.environment.systemPackages = with pkgs; [
    git
    nano
    htop
    curl
    wget
    vim
    # Add your packages here
  ];
}
```

### Changing Hostname

Edit `hosts/pi4/configuration.nix`:

```nix
networking.hostName = "your-hostname";
```

### Disabling the GitHub Runner

Edit `hosts/pi4/configuration.nix`:

```nix
services.github-runners.pi4.enable = false;
```

## References

- [NixOS on Raspberry Pi](https://nixos.org/manual/nixos/stable/#sec-raspberry-pi)
- [GitHub Self-Hosted Runners](https://docs.github.com/en/actions/hosting-your-own-runners)
- [probe-rs](https://probe.rs/)
- [espflash](https://github.com/esp-rs/espflash)
- [NixOS Generations & Rollback](https://nixos.org/manual/nixos/stable/#sec-rollback)
