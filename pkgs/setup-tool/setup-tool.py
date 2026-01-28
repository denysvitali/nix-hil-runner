#!/usr/bin/env python3
"""
NixOS Raspberry Pi Post-Boot Configuration Tool
A CLI-based setup wizard for configuring SSH keys, GitHub Actions runner,
hostname, timezone, and WiFi credentials.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional
from urllib.request import urlopen
from urllib.error import URLError

# Output file paths
SSH_DIR = Path("/root/.ssh")
AUTH_KEYS_FILE = SSH_DIR / "authorized_keys"
RUNNER_DIR = Path("/var/lib/github-runner")
RUNNER_TOKEN_FILE = RUNNER_DIR / ".runner_token"
RUNNER_URL_FILE = RUNNER_DIR / ".runner_url"
NIXOS_CONFIG_DIR = Path("/etc/nixos")

# Defaults
DEFAULT_HOSTNAME = "pi4-smoke-test"
DEFAULT_TIMEZONE = "UTC"
DEFAULT_RUNNER_URL = "https://github.com/denysvitali/nix-hil-rpi"


def validate_ssh_key(key: str) -> tuple[bool, str]:
    """Validate SSH public key format."""
    key = key.strip()
    if not key:
        return False, "SSH key is empty"

    # Common SSH key types
    valid_types = [
        "ssh-rsa",
        "ssh-ed25519",
        "ssh-dss",
        "ecdsa-sha2-nistp256",
        "ecdsa-sha2-nistp384",
        "ecdsa-sha2-nistp521",
        "sk-ssh-ed25519",
        "sk-ecdsa-sha2-nistp256",
    ]

    parts = key.split()
    if len(parts) < 2:
        return False, "Invalid SSH key format: must have at least type and key data"

    key_type = parts[0]
    if key_type not in valid_types:
        return False, f"Unsupported SSH key type: {key_type}"

    # Basic base64 validation (key data should be base64)
    key_data = parts[1]
    if not re.match(r'^[A-Za-z0-9+/]+={0,2}$', key_data):
        return False, "Invalid SSH key data (not valid base64)"

    return True, "Valid SSH key"


def fetch_github_keys(username: str) -> tuple[bool, str]:
    """Fetch SSH keys from GitHub."""
    if not username or not re.match(r'^[a-zA-Z0-9-]+$', username):
        return False, "Invalid GitHub username"

    try:
        url = f"https://github.com/{username}.keys"
        with urlopen(url, timeout=10) as response:
            keys = response.read().decode('utf-8').strip()
            if not keys:
                return False, f"No SSH keys found for GitHub user: {username}"
            return True, keys
    except URLError as e:
        return False, f"Failed to fetch keys from GitHub: {e}"
    except Exception as e:
        return False, f"Error fetching keys: {e}"


def read_key_from_file(path: str) -> tuple[bool, str]:
    """Read SSH key from file."""
    try:
        file_path = Path(path).expanduser()
        if not file_path.exists():
            return False, f"File not found: {path}"

        with open(file_path, 'r') as f:
            content = f.read().strip()
            if not content:
                return False, "File is empty"
            return True, content
    except Exception as e:
        return False, f"Error reading file: {e}"


def get_timezones() -> list[str]:
    """Get list of available timezones."""
    try:
        result = subprocess.run(
            ["timedatectl", "list-timezones"],
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode == 0:
            return result.stdout.strip().split('\n')
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass

    # Fallback to common timezones
    return [
        "UTC",
        "Europe/London",
        "Europe/Paris",
        "Europe/Berlin",
        "Europe/Zurich",
        "Europe/Rome",
        "America/New_York",
        "America/Los_Angeles",
        "America/Chicago",
        "Asia/Tokyo",
        "Asia/Shanghai",
        "Australia/Sydney",
    ]


def backup_file(path: Path) -> None:
    """Create a backup of a file if it exists."""
    if path.exists():
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_path = Path(f"{path}.backup.{timestamp}")
        shutil.copy2(path, backup_path)
        print(f"  Backed up: {path} -> {backup_path}")


def prompt_ssh_key() -> tuple[bool, str]:
    """Prompt user for SSH key."""
    print("\n" + "="*60)
    print("Step 1: SSH Key Configuration")
    print("="*60)
    print("\nHow would you like to provide your SSH public key?")
    print("1. Fetch from GitHub username")
    print("2. Paste public key directly")
    print("3. Load from file")
    print("4. Skip (not recommended)")

    choice = input("\nChoice (1-4): ").strip()

    if choice == "1":
        username = input("GitHub username: ").strip()
        if not username:
            print("Error: Username required")
            return False, ""
        print(f"Fetching keys for {username}...")
        return fetch_github_keys(username)

    elif choice == "2":
        print("\nPaste your SSH public key (press Enter twice when done):")
        lines = []
        while True:
            try:
                line = input()
                if line.strip() == "" and lines:
                    break
                if line:
                    lines.append(line)
            except EOFError:
                break
        key = "\n".join(lines).strip()
        is_valid, msg = validate_ssh_key(key)
        if is_valid:
            return True, key
        else:
            print(f"Error: {msg}")
            return False, ""

    elif choice == "3":
        path = input("File path: ").strip()
        return read_key_from_file(path)

    else:
        print("Skipping SSH key configuration.")
        return False, ""


def prompt_input(prompt: str, default: str = "", required: bool = True, password: bool = False) -> str:
    """Prompt for input with optional default value."""
    if default:
        full_prompt = f"{prompt} [{default}]: "
    else:
        full_prompt = f"{prompt}: "

    if password:
        import getpass
        value = getpass.getpass(full_prompt)
    else:
        value = input(full_prompt)

    value = value.strip()
    if not value:
        value = default

    if required and not value:
        print("Error: This field is required")
        return prompt_input(prompt, default, required, password)

    return value


def configure_ssh(ssh_key: str) -> bool:
    """Configure SSH authorized keys."""
    print("\n[1/6] Configuring SSH authorized keys...")

    try:
        # Create .ssh directory for root
        SSH_DIR.mkdir(parents=True, exist_ok=True)
        os.chmod(SSH_DIR, 0o700)

        # Backup existing authorized_keys
        backup_file(AUTH_KEYS_FILE)

        # Write new authorized_keys
        with open(AUTH_KEYS_FILE, 'w') as f:
            f.write(ssh_key + '\n')
        os.chmod(AUTH_KEYS_FILE, 0o600)

        # Set ownership to root (we're running as root)
        shutil.chown(SSH_DIR, "root", "root")
        shutil.chown(AUTH_KEYS_FILE, "root", "root")

        print("  ✓ SSH keys configured")
        return True

    except Exception as e:
        print(f"  ✗ Failed to configure SSH: {e}")
        return False


def configure_runner(token: str, url: str, hostname: str) -> bool:
    """Configure GitHub Actions runner."""
    print("\n[2/6] Configuring GitHub Actions runner...")

    try:
        import pwd

        # Ensure runner directory exists with correct permissions
        RUNNER_DIR.mkdir(parents=True, exist_ok=True)

        # Try to set ownership to github-runner if user exists
        try:
            pwd.getpwnam("github-runner")
            shutil.chown(RUNNER_DIR, "github-runner", "github-runner")
            runner_user = "github-runner"
            runner_group = "github-runner"
        except KeyError:
            # github-runner user doesn't exist, use root
            runner_user = "root"
            runner_group = "root"
            print("  Note: github-runner user not found, using root")

        # Backup existing files
        backup_file(RUNNER_TOKEN_FILE)
        backup_file(RUNNER_URL_FILE)

        # Write token
        with open(RUNNER_TOKEN_FILE, 'w') as f:
            f.write(token + '\n')
        os.chmod(RUNNER_TOKEN_FILE, 0o600)
        shutil.chown(RUNNER_TOKEN_FILE, runner_user, runner_group)

        # Write URL
        with open(RUNNER_URL_FILE, 'w') as f:
            f.write(url + '\n')
        os.chmod(RUNNER_URL_FILE, 0o600)
        shutil.chown(RUNNER_URL_FILE, runner_user, runner_group)

        # Generate github-runner.nix to enable the runner
        NIXOS_CONFIG_DIR.mkdir(parents=True, exist_ok=True)

        runner_nix = f'''# Generated by NixOS Raspberry Pi setup tool
{{ config, pkgs, lib, ... }}:
{{
  services.github-runners.{hostname} = {{
    enable = true;
    name = "{hostname}";
    url = "{url}";
    tokenFile = "{RUNNER_TOKEN_FILE}";
    extraLabels = [
      "self-hosted"
      "{hostname}"
      "aarch64"
      "nixos"
    ];
  }};
}}
'''
        backup_file(NIXOS_CONFIG_DIR / "github-runner.nix")
        with open(NIXOS_CONFIG_DIR / "github-runner.nix", 'w') as f:
            f.write(runner_nix)

        print("  ✓ GitHub runner configured and enabled")
        return True

    except Exception as e:
        print(f"  ✗ Failed to configure GitHub runner: {e}")
        return False


def configure_hostname(hostname: str) -> bool:
    """Generate hostname configuration."""
    print("\n[3/6] Configuring hostname...")

    try:
        NIXOS_CONFIG_DIR.mkdir(parents=True, exist_ok=True)

        hostname_nix = f'''# Generated by NixOS Raspberry Pi setup tool
{{ config, pkgs, lib, ... }}:
{{
  networking.hostName = "{hostname}";
}}
'''
        backup_file(NIXOS_CONFIG_DIR / "hostname.nix")
        with open(NIXOS_CONFIG_DIR / "hostname.nix", 'w') as f:
            f.write(hostname_nix)

        print(f"  ✓ Hostname set to: {hostname}")
        return True

    except Exception as e:
        print(f"  ✗ Failed to configure hostname: {e}")
        return False


def configure_timezone(timezone: str) -> bool:
    """Generate timezone configuration."""
    print("\n[4/6] Configuring timezone...")

    try:
        timezone_nix = f'''# Generated by NixOS Raspberry Pi setup tool
{{ config, pkgs, lib, ... }}:
{{
  time.timeZone = "{timezone}";
}}
'''
        backup_file(NIXOS_CONFIG_DIR / "timezone.nix")
        with open(NIXOS_CONFIG_DIR / "timezone.nix", 'w') as f:
            f.write(timezone_nix)

        print(f"  ✓ Timezone set to: {timezone}")
        return True

    except Exception as e:
        print(f"  ✗ Failed to configure timezone: {e}")
        return False


def configure_wifi(ssid: str, password: str, enable: bool) -> bool:
    """Generate WiFi configuration."""
    print("\n[5/6] Configuring WiFi...")

    try:
        if enable and ssid:
            wifi_nix = f'''# Generated by NixOS Raspberry Pi setup tool
{{ config, pkgs, lib, ... }}:
{{
  networking.wireless = {{
    enable = true;
    networks = {{
      "{ssid}" = {{
        psk = "{password}";
      }};
    }};
  }};
}}
'''
            backup_file(NIXOS_CONFIG_DIR / "wifi.nix")
            with open(NIXOS_CONFIG_DIR / "wifi.nix", 'w') as f:
                f.write(wifi_nix)
            print(f"  ✓ WiFi configured for network: {ssid}")
        else:
            # Remove wifi.nix if it exists and we're not configuring WiFi
            wifi_nix_path = NIXOS_CONFIG_DIR / "wifi.nix"
            if wifi_nix_path.exists():
                backup_file(wifi_nix_path)
                wifi_nix_path.unlink()
            print("  ✓ WiFi configuration skipped")

        return True

    except Exception as e:
        print(f"  ✗ Failed to configure WiFi: {e}")
        return False


def find_nixos_config() -> Optional[Path]:
    """Find the NixOS configuration file."""
    # Common locations
    possible_paths = [
        Path("/etc/nixos/configuration.nix"),
        Path("/etc/nixos/flake.nix"),
        Path("/nix/var/nixos/configuration.nix"),
    ]
    for path in possible_paths:
        if path.exists():
            return path
    return None


def clone_nixos_config(repo_url: str = "https://github.com/denysvitali/nix-hil-rpi") -> bool:
    """Clone the NixOS configuration repository to /etc/nixos."""
    print(f"  Cloning NixOS configuration from {repo_url}...")

    try:
        # Ensure /etc/nixos exists and is empty
        if NIXOS_CONFIG_DIR.exists():
            # Check if directory is empty
            if any(NIXOS_CONFIG_DIR.iterdir()):
                print(f"  Warning: {NIXOS_CONFIG_DIR} is not empty")
                response = input("  Remove existing contents and clone? (yes/no): ").strip().lower()
                if response != "yes":
                    return False
                # Backup existing directory
                backup_path = Path(f"{NIXOS_CONFIG_DIR}.backup.{datetime.now().strftime('%Y%m%d_%H%M%S')}")
                shutil.move(NIXOS_CONFIG_DIR, backup_path)
                print(f"  Backed up existing config to {backup_path}")
                NIXOS_CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        else:
            NIXOS_CONFIG_DIR.mkdir(parents=True, exist_ok=True)

        # Clone the repository
        result = subprocess.run(
            ["git", "clone", repo_url, str(NIXOS_CONFIG_DIR)],
            capture_output=True,
            text=True,
        )

        if result.returncode != 0:
            print(f"  ✗ Failed to clone repository: {result.stderr}")
            return False

        print(f"  ✓ Cloned repository to {NIXOS_CONFIG_DIR}")
        return True

    except Exception as e:
        print(f"  ✗ Failed to clone repository: {e}")
        return False


def get_flake_configs(flake_dir: Path) -> list[str]:
    """Get available NixOS configurations from flake.nix."""
    try:
        result = subprocess.run(
            ["nix", "flake", "show", str(flake_dir), "--json"],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0:
            import json
            data = json.loads(result.stdout)
            configs = []
            if "nixosConfigurations" in data:
                configs = list(data["nixosConfigurations"].keys())
            return configs
    except Exception as e:
        print(f"  Debug: Could not detect flake configs: {e}")
    return []


def get_config_name(flake_dir: Path) -> str:
    """Determine the NixOS configuration name to use."""
    # Try to detect from flake
    configs = get_flake_configs(flake_dir)
    if configs:
        if "pi4-aarch64" in configs:
            return "pi4-aarch64"
        elif "pi4-cross" in configs:
            return "pi4-cross"
        else:
            return configs[0]

    # Default based on architecture
    import platform
    machine = platform.machine()
    if machine == "aarch64":
        return "pi4-aarch64"
    else:
        return "pi4-cross"


def run_nixos_rebuild() -> bool:
    """Run nixos-rebuild switch."""
    print("\n[6/6] Running nixos-rebuild switch...")
    print("  (This may take a few minutes)")

    # Check if NixOS config exists
    config_path = find_nixos_config()
    if not config_path:
        print("  ⚠ No NixOS configuration found at /etc/nixos/")
        response = input("  Clone nix-hil-rpi repository to /etc/nixos? (yes/no) [yes]: ").strip().lower()
        if response in ("", "yes", "y"):
            if not clone_nixos_config():
                print("  Skipping nixos-rebuild. You'll need to set up the configuration manually.")
                return True
            # Re-check for config after cloning
            config_path = find_nixos_config()
            if not config_path:
                print("  ✗ Configuration still not found after cloning")
                return False
        else:
            print("  Skipping nixos-rebuild. You'll need to set up the configuration manually.")
            return True  # Not a fatal error

    # Check if we're in a flake-based setup
    flake_path = config_path.parent / "flake.nix" if config_path.name != "flake.nix" else config_path
    is_flake = flake_path.exists()

    try:
        # Enable experimental features needed for flakes
        env = os.environ.copy()
        env["NIX_CONFIG"] = "experimental-features = nix-command flakes"

        if is_flake:
            # For flake-based configs, detect available configurations
            print(f"  Using flake configuration: {flake_path.parent}")

            # Get the config name to use
            config_name = get_config_name(flake_path.parent)
            flake_target = f"{flake_path.parent}#{config_name}"
            print(f"  Using configuration: {config_name}")

            result = subprocess.run(
                ["nixos-rebuild", "switch", "--flake", flake_target],
                capture_output=True,
                text=True,
                env=env,
            )
        else:
            # For traditional configs, ensure NIX_PATH is set
            if "NIX_PATH" not in env:
                env["NIX_PATH"] = "nixos-config=/etc/nixos/configuration.nix:/nix/var/nix/profiles/per-user/root/channels"
            result = subprocess.run(
                ["nixos-rebuild", "switch"],
                capture_output=True,
                text=True,
                env=env,
            )

        if result.returncode != 0:
            error_msg = result.stderr[-1000:] if result.stderr else "Unknown error"
            print(f"  ✗ nixos-rebuild failed:\n{error_msg}")
            print("\n  You can try running manually:")
            if is_flake:
                config_name = get_config_name(flake_path.parent)
                print(f"    sudo nixos-rebuild switch --flake {flake_path.parent}#{config_name}")
            else:
                print("    sudo nixos-rebuild switch")
            return False

        print("  ✓ Configuration applied successfully")
        return True

    except Exception as e:
        print(f"  ✗ Failed to run nixos-rebuild: {e}")
        return False


def interactive_setup():
    """Run interactive setup."""
    print("="*60)
    print("NixOS Raspberry Pi Post-Boot Configuration")
    print("="*60)
    print("\nThis tool will configure your NixOS Raspberry Pi.")
    print("Press Ctrl+C at any time to cancel.\n")

    # SSH Key
    ssh_success, ssh_key = prompt_ssh_key()
    if not ssh_success:
        print("\nWarning: No SSH key configured. You won't be able to log in via SSH.")
        confirm = input("Continue without SSH? (yes/no): ").strip().lower()
        if confirm != "yes":
            print("Setup cancelled.")
            return 1

    # Runner Token
    print("\n" + "="*60)
    print("Step 2: GitHub Actions Runner")
    print("="*60)
    print("\nGet token from: GitHub Repo → Settings → Actions → Runners → New self-hosted runner")
    runner_token = prompt_input("Runner registration token", required=True, password=True)
    runner_url = prompt_input("Runner URL", default=DEFAULT_RUNNER_URL, required=True)

    # Hostname
    print("\n" + "="*60)
    print("Step 3: Hostname (Optional)")
    print("="*60)
    hostname = prompt_input("Hostname", default=DEFAULT_HOSTNAME, required=False)
    if not hostname:
        hostname = DEFAULT_HOSTNAME

    # Timezone
    print("\n" + "="*60)
    print("Step 4: Timezone (Optional)")
    print("="*60)
    timezones = get_timezones()
    print(f"\nCommon timezones: UTC, Europe/Zurich, America/New_York")
    timezone = prompt_input("Timezone", default=DEFAULT_TIMEZONE, required=False)
    if not timezone:
        timezone = DEFAULT_TIMEZONE

    # WiFi
    print("\n" + "="*60)
    print("Step 5: WiFi Configuration (Optional)")
    print("="*60)
    configure_wifi_choice = input("\nConfigure WiFi? (yes/no) [no]: ").strip().lower()
    wifi_ssid = ""
    wifi_password = ""
    wifi_enable = False
    if configure_wifi_choice == "yes":
        wifi_ssid = prompt_input("WiFi SSID", required=True)
        wifi_password = prompt_input("WiFi Password", required=True, password=True)
        wifi_enable = True

    # Summary
    print("\n" + "="*60)
    print("Configuration Summary")
    print("="*60)
    print(f"\nSSH Key: {'Configured' if ssh_key else 'Not configured'}")
    print(f"Runner Token: {'*' * min(len(runner_token), 8) if runner_token else 'Not set'}")
    print(f"Runner URL: {runner_url}")
    print(f"Hostname: {hostname}")
    print(f"Timezone: {timezone}")
    print(f"WiFi: {wifi_ssid if wifi_enable else 'Not configured'}")

    print("\n" + "-"*60)
    confirm = input("\nApply this configuration? (yes/no): ").strip().lower()
    if confirm != "yes":
        print("Setup cancelled.")
        return 1

    # Apply configuration
    print("\n" + "="*60)
    print("Applying Configuration")
    print("="*60)

    success = True

    if ssh_key:
        if not configure_ssh(ssh_key):
            success = False

    if runner_token:
        if not configure_runner(runner_token, runner_url, hostname):
            success = False

    if not configure_hostname(hostname):
        success = False

    if not configure_timezone(timezone):
        success = False

    if not configure_wifi(wifi_ssid, wifi_password, wifi_enable):
        success = False

    if not run_nixos_rebuild():
        success = False

    print("\n" + "="*60)
    if success:
        print("✓ Setup completed successfully!")
        print("="*60)
        print("\nYou can now:")
        print("  • SSH into the system as root using your configured key")
        if runner_token:
            print("  • The GitHub Actions runner will be available after enabling it")
        print("\nBackups of original files were created with .backup.<timestamp> suffix.")
    else:
        print("✗ Setup completed with errors")
        print("="*60)
        print("\nSome steps failed. Check the output above for details.")
        return 1

    return 0


def main():
    """Entry point for the setup tool."""
    # Check if running as root (required for nixos-rebuild)
    if os.geteuid() != 0:
        print("Error: This tool must be run as root (sudo)")
        print("Usage: sudo setup-tool")
        return 1

    parser = argparse.ArgumentParser(
        description="NixOS Raspberry Pi Post-Boot Configuration Tool"
    )
    parser.add_argument(
        "--non-interactive",
        action="store_true",
        help="Run in non-interactive mode (use environment variables or defaults)"
    )
    parser.add_argument("--ssh-key", help="SSH public key or GitHub username")
    parser.add_argument("--ssh-method", choices=["github", "direct", "file"],
                        help="How to get SSH key: github=fetch from GitHub, direct=paste key, file=read from file")
    parser.add_argument("--runner-token", help="GitHub Actions runner registration token")
    parser.add_argument("--runner-url", default=DEFAULT_RUNNER_URL, help="GitHub repository URL")
    parser.add_argument("--hostname", default=DEFAULT_HOSTNAME, help="System hostname")
    parser.add_argument("--timezone", default=DEFAULT_TIMEZONE, help="System timezone")
    parser.add_argument("--wifi-ssid", help="WiFi network name")
    parser.add_argument("--wifi-password", help="WiFi password")
    parser.add_argument("--skip-wifi", action="store_true", help="Skip WiFi configuration")

    args = parser.parse_args()

    if args.non_interactive:
        # Non-interactive mode
        print("Running in non-interactive mode...")

        # Get SSH key
        ssh_key = ""
        if args.ssh_key:
            if args.ssh_method == "github":
                success, ssh_key = fetch_github_keys(args.ssh_key)
                if not success:
                    print(f"Error: {ssh_key}")
                    return 1
            elif args.ssh_method == "file":
                success, ssh_key = read_key_from_file(args.ssh_key)
                if not success:
                    print(f"Error: {ssh_key}")
                    return 1
            else:
                is_valid, msg = validate_ssh_key(args.ssh_key)
                if not is_valid:
                    print(f"Error: {msg}")
                    return 1
                ssh_key = args.ssh_key

        # Apply configuration
        success = True

        if ssh_key:
            if not configure_ssh(ssh_key):
                success = False

        if args.runner_token:
            if not configure_runner(args.runner_token, args.runner_url, args.hostname):
                success = False

        if not configure_hostname(args.hostname):
            success = False

        if not configure_timezone(args.timezone):
            success = False

        if not args.skip_wifi and args.wifi_ssid:
            if not configure_wifi(args.wifi_ssid, args.wifi_password or "", True):
                success = False
        else:
            configure_wifi("", "", False)

        if not run_nixos_rebuild():
            success = False

        return 0 if success else 1
    else:
        # Interactive mode
        try:
            return interactive_setup()
        except KeyboardInterrupt:
            print("\n\nSetup cancelled by user.")
            return 1


if __name__ == "__main__":
    sys.exit(main())
