{ config, lib, pkgs, ... }:
{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;

  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = lib.mkForce false;

  boot.uki.name = lib.mkDefault config.system.image.id;

  # UKI is the boot artifact; no separate kernel/initrd files in /boot.
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages;

  # The repart image profile already ensures /boot is on the ESP.
}
