# GitHub Actions Runner Configuration
{ config, lib, ... }:
{
  config.services.github-runners.pi4 = {
    enable = true;
    name = "pi4-gps-tracker";
    extraLabels = [
      "self-hosted"
      "pi4"
      "aarch64"
      "nixos"
    ];
    url = "https://github.com/denysvitali/gps-tracker-tr003-v2";
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
  };

  # Create a skeleton token file if it doesn't exist (with instructions)
  config.systemd.services.github-runner-pi4 = {
    preStart = lib.mkAfter ''
      if [ ! -f /var/lib/github-runner/.token ]; then
        echo "# GitHub Actions Runner Token File" > /var/lib/github-runner/.token
        echo "# Place your runner token in this file, then restart the service:" >> /var/lib/github-runner/.token
        echo "# sudo systemctl restart github-runner-pi4.service" >> /var/lib/github-runner/.token
        echo "#" >> /var/lib/github-runner/.token
        echo "# Get your token from: https://github.com/denysvitali/gps-tracker-tr003-v2/settings/actions/runners/new" >> /var/lib/github-runner/.token
        echo "#" >> /var/lib/github-runner/.token
        echo "# Example (replace with your actual token):" >> /var/lib/github-runner/.token
        echo "# YOUR_RUNNER_TOKEN_HERE" >> /var/lib/github-runner/.token
        chmod 0600 /var/lib/github-runner/.token
      fi
    '';
  };
}
