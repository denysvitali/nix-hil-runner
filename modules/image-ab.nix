{ config, lib, pkgs, modulesPath, ... }:
let
  storeSize = "2G";
in
{
  imports = [
    "${modulesPath}/image/repart.nix"
  ];

  system.image = {
    id = lib.mkDefault "hil-runner";
    # Set by the flake from ./VERSION (CI overwrites that file before build).
    version = lib.mkDefault "dev";
  };

  image.repart = {
    name = config.system.image.id;
    split = true;

    partitions = {
      "10-esp" = {
        contents = {
          "/EFI/BOOT/BOOTAA64.EFI".source =
            "${pkgs.systemd}/lib/systemd/boot/efi/systemd-bootaa64.efi";
          "/EFI/Linux/${config.system.boot.loader.ukiFile}".source =
            "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";
          "/loader/loader.conf".source = builtins.toFile "loader.conf" ''
            timeout 5
            default ${config.boot.uki.name}_*.efi
          '';
        };
        repartConfig = {
          Type = "esp";
          Label = "ESP";
          Format = "vfat";
          SizeMinBytes = "256M";
          SizeMaxBytes = "256M";
          SplitName = "-";
        };
      };

      "20-nix-store" = {
        storePaths = [ config.system.build.toplevel ];
        nixStorePrefix = "/";
        repartConfig = {
          Type = "linux-generic";
          Label = "store_${config.system.image.version}";
          Format = "squashfs";
          ReadOnly = "yes";
          Minimize = "off";
          SizeMinBytes = storeSize;
          SizeMaxBytes = storeSize;
          SplitName = "store";
        };
      };

      "30-nix-store-empty" = {
        repartConfig = {
          Type = "linux-generic";
          Label = "_empty";
          Minimize = "off";
          SizeMinBytes = storeSize;
          SizeMaxBytes = storeSize;
          SplitName = "-";
        };
      };

      "40-perm" = {
        repartConfig = {
          Type = "linux-generic";
          Label = "perm";
          Format = "ext4";
          Minimize = "off";
          SizeMinBytes = "256M";
          SizeMaxBytes = "1G";
          SplitName = "-";
        };
      };

      "50-root" = {
        repartConfig = {
          Type = "root";
          Format = "ext4";
          Label = "root";
          Minimize = "off";
          SizeMinBytes = "2G";
          SizeMaxBytes = "2G";
          SplitName = "-";
        };
      };
    };
  };

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-partlabel/root";
      fsType = "ext4";
    };
    "/nix/store" = {
      device = "/dev/disk/by-partlabel/store_${config.system.image.version}";
      fsType = "squashfs";
      options = [ "ro" ];
      neededForBoot = true;
    };
    "/boot" = {
      device = "/dev/disk/by-partlabel/ESP";
      fsType = "vfat";
      options = [ "umask=0077" ];
    };
    "/perm" = {
      device = "/dev/disk/by-partlabel/perm";
      fsType = "ext4";
      neededForBoot = false;
    };
  };
}
