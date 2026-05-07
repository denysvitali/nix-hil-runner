{ config, pkgs, lib, ... }:
{
  imports = [
    ./hardware.nix
    ../../modules/github-runner.nix
    ../../modules/ci-tools.nix
    ../../modules/base-packages.nix
    ../../modules/ssh-keys.nix
    ../../modules/self-update.nix
  ];

  # GitHub Actions runner is configured in modules/github-runner.nix

  # ============== Nix Daemon Configuration ==============
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    max-jobs = lib.mkDefault 4;
    auto-optimise-store = true;
  };

  # ============== Networking ==============
  networking = {
    hostName = "pi4-gps-tracker";
    networkmanager.enable = true;
    firewall.allowedTCPPorts = [ 22 ];  # SSH
  };

  # Add pi user to plugdev/dialout for probe-rs access
  users.users.pi.extraGroups = [ "plugdev" "dialout" ];

  # ============== System Settings ==============
  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  # Enable automatic garbage collection
  nix.gc.automatic = true;

  # System state version
  system.stateVersion = "24.11";

  # Generate a machine-id for DHCP/DNS
  systemd.services.systemd-machine-id-commit.wantedBy = [ "multi-user.target" ];
}
