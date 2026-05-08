# Base system packages
{ config, pkgs, ... }:
{
  config.environment.systemPackages = with pkgs; [
    git
    nano
    htop
    curl
    wget
    vim
    unzip
  ];
}
