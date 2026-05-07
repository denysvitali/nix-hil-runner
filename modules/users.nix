{ config, lib, ... }:
let
  cfg = config.hil;
in
{
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
    authorizedKeysFiles = lib.mkForce [ "/etc/ssh/authorized_keys.d/%u" ];
  };

  users.users.${cfg.user} = {
    isNormalUser = true;
    description = "HIL runner user";
    extraGroups = [ "wheel" "networkmanager" "plugdev" "dialout" ];
  };

  security.sudo.wheelNeedsPassword = false;
}
