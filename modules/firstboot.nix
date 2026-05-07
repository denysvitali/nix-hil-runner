{ config, lib, pkgs, ... }:
let
  sshdDropinDir = "/etc/systemd/system/sshd.service.d";
  sshdDropin = "${sshdDropinDir}/firstboot.conf";

  sshdDropinContent = ''
    [Service]
    ExecStart=
    ExecStart=${pkgs.openssh}/bin/sshd -D -f /etc/ssh/sshd_config -o PermitRootLogin=yes -o PasswordAuthentication=yes
  '';

  motdFirstBoot = ''
    ============================================================
      HIL RUNNER — FIRST BOOT (insecure mode)

      Password authentication is enabled. Default credentials:
        user:     root
        password: root

      Run the following to configure this device:

          hil-setup

      The wizard will prompt for hostname, SSH keys, and GitHub
      runner registration. After configuration the device reboots
      into hardened mode (password auth disabled, key-only).
    ============================================================
  '';

  sshdDropinFile = pkgs.writeText "sshd-firstboot.conf" sshdDropinContent;
  motdFile = pkgs.writeText "motd-firstboot" motdFirstBoot;

  firstbootScript = pkgs.writeShellScript "hil-firstboot" ''
    set -eu
    install -d -m 0755 /perm
    install -d -m 0755 ${sshdDropinDir}

    if [ ! -f /perm/configured ]; then
      echo "FIRST BOOT: enabling password auth + root login"
      echo 'root:root' | ${pkgs.shadow}/bin/chpasswd
      install -m 0644 ${sshdDropinFile} ${sshdDropin}
      install -m 0644 ${motdFile} /etc/motd
      ${pkgs.systemd}/bin/systemctl daemon-reload
    else
      echo "device configured; ensuring hardened mode"
      if [ -f ${sshdDropin} ]; then
        rm -f ${sshdDropin}
        ${pkgs.systemd}/bin/systemctl daemon-reload
      fi
      ${pkgs.shadow}/bin/passwd -l root || true
      : > /etc/motd
    fi
  '';
in
{
  systemd.services.hil-firstboot = {
    description = "First-boot mode toggle (insecure access until /perm/configured)";
    wantedBy = [ "multi-user.target" ];
    before = [ "sshd.service" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${firstbootScript}";
    };
  };
}
