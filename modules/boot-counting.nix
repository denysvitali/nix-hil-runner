{ config, lib, pkgs, ... }:
let
  # Gate for systemd-bless-boot.service. Determines whether the current boot
  # was "good enough" to strip the boot-counter suffix from the running UKI.
  #
  # First-boot mode (no /perm/configured): the runner can't start until the
  # wizard has run, so the runner being inactive is expected — treat reaching
  # multi-user.target as success.
  #
  # Hardened mode: a healthy boot is one where hil-runner.service reaches
  # 'active' within TimeoutStartSec=5min. If it doesn't, this service is
  # killed, bless is gated on it via Requires=, so bless skips, and the next
  # boot decrements TriesLeft on the running UKI. After 3 failed attempts
  # systemd-boot falls through to the previous UKI.
  successScript = pkgs.writeShellScript "hil-boot-success" ''
    set -eu
    if [ ! -e /perm/configured ]; then
      exit 0
    fi
    while ! ${pkgs.systemd}/bin/systemctl is-active --quiet hil-runner.service; do
      sleep 5
    done
  '';
in
{
  systemd.services.hil-boot-success = {
    description = "Mark current boot as successful (gates systemd-bless-boot)";
    wantedBy = [ "boot-complete.target" ];
    before = [ "systemd-bless-boot.service" ];
    after = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "5min";
      ExecStart = "${successScript}";
    };
  };

  # Before= alone wouldn't stop bless from running when the healthcheck fails;
  # Requires= makes bless inherit hil-boot-success's failure and skip blessing.
  systemd.services.systemd-bless-boot = {
    unitConfig.Requires = [ "hil-boot-success.service" ];
    after = [ "hil-boot-success.service" ];
  };

  # boot-complete.target is shipped by systemd but not pulled in by default;
  # without this nothing would activate it during boot and bless would never run.
  systemd.targets.boot-complete.wantedBy = [ "multi-user.target" ];
}
