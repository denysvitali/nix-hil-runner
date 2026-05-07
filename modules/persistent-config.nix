{ config, lib, pkgs, ... }:
let
  cfg = config.hil;
in
{
  systemd.tmpfiles.rules = [
    "d ${cfg.persistentConfigPath} 0755 root root - -"
    "d /etc/ssh/authorized_keys.d 0755 root root - -"
  ];

  systemd.services.hil-config-sync = {
    description = "Sync persistent HIL config (SSH keys, runner token) into runtime locations";
    wantedBy = [ "multi-user.target" ];
    before = [
      "sshd.service"
      "github-runner-${cfg.runner.name}.service"
    ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu
      src=${lib.escapeShellArg cfg.persistentConfigPath}

      install -d -m 0755 /etc/ssh/authorized_keys.d

      if [ -f "$src/authorized_keys" ]; then
        for u in root ${lib.escapeShellArg cfg.user}; do
          install -m 0600 -o root -g root \
            "$src/authorized_keys" \
            "/etc/ssh/authorized_keys.d/$u"
        done
      else
        echo "warning: $src/authorized_keys not found; SSH access will be unavailable" >&2
      fi

      if [ -f "$src/runner.token" ]; then
        install -d -o github-runner -g github-runner -m 0700 /var/lib/github-runner
        install -m 0600 -o github-runner -g github-runner \
          "$src/runner.token" /var/lib/github-runner/.token
      fi
    '';
  };
}
