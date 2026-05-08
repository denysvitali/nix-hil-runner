{ config, lib, pkgs, ... }:
{
  # /perm is the persistent layer. For now it's a directory on the rootfs
  # (Stage 2 will promote it to a dedicated partition that survives reflash).
  systemd.tmpfiles.rules = [
    "d /perm 0755 root root - -"
    "d /etc/ssh/authorized_keys.d 0755 root root - -"
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

      if [ -f /perm/authorized_keys ]; then
        for u in root hil; do
          install -m 0600 -o root -g root \
            /perm/authorized_keys "/etc/ssh/authorized_keys.d/$u"
        done
      fi

      if [ -s /perm/hostname ]; then
        # NixOS forbids writing the static /etc/hostname (it's a symlink into
        # the Nix store), so plain `hostnamectl set-hostname` errors out. The
        # transient hostname is the one the kernel actually uses, and that's
        # the one we want to drive from /perm anyway.
        ${pkgs.systemd}/bin/hostnamectl --transient set-hostname "$(cat /perm/hostname)"
      fi
    '';
  };
}
