# CI/Embedded Development Tools
{ config, pkgs, ... }:
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
  users.groups.plugdev = { };

  # Add github-runner user to plugdev group for USB device access
  users.users.github-runner.extraGroups = [ "plugdev" ];

  # Udev rules for probe-rs compatible debug probes
  # Based on: https://probe.rs/docs/getting-started/probe-setup/
  services.udev.packages = with pkgs; [
    (pkgs.writeTextFile {
      name = "probe-rs-udev-rules";
      text = ''
        # CMSIS-DAP compatible adapters
        SUBSYSTEM=="usb", ATTR{idVendor}=="0d28", MODE="0666", GROUP="plugdev"
        SUBSYSTEM=="usb", ATTR{idVendor}=="0d28", MODE="0666", GROUP="plugdev", ENV{ID_MM_DEVICE_IGNORE}="1"

        # WCH LinkE
        SUBSYSTEM=="usb", ATTR{idVendor}=="1a86", MODE="0666", GROUP="plugdev"
        SUBSYSTEM=="usb", ATTR{idVendor}=="1a86", MODE="0666", GROUP="plugdev", ENV{ID_MM_DEVICE_IGNORE}="1"

        # ESP JTAG (ESP32-C3 built-in JTAG)
        SUBSYSTEM=="usb", ATTR{idVendor}=="303a", MODE="0666", GROUP="plugdev"
        SUBSYSTEM=="usb", ATTR{idVendor}=="303a", MODE="0666", GROUP="plugdev", ENV{ID_MM_DEVICE_IGNORE}="1"

        # FTDI (FT2232, FT4232, FT232H)
        SUBSYSTEM=="usb", ATTR{idVendor}=="0403", MODE="0666", GROUP="plugdev"
        SUBSYSTEM=="usb", ATTR{idVendor}=="0403", MODE="0666", GROUP="plugdev", ENV{ID_MM_DEVICE_IGNORE}="1"

        # Segger J-Link
        SUBSYSTEM=="usb", ATTR{idVendor}=="1366", MODE="0666", GROUP="plugdev"
        SUBSYSTEM=="usb", ATTR{idVendor}=="1366", MODE="0666", GROUP="plugdev", ENV{ID_MM_DEVICE_IGNORE}="1"

        # ST-Link V1
        SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="3744", MODE="0666", GROUP="plugdev"
        SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="3744", MODE="0666", GROUP="plugdev", ENV{ID_MM_DEVICE_IGNORE}="1"

        # ST-Link V2
        SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="3748", MODE="0666", GROUP="plugdev"
        SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="3748", MODE="0666", GROUP="plugdev", ENV{ID_MM_DEVICE_IGNORE}="1"

        # ST-Link V2-1
        SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="374b", MODE="0666", GROUP="plugdev"
        SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="374b", MODE="0666", GROUP="plugdev", ENV{ID_MM_DEVICE_IGNORE}="1"

        # ST-Link V3
        SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="374e", MODE="0666", GROUP="plugdev"
        SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="374e", MODE="0666", GROUP="plugdev", ENV{ID_MM_DEVICE_IGNORE}="1"
        SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="374f", MODE="0666", GROUP="plugdev"
        SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="374f", MODE="0666", GROUP="plugdev", ENV{ID_MM_DEVICE_IGNORE}="1"
        SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="3753", MODE="0666", GROUP="plugdev"
        SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="3753", MODE="0666", GROUP="plugdev", ENV{ID_MM_DEVICE_IGNORE}="1"

        # TI XDS110
        SUBSYSTEM=="usb", ATTR{idVendor}=="0451", ATTR{idProduct}=="bef3", MODE="0666", GROUP="plugdev"
        SUBSYSTEM=="usb", ATTR{idVendor}=="0451", ATTR{idProduct}=="bef3", MODE="0666", GROUP="plugdev", ENV{ID_MM_DEVICE_IGNORE}="1"

        # SiLabs CP210x
        SUBSYSTEM=="usb", ATTR{idVendor}=="10c4", ATTR{idProduct}=="ea60", MODE="0666", GROUP="plugdev"
        SUBSYSTEM=="usb", ATTR{idVendor}=="10c4", ATTR{idProduct}=="ea60", MODE="0666", GROUP="plugdev", ENV{ID_MM_DEVICE_IGNORE}="1"

        # WCH CH340
        SUBSYSTEM=="usb", ATTR{idVendor}=="1a86", ATTR{idProduct}=="7523", MODE="0666", GROUP="plugdev"
        SUBSYSTEM=="usb", ATTR{idVendor}=="1a86", ATTR{idProduct}=="7523", MODE="0666", GROUP="plugdev", ENV{ID_MM_DEVICE_IGNORE}="1"

        # WCH CH341
        SUBSYSTEM=="usb", ATTR{idVendor}=="1a86", ATTR{idProduct}=="5512", MODE="0666", GROUP="plugdev"
        SUBSYSTEM=="usb", ATTR{idVendor}=="1a86", ATTR{idProduct}=="5512", MODE="0666", GROUP="plugdev", ENV{ID_MM_DEVICE_IGNORE}="1"
      '';
      destination = "/etc/udev/rules.d/60-probe-rs.rules";
    })
  ];
}
