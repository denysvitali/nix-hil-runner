{ config, pkgs, lib, ... }:
{
  imports = [
    ./hardware.nix
    ../../modules/perm.nix
    ../../modules/firstboot.nix
    ../../modules/hil-setup.nix
    ../../modules/users.nix
    ../../modules/runner.nix
    ../../modules/ci-tools.nix
    ../../modules/base-packages.nix
    ../../modules/self-update.nix
  ];

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    max-jobs = lib.mkDefault 4;
    auto-optimise-store = true;
  };

  # Generic identity. The actual hostname is set at runtime by hil-perm-sync
  # from /perm/hostname once the device has been configured.
  networking = {
    hostName = lib.mkDefault "hil-runner";
    networkmanager.enable = true;
    firewall.allowedTCPPorts = [ 22 ];
  };

  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  nix.gc.automatic = true;
  system.stateVersion = "24.11";
  systemd.services.systemd-machine-id-commit.wantedBy = [ "multi-user.target" ];
}
