# NixOS Raspberry Pi 4 Smoke Test Image

Reproducible, updatable NixOS SD image for Raspberry Pi 4 with GitHub Actions self-hosted runner.

## Features

- **NixOS unstable** (rolling release)
- **Immutable rootfs** via NixOS generation system
- **Atomic remote upgrades** via SSH with native rollback
- **CI Tools**: probe-rs, cargo, espflash
- **GitHub Actions** self-hosted runner (`pi4-smoke-test`)
- **Aarch64 emulation** support for x86_64 build machines
- **TUI-based first-boot setup** for easy configuration

## Architecture

No A/B partitioning needed - NixOS provides "A/B-like" behavior through its **generation system**:
- Each `nixos-rebuild` creates a new generation
- Rollbacks are native - select an older generation at boot
- See: https://nixos.org/manual/nixos/stable/#sec-rollback

## Directory Structure

```
nix-hil-rpi/
├── flake.nix                 # Flake inputs and outputs
├── hosts/
│   └── pi4/
│       ├── configuration.nix  # Main system config
│       └── hardware.nix       # Pi 4 specific hardware
├── pkgs/
│   └── setup-tool/            # TUI-based first-boot setup tool
│       ├── default.nix        # Package definition
│       └── setup-tool.py      # Setup tool implementation
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
nix build .#nixosConfigurations.pi4.config.system.build.sdImage

# Result is in result/sd-image/nixos.img
```

### On Native ARM

```bash
nix build .#sdImage
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

## First Boot Setup

When you boot the Raspberry Pi for the first time, an interactive TUI setup tool will automatically appear on `tty1` (the main console). This tool configures the essential settings needed before the system is fully operational.

### Default Login Credentials

For the first boot only, you can log in via console or SSH using:
- **Username**: `pi`
- **Password**: `nixos`

> ⚠️ **Important**: These credentials are temporary and only work until the setup tool completes. SSH password authentication will be **disabled** after setup finishes.

### The TUI Setup Tool

The setup tool runs automatically on first boot and guides you through configuration:

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│     🍓 NixOS Raspberry Pi 4 Post-Boot Configuration Tool 🍓     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

Welcome! This tool will help you configure your NixOS Raspberry Pi.

Required Configuration:
  • SSH Authorized Keys (enables SSH access)
  • GitHub Actions Runner Token
  • GitHub Actions Runner URL

Optional Configuration:
  • Hostname (default: pi4-smoke-test)
  • Timezone (default: UTC)
  • WiFi Credentials (if WiFi interface detected)

Press Start to begin the configuration process.
```

### What Gets Configured

The setup tool will configure:

1. **SSH Keys** (required) - Choose one of:
   - Fetch from GitHub username
   - Paste public key directly
   - Load from USB/SD card file

2. **GitHub Actions Runner** (required):
   - Runner token (PAT with `repo` scope)
   - Runner URL (default: this repo)

3. **System Settings** (optional):
   - Hostname (default: `pi4-smoke-test`)
   - Timezone (default: `UTC`)
   - WiFi credentials (if WiFi detected)

4. **Final Application**:
   - Runs `nixos-rebuild switch` to apply all changes
   - Disables SSH password authentication
   - Creates completion flag to prevent re-running

### After Setup Completes

Once the setup tool finishes:
- ✅ SSH key-based authentication is enabled
- ✅ SSH password authentication is **disabled**
- ✅ GitHub Actions runner is configured and will start
- ✅ System hostname and timezone are set
- ✅ WiFi is configured (if provided)

You can now SSH into the Pi using your configured key:
```bash
ssh pi@pi4-smoke-test.local
```

## Initial Boot

1. Insert SD card and power on the Pi
2. Wait for boot (LED pattern: rapid blinking → solid)
3. The TUI setup tool appears automatically on `tty1`
4. Complete the setup using either:
   - **Direct console**: Use a keyboard and monitor connected to the Pi
   - **SSH**: Find the Pi's IP and SSH in with the temporary credentials

### Finding the Pi's IP Address

```bash
# Using mDNS
avahi-resolve -n pi4-smoke-test.local

# Or check your router's DHCP lease table
```

### Post-Setup SSH Access

After the setup tool completes, **only key-based SSH authentication works**. The temporary password `nixos` will no longer function for SSH.

```bash
# SSH using your configured key
ssh pi@<IP>
```

## Remote Upgrades

From your workstation (requires SSH access):

```bash
nixos-rebuild switch --flake .#pi4 \
  --target-host pi@<PI_IP> \
  --use-remote-sudo
```

This will:
1. Build on your workstation (with aarch64 emulation)
2. Transfer closure to the Pi
3. Atomically activate new generation
4. Keep old generation for rollback

## In-Place Upgrades

Once NixOS is running on the Raspberry Pi, you can perform upgrades directly on the device or from a remote machine.

### Updating the System

#### 1. Update Flake Inputs

This updates `nixpkgs` and other inputs to their latest versions:

```bash
# On the Pi or your workstation
cd /etc/nixos  # or wherever your flake is
nix flake update
```

#### 2. Rebuild with New Configuration

Apply the updated inputs or local config changes:

```bash
# On the Pi (in-place upgrade)
sudo nixos-rebuild switch --flake .#pi4-aarch64

# Or from a remote machine
nixos-rebuild switch --flake .#pi4-aarch64 \
  --target-host pi@<PI_IP> \
  --use-remote-sudo
```

### Understanding Upgrade Types

