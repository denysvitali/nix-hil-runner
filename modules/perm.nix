{
  pkgs,
  ...
}:
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
    before = [
      "sshd.service"
      "hil-runner.service"
    ];
    after = [
      "hil-firstboot.service"
      "local-fs.target"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu
      users="root hil"

      if [ ! -f /perm/configured ]; then
        echo "device not yet configured; skipping perm sync"
        exit 0
      fi

      key_count=0
      if [ -f /perm/authorized_keys ]; then
        key_count=$(grep -cvE '^[[:space:]]*(#|$)' /perm/authorized_keys || true)
        for u in $users; do
          install -m 0600 -o root -g root \
            /perm/authorized_keys "/etc/ssh/authorized_keys.d/$u"
        done
      fi

      hostname=""
      if [ -s /perm/hostname ]; then
        hostname=$(cat /perm/hostname)
        # NixOS forbids writing the static /etc/hostname (it's a symlink into
        # the Nix store), so plain `hostnamectl set-hostname` errors out. The
        # transient hostname is the one the kernel actually uses, and that's
        # the one we want to drive from /perm anyway.
        ${pkgs.systemd}/bin/hostnamectl --transient set-hostname "$hostname"
      fi

      # Console root password. hil-firstboot locks root unconditionally in the
      # hardened branch; if /perm/root.hash exists we re-enable it here so SSH
      # password auth stays off (no sshd drop-in) but a serial/HDMI login works.
      root_pw="locked"
      if [ -s /perm/root.hash ]; then
        printf 'root:%s\n' "$(cat /perm/root.hash)" \
          | ${pkgs.shadow}/bin/chpasswd -e
        root_pw="set"
      fi

      echo "synced $key_count keys for users $(echo $users | tr ' ' ','); hostname=''${hostname:-<unset>}; root_pw=$root_pw"
    '';
  };

  systemd.paths.hil-perm-watch = {
    description = "Watch /perm/{authorized_keys,hostname} and re-trigger hil-perm-sync";
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      PathChanged = [
        "/perm/authorized_keys"
        "/perm/hostname"
        "/perm/root.hash"
      ];
      Unit = "hil-perm-sync.service";
    };
  };
}
