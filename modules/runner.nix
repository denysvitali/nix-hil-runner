{ config, lib, pkgs, ... }:
let
  workDir = "/var/lib/github-runner";
  runner = pkgs.github-runner;

  configureScript = pkgs.writeShellScript "hil-runner-configure" ''
    set -eu
    cd ${workDir}
    if [ ! -f .runner ]; then
      if [ ! -f /perm/runner.token ]; then
        echo "missing /perm/runner.token; refusing to configure" >&2
        exit 1
      fi
      token=$(cat /perm/runner.token)
      ${runner}/bin/config.sh \
        --url "$URL" \
        --token "$token" \
        --name "$NAME" \
        --labels "$LABELS" \
        --unattended --replace --disableupdate
    fi
  '';
in
{
  users.groups.github-runner = { };
  users.users.github-runner = {
    isSystemUser = true;
    group = "github-runner";
    home = workDir;
    createHome = false;
    extraGroups = [ "plugdev" "dialout" ];
  };

  systemd.tmpfiles.rules = [
    "d ${workDir} 0700 github-runner github-runner - -"
  ];

  systemd.services.hil-runner = {
    description = "GitHub Actions self-hosted runner (HIL)";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "hil-perm-sync.service"
    ];
    requires = [ "hil-perm-sync.service" ];

    unitConfig.ConditionPathExists = "/perm/configured";

    path = with pkgs; [
      bash
      coreutils
      git
      gnutar
      gzip
      openssh
      icu
    ];

    serviceConfig = {
      Type = "simple";
      User = "github-runner";
      Group = "github-runner";
      WorkingDirectory = workDir;
      SupplementaryGroups = [ "plugdev" "dialout" ];
      EnvironmentFile = "/perm/runner.env";
      Environment = [
        "USER=github-runner"
        "HOME=${workDir}"
      ];
      ExecStartPre = "${configureScript}";
      ExecStart = "${runner}/bin/run.sh";
      Restart = "on-failure";
      RestartSec = 5;
      PrivateDevices = false;
    };
  };
}