| Command | What It Does |
|---------|--------------|
| `nix flake update` | Updates `flake.lock` with latest `nixpkgs` and inputs |
| `nixos-rebuild switch --flake .#pi4-aarch64` | Builds and activates configuration using current `flake.lock` |
| `git pull && nixos-rebuild switch ...` | Updates configuration from git, then rebuilds |

- **Updating flake inputs**: Gets newer versions of NixOS packages
- **Rebuilding with local changes**: Applies your modified configuration
- **Upgrading from git**: Combines `git pull` with rebuild to get both new config and packages

### Rollback if Something Breaks

If an upgrade causes issues, rollback to the previous generation:

```bash
# Rollback to the previous generation
sudo nixos-rebuild switch --rollback

# Or at boot time (via serial console or monitor):
# At boot menu, select "NixOS - Boot options" → previous generation
```

### Cleaning Up Old Generations

After confirming everything works, clean up old generations to free disk space:

```bash
# Delete all old generations (keeps current only)
nix-collect-garbage -d

# Or delete generations older than 30 days
sudo nix-collect-garbage --delete-older-than 30d
```

> ⚠️ **Note**: Be careful with garbage collection if you might need to rollback. Old generations provide your safety net.

### Complete Remote Upgrade Example

From your workstation, updating everything:

```bash
# 1. Navigate to your flake repository
cd ~/projects/nix-hil-rpi

# 2. Pull latest configuration changes
git pull origin main

# 3. Update nixpkgs to latest
nix flake update

# 4. Deploy to Pi (builds locally, transfers, activates)
nixos-rebuild switch --flake .#pi4-aarch64 \
  --target-host pi@pi4-smoke-test.local \
  --use-remote-sudo

# 5. Verify the upgrade
ssh pi@pi4-smoke-test.local "sudo nixos-rebuild list-generations"
```

## Manual Setup Tool Usage

Normally, the setup tool runs automatically on first boot. However, you can also run it manually if needed.

### Running the Setup Tool

```bash
# Run the setup tool manually
sudo setup-tool
```

### Setup Completion Flag

The setup tool creates a flag file to prevent automatic re-running:

```bash
# Check if setup has completed
cat /var/lib/.nixos-setup-complete
```

If this file exists, the systemd service will not start the setup tool automatically on boot.

### Resetting the Setup Tool

To run the setup tool again on next boot:

```bash
# Remove the completion flag
sudo rm /var/lib/.nixos-setup-complete

# Reboot to trigger the setup service
sudo reboot
```

Alternatively, you can run it immediately without rebooting:

```bash
# Remove flag and run manually
sudo rm /var/lib/.nixos-setup-complete
sudo setup-tool
```

## Persistence

These paths survive `nixos-rebuild`:

- `/var/lib/github-runner/` - Runner data + token
- `/var/lib/.nixos-setup-complete` - Setup completion flag
- `/etc/nixos/` - Symlink to your git repo (optional)
- `/home/pi/` - User files
- `/root/` - Root files
- `/home/pi/.ssh/` - SSH keys and authorized_keys

## Installed Packages

| Package | Description |
|---------|-------------|
| `probe-rs` | JTAG/SWD debugger |
| `espflash` | Espressif chip flasher |
| `cargo` | Rust package manager |
| `rustc` | Rust compiler |
| `git` | Version control |
| `nano` | Simple editor |
| `htop` | Process viewer |
| `setup-tool` | TUI first-boot configuration |

## Troubleshooting

### Setup tool didn't appear

- Check that you're on `tty1` (press `Alt+F1` if on another console)
- Check the service status: `sudo systemctl status nixos-first-boot-setup`
- Run manually: `sudo setup-tool`
- Check for the completion flag: `ls -la /var/lib/.nixos-setup-complete`

### Can't SSH after setup

- Ensure you configured SSH keys in the setup tool
- Check the authorized_keys file: `cat /home/pi/.ssh/authorized_keys`
- Verify SSH service is running: `sudo systemctl status sshd`
- Check SSH is using key auth (password auth is disabled after setup)

### Forgot to set GitHub runner token

- **Option 1**: Re-run the setup tool:
  ```bash
  sudo setup-tool
  ```
- **Option 2**: Edit files directly:
  ```bash
  # Create token file
  echo "YOUR_GITHUB_PAT" | sudo tee /var/lib/github-runner/.runner_token > /dev/null
  sudo chown github-runner:github-runner /var/lib/github-runner/.runner_token
  sudo chmod 600 /var/lib/github-runner/.runner_token
  
  # Restart the runner service
  sudo systemctl restart github-runner-pi4-smoke-test.service
  ```

### Runner not starting

```bash
# Check runner status
sudo systemctl status github-runner-pi4-smoke-test.service

# View logs
sudo journalctl -u github-runner-pi4-smoke-test.service -f

# Check if token file exists
ls -la /var/lib/github-runner/.runner_token
```

### Build fails with "unsupported platform"

Ensure you're not cross-compiling without emulation:

```bash
# On x86_64, ensure binfmt is registered
sudo systemctl start binfmt-support
```

### Pi won't boot

1. Verify SD card is formatted as MBR (not GPT)
2. Check LED status:
   - No light: Power issue
   - 3 flashes: SD card not found
   - 4 flashes: Kernel not found

## References

- [NixOS on Raspberry Pi](https://nixos.org/manual/nixos/stable/#sec-raspberry-pi)
- [GitHub Self-Hosted Runners](https://docs.github.com/en/actions/hosting-your-own-runners)
- [probe-rs](https://probe.rs/)
- [espflash](https://github.com/esp-rs/espflash)
- [NixOS Generations & Rollback](https://nixos.org/manual/nixos/stable/#sec-rollback)
