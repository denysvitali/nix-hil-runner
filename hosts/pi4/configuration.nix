{ config, pkgs, lib, ... }:
{
  imports = [
    ../../modules/image-ab.nix
    ../../modules/uki-boot.nix
    ../../modules/sysupdate.nix
    ../../modules/boot-counting.nix
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

  # Mirror upstream nixpkgs fix 74ebb9c0 ("systemdUkify: fix", 2026-05-06):
  # systemd's meson build probes the build-time python for `import pefile`
  # whenever -Dukify=enabled, but nixos-unstable (rev 549bd84) still gates
  # pefile behind `doCheck`. Prepend a build python with pefile so meson
  # picks it up first in PATH. Drop this once nixos-unstable picks up the fix.
  nixpkgs.overlays = [
    (_: prev: {
      systemd = prev.systemd.overrideAttrs (old: {
        nativeBuildInputs = [
          (prev.buildPackages.python3.withPackages (ps: with ps; [
            lxml markupsafe jinja2 pyelftools pefile
          ]))
        ] ++ (old.nativeBuildInputs or []);
      });
    })
  ];

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
