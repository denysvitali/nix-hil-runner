{
  description = "NixOS HIL runner — generic image with first-boot setup wizard";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://cache.nixos.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f {
        inherit system;
        pkgs = nixpkgs.legacyPackages.${system};
      });
    in
    {
      nixosConfigurations = {
        # Legacy SD-image (sd-image-aarch64), generation-based rollback only.
        pi4-aarch64 = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
            "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
            ./hosts/pi4/configuration.nix
            ./hosts/pi4/hardware.nix
          ];
        };

        pi4-cross = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            { nixpkgs.crossSystem = { system = "aarch64-linux"; }; }
            "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
            ./hosts/pi4/configuration.nix
            ./hosts/pi4/hardware.nix
          ];
        };

        # A/B image with systemd-repart + systemd-sysupdate + pftf UEFI.
        # Boots on Pi 4 via pftf UEFI -> systemd-boot -> UKI.
        pi4-ab = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [ ./hosts/pi4-ab/configuration.nix ];
        };

        pi4-ab-cross = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            { nixpkgs.buildPlatform = "x86_64-linux"; nixpkgs.hostPlatform = "aarch64-linux"; }
            ./hosts/pi4-ab/configuration.nix
          ];
        };
      };

      packages = forAllSystems ({ system, pkgs }:
        let
          ab = if system == "aarch64-linux"
            then self.nixosConfigurations.pi4-ab
            else self.nixosConfigurations.pi4-ab-cross;
          legacy = if system == "aarch64-linux"
            then self.nixosConfigurations.pi4-aarch64
            else self.nixosConfigurations.pi4-cross;
        in
        {
          # Legacy SD image — bootable on Pi 4 with stock Pi firmware + extlinux.
          pi4-sd-image = legacy.config.system.build.sdImage;

          # A/B image — full bootable raw image (write to SD, boot via pftf UEFI).
          pi4-ab-image = ab.config.system.build.image;

          # Sysupdate package — nix-store.raw + UKI + SHA256SUMS for OTA updates.
          pi4-ab-update-package = ab.config.system.build.sysupdate-package;

          default = legacy.config.system.build.sdImage;
        });
    };
}
