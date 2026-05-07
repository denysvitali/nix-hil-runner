{ lib, ... }:
{
  options.hil = {
    hostname = lib.mkOption {
      type = lib.types.str;
      default = "hil-runner";
      description = "System hostname.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "hil";
      description = "Primary unprivileged user account.";
    };

    persistentConfigPath = lib.mkOption {
      type = lib.types.str;
      default = "/boot/firmware/hil-config";
      description = ''
        Path on the persistent (firmware) partition where runtime
        secrets and configuration are read from. Files expected here:

        - authorized_keys : SSH authorized_keys for root and the primary user
        - runner.token    : GitHub Actions runner registration token
      '';
    };

    runner = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      name = lib.mkOption {
        type = lib.types.str;
        default = "hil-runner";
      };
      url = lib.mkOption {
        type = lib.types.str;
        description = "GitHub repository or organization URL the runner registers against.";
      };
      labels = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "nixos" "aarch64" ];
      };
    };

    selfUpdate = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      repoUrl = lib.mkOption {
        type = lib.types.str;
        description = "Git URL of the flake repository to pull updates from.";
      };
      branch = lib.mkOption {
        type = lib.types.str;
        default = "master";
      };
      flakeAttr = lib.mkOption {
        type = lib.types.str;
        description = "nixosConfigurations attribute name to switch to.";
      };
      onCalendar = lib.mkOption {
        type = lib.types.str;
        default = "hourly";
      };
    };
  };
}
