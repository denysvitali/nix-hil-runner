# Automatic self-update configuration
{ pkgs, ... }:
let
  repoUrl = "https://github.com/denysvitali/nix-hil-runner.git";
  repoDir = "/var/lib/nix-hil-runner";
in
{
  systemd.services.nix-hil-runner-self-update = {
    description = "Update nix-hil-runner checkout and switch to latest NixOS generation";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];

    path = [
      pkgs.git
      pkgs.nixos-rebuild
      pkgs.nix
      pkgs.openssh
    ];

    serviceConfig = {
      Type = "oneshot";
    };

    script = ''
      set -euo pipefail

      if [ ! -d ${repoDir}/.git ]; then
        rm -rf ${repoDir}.tmp
        git clone --depth 1 ${repoUrl} ${repoDir}.tmp
        rm -rf ${repoDir}
        mv ${repoDir}.tmp ${repoDir}
      fi

      git -C ${repoDir} fetch --prune origin master
      git -C ${repoDir} checkout -B master origin/master
      git -C ${repoDir} submodule update --init --recursive

      nix flake update ${repoDir}
      nixos-rebuild switch --flake ${repoDir}#pi4-aarch64
    '';
  };

  systemd.timers.nix-hil-runner-self-update = {
    description = "Periodically update nix-hil-runner from upstream";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
      RandomizedDelaySec = "15m";
      Unit = "nix-hil-runner-self-update.service";
    };
  };
}
