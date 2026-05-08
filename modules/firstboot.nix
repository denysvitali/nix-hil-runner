{ config, lib, pkgs, ... }:
let
  # NixOS makes /etc/systemd/system a read-only symlink into the Nix store, so
  # runtime drop-ins have to live under /run/systemd/system. systemd reads
  # drop-ins from /run with higher precedence than /etc, and the path is on
  # tmpfs so it's always writable and disappears on reboot (which is exactly
  # what we want for a first-boot toggle).
  sshdDropinDir = "/run/systemd/system/sshd.service.d";
  sshdDropin = "${sshdDropinDir}/firstboot.conf";

  # Self-contained sshd config used only while the device is unconfigured.
  # We don't override the hardened /etc/ssh/sshd_config with -o flags because
  # that's fragile (depends on flag precedence + daemon-reload timing). Point
  # sshd at a fresh config instead. NixOS's sshd ExecStartPre still generates
  # host keys at /etc/ssh/ssh_host_*_key, so we just reference them here.
  firstbootSshdConfig = pkgs.writeText "sshd_config-firstboot" ''
    Port 22
    AddressFamily any

    HostKey /etc/ssh/ssh_host_ed25519_key
    HostKey /etc/ssh/ssh_host_rsa_key

    PermitRootLogin yes
    PasswordAuthentication yes
    KbdInteractiveAuthentication yes
    UsePAM yes
    PrintMotd yes

    AuthorizedKeysFile /etc/ssh/authorized_keys.d/%u

    Subsystem sftp ${pkgs.openssh}/libexec/sftp-server
  '';

  sshdDropinContent = ''
    [Service]
    ExecStart=
    ExecStart=${pkgs.openssh}/bin/sshd -D -f ${firstbootSshdConfig}
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
