{ config, lib, ... }:
{
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = lib.mkDefault "prohibit-password";
      PasswordAuthentication = lib.mkDefault false;
    };
    authorizedKeysFiles = lib.mkForce [ "/etc/ssh/authorized_keys.d/%u" ];
  };

  users.mutableUsers = true;

  users.users.hil = {
    isNormalUser = true;
    description = "HIL runner user";
    extraGroups = [ "wheel" "networkmanager" "plugdev" "dialout" ];
  };

  security.sudo.wheelNeedsPassword = false;
}
