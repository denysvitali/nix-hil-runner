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
}
