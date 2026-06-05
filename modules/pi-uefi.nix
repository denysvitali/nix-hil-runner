{
  pkgs,
  ...
}:
let
  # pftf provides a UEFI firmware build for the Raspberry Pi 4.
  # The Pi GPU loads start4.elf -> RPI_EFI.fd; UEFI then chains to
  # systemd-boot in /EFI/BOOT/BOOTAA64.EFI on the ESP.
  pftfRPi4 = pkgs.fetchzip {
    url = "https://github.com/pftf/RPi4/releases/download/v1.41/RPi4_UEFI_Firmware_v1.41.zip";
    hash = "sha256-MVvoIO26JNEi1maOYcgk0h/Heb9W+Y8mgh7l8GFC4/k=";
    stripRoot = false;
  };
in
{
  # Drop the pftf tree at the root of the ESP. systemd-repart's CopyFiles
  # recurses into directories, so a single contents entry is enough.
  image.repart.partitions."10-esp".contents."/".source = pftfRPi4;
}
