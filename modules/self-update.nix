{ config, lib, pkgs, ... }:
let
  cfg = config.hil.selfUpdate;
  repoDir = "/var/lib/nix-hil-runner";
in
lib.mkIf cfg.enable {
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

    serviceConfig.Type = "oneshot";

    script = ''
      set -euo pipefail
      repo_url=${lib.escapeShellArg cfg.repoUrl}
      branch=${lib.escapeShellArg cfg.branch}
      attr=${lib.escapeShellArg cfg.flakeAttr}

      if [ ! -d ${repoDir}/.git ]; then
        rm -rf ${repoDir}.tmp
        git clone --depth 1 --branch "$branch" "$repo_url" ${repoDir}.tmp
        rm -rf ${repoDir}
        mv ${repoDir}.tmp ${repoDir}
      fi

      git -C ${repoDir} fetch --prune origin "$branch"
      git -C ${repoDir} checkout -B "$branch" "origin/$branch"
      git -C ${repoDir} submodule update --init --recursive

      nix flake update --flake ${repoDir}
      nixos-rebuild switch --flake ${repoDir}#"$attr"
    '';
  };

  systemd.timers.nix-hil-runner-self-update = {
    description = "Periodically update nix-hil-runner from upstream";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = cfg.onCalendar;
      Persistent = true;
      RandomizedDelaySec = "15m";
      Unit = "nix-hil-runner-self-update.service";
    };
  };
}
