{ config, pkgs, lib, ... }:
{
  imports = [
    ./hardware.nix
    ../../modules/settings.nix
    ../../modules/persistent-config.nix
    ../../modules/users.nix
    ../../modules/github-runner.nix
    ../../modules/ci-tools.nix
    ../../modules/base-packages.nix
    ../../modules/self-update.nix
  ];

  hil = {
    hostname = "pi4-hil-runner";
    user = "hil";

    runner = {
      url = lib.mkDefault "https://github.com/denysvitali/gps-tracker";
      name = lib.mkDefault "pi4-hil-runner";
      labels = [ "pi4" "aarch64" "nixos" ];
    };

    selfUpdate = {
      repoUrl = lib.mkDefault "https://github.com/denysvitali/nix-hil-runner.git";
      flakeAttr = "pi4-aarch64";
    };
  };

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    max-jobs = lib.mkDefault 4;
    auto-optimise-store = true;
  };

  networking = {
    hostName = config.hil.hostname;
    networkmanager.enable = true;
    firewall.allowedTCPPorts = [ 22 ];
  };

  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  nix.gc.automatic = true;
  system.stateVersion = "24.11";
  systemd.services.systemd-machine-id-commit.wantedBy = [ "multi-user.target" ];
}
