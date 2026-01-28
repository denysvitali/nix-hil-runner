{ config, pkgs, lib, ... }:

let
  # Setup tool package for first-boot configuration
  setup-tool = pkgs.callPackage ../../pkgs/setup-tool/default.nix { };

  # Flag file to track if setup is complete
  setupCompleteFlag = "/var/lib/.nixos-setup-complete";
in
{
  # ============== File Systems ==============
  # fileSystems."/" = {
  #   device = "/dev/disk/by-label/NIXOS_SD";
  #   fsType = "ext4";
  # };

  # ============== SSH Configuration ==============
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      # Password auth enabled for first boot only (until setup completes)
      # The setup tool will disable password auth after configuring SSH keys
      PasswordAuthentication = true;
    };
  };

  # SSH authorized keys for the pi user (fetches from GitHub)
  users.users.pi = {
    isNormalUser = true;
    description = "Pi User";
    extraGroups = [ "wheel" "networkmanager" ];
    # Initial password for first-boot access (user will set SSH keys via setup tool)
    # Password is "nixos" - should be changed after initial setup
    initialPassword = "nixos";
    openssh.authorizedKeys.keys = [
      # Fetched from https://github.com/denysvitali.keys
      # Add additional keys here as needed
    ];
  };

  # ============== Package Installation ==============
  environment.systemPackages = with pkgs; [
    # CI/Debugging tools
    probe-rs-tools
    espflash

    # Rust toolchain (cargo, rustc, etc.)
    cargo
    rustc
    rustfmt
    clippy

    # Build tools
    git
    nano
    htop
    curl
    wget

    # First-boot setup tool
    setup-tool
  ];

  # ============== First-Boot Setup Service =============-
  # Systemd service that runs the setup tool on first boot
  systemd.services.nixos-first-boot-setup = let
    # Wrapper script that runs setup tool and creates flag on success
    setupWrapper = pkgs.writeShellScript "nixos-setup-wrapper" ''
      set -e
      
      # Check if we have a usable TTY
      if [ -t 0 ] && [ -t 1 ]; then
        echo "Starting NixOS first-boot setup..."
        echo "Press any key to continue or wait 5 seconds..."
        ${pkgs.coreutils}/bin/sleep 5 || true
      fi

      # Run the setup tool only if we have a TTY, otherwise skip
      if [ -t 0 ] && [ -t 1 ]; then
        if ${setup-tool}/bin/setup-tool; then
          echo "Setup completed successfully."
          # Create flag file to prevent future runs
          touch ${setupCompleteFlag}
          echo "Created ${setupCompleteFlag}"
        else
          echo "Setup tool exited with error. You can re-run with: sudo systemctl restart nixos-first-boot-setup"
          exit 1
        fi
      else
        echo "No TTY available, skipping interactive setup."
        echo "To run setup manually: sudo setup-tool"
        # Don't create flag - let it run on actual first boot with TTY
        exit 0
      fi
    '';
  in {
    description = "NixOS First Boot Setup Tool";
    wantedBy = [ "multi-user.target" ];
    # Run after network is available
    after = [ "network-online.target" "systemd-user-sessions.service" "getty@tty1.service" ];
    requires = [ "network-online.target" ];

    # Only run if setup hasn't completed yet
    unitConfig = {
      ConditionPathExists = "!${setupCompleteFlag}";
    };

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Don't allocate TTY by default - the script checks for TTY availability
      StandardInput = "null";
      StandardOutput = "journal";
      StandardError = "journal";
      # Run as root (required for nixos-rebuild and writing to /etc)
      User = "root";
      Group = "root";
      # Use wrapper script that creates flag on success
      ExecStart = setupWrapper;
      # Ignore SIGHUP to prevent failures during rebuild
      IgnoreSIGPIPE = false;
    };

    # Ensure github-runner directories exist before running (only if user exists)
    preStart = ''
      mkdir -p /var/lib/github-runner
      # Only chown if github-runner user exists
      if id -u github-runner >/dev/null 2>&1; then
        chown github-runner:github-runner /var/lib/github-runner 2>/dev/null || true
      fi
      chmod 755 /var/lib/github-runner
    '';
  };

  # ============== Nix Daemon for Parallel Builds ==============
  nix.settings.max-jobs = lib.mkDefault 4;
  nix.settings.auto-optimise-store = true;

  # ============== GitHub Actions Self-Hosted Runner ==============
  # The runner is disabled by default in the SD image.
  # To enable after first boot:
  # 1. Set the URL to your GitHub repo/org (e.g., "https://github.com/owner/repo")
  # 2. Set tokenFile to a file containing your runner token
  # 3. Set enable = true
  services.github-runners.pi4-smoke-test = {
    enable = false;
    name = "pi4-smoke-test";
    extraLabels = [
      "self-hosted"
      "pi4-smoke-test"
      "aarch64"
      "nixos"
    ];

    # TODO: Configure these after first boot
    # url = "https://github.com/your-org/your-repo";
    # tokenFile = "/var/lib/github-runner/.runner_token";
  };

  # ============== Networking ==============
  networking = {
    hostName = "pi4-smoke-test";
    networkmanager.enable = true;
    firewall.allowedTCPPorts = [ 22 ];  # SSH
  };

  # ============== System ==============
  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  # Enable automatic garbage collection
  nix.gc.automatic = true;

  # System state version
  system.stateVersion = "24.11";

  # Generate a machine-id for DHCP/DNS
  systemd.services.systemd-machine-id-commit.wantedBy = [ "multi-user.target" ];
}
