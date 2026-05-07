{ config, lib, pkgs, ... }:
let
  defaultRepoUrl = "https://github.com/denysvitali/nix-hil-runner.git";
  defaultBranch = "master";
  defaultFlakeAttr = "pi4-aarch64";
  repoDir = "/var/lib/nix-hil-runner";

  updateScript = pkgs.writeShellScript "hil-self-update" ''
    set -euo pipefail

    repo_url=${defaultRepoUrl}
    branch=${defaultBranch}
    attr=${defaultFlakeAttr}

    # Optional override file on the perm partition: /perm/self-update.env
    # may set REPO_URL, BRANCH, FLAKE_ATTR.
    if [ -f /perm/self-update.env ]; then
      # shellcheck disable=SC1091
      . /perm/self-update.env
      repo_url="''${REPO_URL:-$repo_url}"
      branch="''${BRANCH:-$branch}"
      attr="''${FLAKE_ATTR:-$attr}"
    fi

    if [ ! -d ${repoDir}/.git ]; then
      rm -rf ${repoDir}.tmp
      ${pkgs.git}/bin/git clone --depth 1 --branch "$branch" "$repo_url" ${repoDir}.tmp
      rm -rf ${repoDir}
      mv ${repoDir}.tmp ${repoDir}
    fi

    ${pkgs.git}/bin/git -C ${repoDir} fetch --prune origin "$branch"
    ${pkgs.git}/bin/git -C ${repoDir} checkout -B "$branch" "origin/$branch"
    ${pkgs.git}/bin/git -C ${repoDir} submodule update --init --recursive

    ${pkgs.nix}/bin/nix flake update --flake ${repoDir}
    ${pkgs.nixos-rebuild}/bin/nixos-rebuild switch --flake ${repoDir}#"$attr"
  '';
in
{
  systemd.services.hil-self-update = {
    description = "Pull nix-hil-runner upstream and switch to the latest generation";
    # Don't try to self-update before the device is configured.
    unitConfig.ConditionPathExists = "/perm/configured";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = with pkgs; [ git nixos-rebuild nix openssh ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${updateScript}";
    };
  };

  systemd.timers.hil-self-update = {
    description = "Periodically run hil-self-update";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
      RandomizedDelaySec = "15m";
      Unit = "hil-self-update.service";
    };
  };
}
