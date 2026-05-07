{ config, lib, pkgs, ... }:
{
  # /perm is the persistent layer. For now it's a directory on the rootfs
  # (Stage 2 will promote it to a dedicated partition that survives reflash).
  systemd.tmpfiles.rules = [
    "d /perm 0755 root root - -"
  ];

  systemd.services.hil-perm-sync = {
    description = "Sync /perm runtime config into runtime locations";
    wantedBy = [ "multi-user.target" ];
    before = [ "sshd.service" "hil-runner.service" ];
    after = [ "hil-firstboot.service" "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu
      if [ ! -f /perm/configured ]; then
        echo "device not yet configured; skipping perm sync"
        exit 0
      fi

      install -d -m 0755 /etc/ssh/authorized_keys.d
      if [ -f /perm/authorized_keys ]; then
        for u in root hil; do
          install -m 0600 -o root -g root \
            /perm/authorized_keys "/etc/ssh/authorized_keys.d/$u"
        done
      fi

      if [ -s /perm/hostname ]; then
        ${pkgs.systemd}/bin/hostnamectl set-hostname "$(cat /perm/hostname)"
      fi
    '';
  };
}
