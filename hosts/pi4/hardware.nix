{ config, pkgs, lib, ... }:

{
  # Raspberry Pi 4 specific hardware configuration

  # Enable the 64-bit kernel with shared memory and GPU memory
  boot.kernelParams = [
    "cma=256M"
    "gpu_mem=128"
  ];

  # Use the specialized Raspberry Pi 4 kernel
  boot.kernelPackages = pkgs.linuxPackages_rpi4;

  # Required for Raspberry Pi 4
  hardware = {
    enableRedistributableFirmware = true;
  };

  # Bootloader configuration for Raspberry Pi 4
  boot.loader = {
    grub.enable = false;
    generic-extlinux-compatible.enable = true;
  };

  # Enable USB serial kernel modules for ESP32-C3 and similar devices
  boot.kernelModules = [
    # USB CDC ACM - standard class for USB serial devices (native ESP32-C3 USB)
    "cdc-acm"
    # Generic USB serial support
    "usbserial"
    # Common USB-to-UART bridge chips
    "cp210x"  # Silicon Labs CP2102/CP210N (used on many ESP32-C3 dev kits)
    "ch341"   # WCH CH340 (used on many budget boards)
  ];

  # Workaround for dw-hdmi module not being included in linux-rpi kernel
  # See: https://github.com/NixOS/nixos-hardware/issues/1745
  boot.initrd.availableKernelModules = lib.mkForce [
    # Essential modules for boot - SD card and filesystem support
    "mmc_block" "sdhci" "sdhci-pci" "sdhci-iproc" "ext4" "vfat"
    # Exclude dw-hdmi as it's not built with linux-rpi
    # The system will still work without it in initrd
  ];

  # Enable SD image creation
  # (No sdImage.enable option; importing the module is enough)
  # sdImage.compressImage = false; # Set to true if you want .img.xz
}
