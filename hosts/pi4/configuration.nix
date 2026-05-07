{ config, pkgs, lib, ... }:
{
  imports = [
    ../../modules/image-ab.nix
    ../../modules/uki-boot.nix
    ../../modules/sysupdate.nix
    ../../modules/pi-uefi.nix

    ../../modules/perm.nix
    ../../modules/firstboot.nix
    ../../modules/hil-setup.nix
    ../../modules/users.nix
    ../../modules/runner.nix
    ../../modules/ci-tools.nix
    ../../modules/base-packages.nix
    # self-update is unnecessary in A/B mode — sysupdate replaces it.
  ];

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    max-jobs = lib.mkDefault 4;
  };

  networking = {
    hostName = lib.mkDefault "hil-runner";
    networkmanager.enable = true;
    firewall.allowedTCPPorts = [ 22 ];
  };

  # Squashfs nix store is read-only; auto-optimise is incompatible.
  nix.gc.automatic = false;

  hardware.enableRedistributableFirmware = true;

  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";
  system.stateVersion = "24.11";
}
