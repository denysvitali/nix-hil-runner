# CI/Embedded Development Tools
{ config, pkgs, lib, ... }:
{
  config.environment.systemPackages = with pkgs; [
    # Embedded development tools
    probe-rs-tools
    espflash

    # Rust toolchain
    cargo
    rustc
    rustfmt
    clippy
  ];

  # ============== USB/Probe Device Permissions ==============
  # Create plugdev group for USB device access
  # NixOS auto-assigns GIDs; leaving empty lets it assign from system range (< 1000)
  config.users.groups.plugdev = { };

  # Add empty file with "probe-rs" in name to satisfy probe-rs detection
  # probe-rs checks for any file with "probe-rs" in the name at /etc/udev/rules.d/
  # Create a derivation with the empty file and add it to udev packages
  config.services.udev.packages = lib.mkBefore [
    (pkgs.writeTextDir "etc/udev/rules.d/99-probe-rs.rules" "")
  ];

  # Create github-runner user for the GitHub Actions runner service
  config.users.groups.github-runner = { };
  config.users.users.github-runner = {
    isSystemUser = true;
    group = "github-runner";
    extraGroups = [ "plugdev" ];
  };

  # Udev rules for probe-rs compatible debug probes
  config.services.udev.extraRules = ''
    # CMSIS-DAP compatible adapters
    SUBSYSTEM=="usb", ATTR{idVendor}=="0d28", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="usb", ATTR{idVendor}=="0d28", ENV{ID_MM_DEVICE_IGNORE}="1"

    # WCH LinkE
    SUBSYSTEM=="usb", ATTR{idVendor}=="1a86", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="usb", ATTR{idVendor}=="1a86", ENV{ID_MM_DEVICE_IGNORE}="1"

    # ESP JTAG (ESP32-C3 built-in JTAG)
    SUBSYSTEM=="usb", ATTR{idVendor}=="303a", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="usb", ATTR{idVendor}=="303a", ENV{ID_MM_DEVICE_IGNORE}="1"

    # FTDI (FT2232, FT4232, FT232H)
    SUBSYSTEM=="usb", ATTR{idVendor}=="0403", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="usb", ATTR{idVendor}=="0403", ENV{ID_MM_DEVICE_IGNORE}="1"

    # Segger J-Link
    SUBSYSTEM=="usb", ATTR{idVendor}=="1366", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="usb", ATTR{idVendor}=="1366", ENV{ID_MM_DEVICE_IGNORE}="1"

    # ST-Link V1
    SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="3744", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="3744", ENV{ID_MM_DEVICE_IGNORE}="1"

    # ST-Link V2
    SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="3748", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="3748", ENV{ID_MM_DEVICE_IGNORE}="1"

    # ST-Link V2-1
    SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="374b", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="374b", ENV{ID_MM_DEVICE_IGNORE}="1"

    # ST-Link V3
    SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="374e", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="374e", ENV{ID_MM_DEVICE_IGNORE}="1"
    SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="374f", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="374f", ENV{ID_MM_DEVICE_IGNORE}="1"
    SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="3753", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="3753", ENV{ID_MM_DEVICE_IGNORE}="1"

    # TI XDS110
    SUBSYSTEM=="usb", ATTR{idVendor}=="0451", ATTR{idProduct}=="bef3", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="usb", ATTR{idVendor}=="0451", ATTR{idProduct}=="bef3", ENV{ID_MM_DEVICE_IGNORE}="1"

    # SiLabs CP210x
    SUBSYSTEM=="usb", ATTR{idVendor}=="10c4", ATTR{idProduct}=="ea60", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="usb", ATTR{idVendor}=="10c4", ATTR{idProduct}=="ea60", ENV{ID_MM_DEVICE_IGNORE}="1"

    # WCH CH340
    SUBSYSTEM=="usb", ATTR{idVendor}=="1a86", ATTR{idProduct}=="7523", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="usb", ATTR{idVendor}=="1a86", ATTR{idProduct}=="7523", ENV{ID_MM_DEVICE_IGNORE}="1"

    # WCH CH341
    SUBSYSTEM=="usb", ATTR{idVendor}=="1a86", ATTR{idProduct}=="5512", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="usb", ATTR{idVendor}=="1a86", ATTR{idProduct}=="5512", ENV{ID_MM_DEVICE_IGNORE}="1"
  '';
}
