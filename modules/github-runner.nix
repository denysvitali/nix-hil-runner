# GitHub Actions Runner Configuration
{ config, lib, ... }:
{
  config.services.github-runners.pi4 = {
    enable = true;
    name = "pi4-gps-tracker";
    noDefaultLabels = true;
    extraLabels = [
      "pi4"
      "aarch64"
      "nixos"
    ];
    url = "https://github.com/denysvitali/gps-tracker";
    tokenFile = "/var/lib/github-runner/.token";
  };

  # Ensure persistent storage directory exists with proper permissions
  config.systemd.tmpfiles.rules = [
    "d /var/lib/github-runner 0755 github-runner github-runner - -"
  ];

  # Add plugdev group to the runner service for USB device access
  # Set USER env var so probe-rs can detect group membership (it runs `id -Gn $USER`)
  config.systemd.services.github-runner-pi4.serviceConfig = {
    SupplementaryGroups = [ "plugdev" "dialout" ];
    Environment = [ "USER=github-runner" ];
    
    # Allow access to hardware devices (USB probes)
    PrivateDevices = false;
  };

  # The runner should wait until networking is really online at boot.
  # If the runner is already registered, the persisted runner state under
  # /var/lib/github-runner is enough for normal restarts.
  config.systemd.services.github-runner-pi4 = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
  };
}
