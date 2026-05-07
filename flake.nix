{
  description = "NixOS HIL runner — A/B image with first-boot setup wizard";

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
      # Version is injected at build time by writing ./VERSION (CI does this
      # from the computed tag). Local builds without a VERSION file get "dev".
      version =
        if builtins.pathExists ./VERSION
        then nixpkgs.lib.fileContents ./VERSION
        else "dev";
      versionModule = { system.image.version = version; };
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f {
        inherit system;
        pkgs = nixpkgs.legacyPackages.${system};
      });
    in
    {
      nixosConfigurations = {
        pi4 = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [ versionModule ./hosts/pi4/configuration.nix ];
        };

        pi4-cross = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            versionModule
            {
              nixpkgs.buildPlatform = "x86_64-linux";
              nixpkgs.hostPlatform = "aarch64-linux";
            }
            ./hosts/pi4/configuration.nix
          ];
        };
      };

      packages = forAllSystems ({ system, pkgs }:
        let
          cfg = if system == "aarch64-linux"
            then self.nixosConfigurations.pi4
            else self.nixosConfigurations.pi4-cross;
        in
        {
          image = cfg.config.system.build.image;
          update-package = cfg.config.system.build.sysupdate-package;
          default = cfg.config.system.build.image;
        });
    };
}
