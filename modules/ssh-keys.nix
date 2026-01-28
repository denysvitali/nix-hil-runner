# SSH Configuration - Fetches keys from GitHub at build time
{ config, pkgs, lib, ... }:
let
  # Fetch SSH keys from GitHub at build time
  denysvitaliKeys = pkgs.fetchurl {
    url = "https://github.com/denysvitali.keys";
    hash = "sha256-DA6Xl/dMLPZa+Vx3+zpQTPns9S7W7RRNVEvfR8S/yBk=";
  };
in
{
  config = {
    # SSH daemon configuration
    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "prohibit-password";
        PasswordAuthentication = false;
      };
    };

    # Pi user with dynamically fetched SSH keys
    users.users.pi = {
      isNormalUser = true;
      description = "Pi User";
      extraGroups = [ "wheel" "networkmanager" ];
      openssh.authorizedKeys.keys = lib.splitString "\n" (lib.removeSuffix "\n" (builtins.readFile denysvitaliKeys));
    };

    # Root user with same keys
    users.users.root.openssh.authorizedKeys.keys = lib.splitString "\n" (lib.removeSuffix "\n" (builtins.readFile denysvitaliKeys));
  };
}
