{ config, lib, pkgs, ... }:
let
  # Rolling 'updates' release maintained by .github/workflows/release.yml:
  # each successful master build replaces the assets there, so this URL
  # always serves the current SHA256SUMS plus the matching *.store.raw / *.efi.
  defaultSource = {
    Type = "url-file";
    Path = "https://github.com/denysvitali/nix-hil-runner/releases/download/updates/";
  };
in
{
  systemd.sysupdate = {
    enable = true;

    transfers = {
      "10-nix-store" = {
        # GitHub release assets are capped at 2 GB; the raw store image is
        # larger than that, so we publish it xz-compressed. systemd-sysupdate
        # transparently decompresses sources whose MatchPattern ends in
        # .gz/.bz2/.xz/.zst.
        Source = defaultSource // {
          MatchPattern = [ "${config.system.image.id}_@v.store.raw.xz" ];
        };
        Target = {
          InstancesMax = 2;
          Path = "auto";
          MatchPattern = "store_@v";
          # Required by sysupdate for partition targets: tells it which GPT
          # type to look for during auto-discovery and which type to assign
          # when claiming a free slot. Matches image-ab.nix:46 ("linux-generic").
          MatchPartitionType = "linux-generic";
          PartitionType = "linux-generic";
          Type = "partition";
          ReadOnly = "yes";
        };
        Transfer.Verify = "no";
      };

      "20-uki" = {
        Source = defaultSource // {
          MatchPattern = [ "${config.boot.uki.name}_@v.efi" ];
        };
        Target = {
          InstancesMax = 2;
          MatchPattern = [ "${config.boot.uki.name}_@v.efi" ];
          Mode = "0444";
          Path = "/EFI/Linux";
          PathRelativeTo = "boot";
          Type = "regular-file";
        };
        Transfer.Verify = "no";
      };
    };
  };

  # Build target: the parts of the image needed for an OTA update.
  # The store image is xz-compressed to stay under GitHub's 2 GB release-asset
  # limit; sysupdate transparently decompresses on apply.
  system.build.sysupdate-package =
    pkgs.runCommand "sysupdate-package-${config.system.image.version}" { } ''
      mkdir $out
      cp ${config.system.build.uki}/${config.system.boot.loader.ukiFile} \
         $out/${config.boot.uki.name}_${config.system.image.version}.efi
      ${pkgs.xz}/bin/xz -T0 -9e -c \
         ${config.system.build.image}/${config.system.image.id}_${config.system.image.version}.store.raw \
         > $out/${config.system.image.id}_${config.system.image.version}.store.raw.xz
      cd $out
      ${pkgs.coreutils}/bin/sha256sum * > SHA256SUMS
    '';
}
