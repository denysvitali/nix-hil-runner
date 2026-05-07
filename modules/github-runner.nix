{ config, lib, ... }:
let
  cfg = config.hil.runner;
in
lib.mkIf cfg.enable {
  services.github-runners.${cfg.name} = {
    enable = true;
    name = cfg.name;
    noDefaultLabels = true;
    extraLabels = cfg.labels;
    url = cfg.url;
    tokenFile = "/var/lib/github-runner/.token";
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/github-runner 0700 github-runner github-runner - -"
  ];

  systemd.services."github-runner-${cfg.name}" = {
    wants = [ "network-online.target" "hil-config-sync.service" ];
    after = [ "network-online.target" "hil-config-sync.service" ];
    serviceConfig = {
      SupplementaryGroups = [ "plugdev" "dialout" ];
      Environment = [ "USER=github-runner" ];
      PrivateDevices = false;
    };
  };
}
