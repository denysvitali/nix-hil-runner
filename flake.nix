{
  description = "NixOS Raspberry Pi 4 Smoke Test Image";

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

      # Setup tool package
      setupTool = { pkgs }: pkgs.callPackage ./pkgs/setup-tool/default.nix { };
    in
    {
      # Native build on aarch64-linux
      nixosConfigurations.pi4-aarch64 = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
          ./hosts/pi4/configuration.nix
          ./hosts/pi4/hardware.nix
        ];
      };

      # Cross-compile from x86_64-linux to aarch64-linux
      nixosConfigurations.pi4-cross = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          {
            nixpkgs.crossSystem = {
              system = "aarch64-linux";
            };
          }
          "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
          ./hosts/pi4/configuration.nix
          ./hosts/pi4/hardware.nix
        ];
      };

      packages = forAllSystems ({ system, pkgs }: {
        # Use native build on aarch64, cross-compile on x86_64
        pi4-sd-image =
          if system == "aarch64-linux"
          then self.nixosConfigurations.pi4-aarch64.config.system.build.sdImage
          else self.nixosConfigurations.pi4-cross.config.system.build.sdImage;

        # Post-boot configuration TUI tool
        setup-tool = setupTool { inherit pkgs; };
      });

      defaultPackage = forAllSystems ({ system, pkgs }: self.packages.${system}.pi4-sd-image);
    };
}
