{ config, lib, pkgs, ... }:
{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;

  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = lib.mkForce false;

  boot.uki.name = lib.mkDefault config.system.image.id;

  # UKI is the boot artifact; no separate kernel/initrd files in /boot.
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages;

  # pftf RPi4 UEFI loads the UKI via the EDK2 Arasan SDHCI driver, which is
  # very slow. Every MB shaved off the initrd is real time at boot. Drop the
  # generic "boot anywhere" module set and include only what BCM2711 needs.
  boot.initrd = {
    includeDefaultModules = false;
    availableKernelModules = [
      "mmc_block" "sdhci_iproc"                 # SD card boot
      "pcie_brcmstb" "reset-raspberrypi"        # PCIe + vl805 reset (USB boot)
      "xhci_pci" "usb_storage" "usbhid" "hid_generic"
      "ext4" "squashfs" "vfat"
    ];
    compressor = "zstd";
    compressorArgs = [ "-19" "-T0" ];
  };

  boot.kernelParams = [
    "earlycon=pl011,0xfe201000"
    "console=tty0"
    "console=ttyAMA0,115200"
  ];

  # The repart image profile already ensures /boot is on the ESP.
}
