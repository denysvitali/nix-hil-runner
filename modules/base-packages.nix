# Base system packages
{ config, pkgs, ... }:
{
  config.environment.systemPackages = with pkgs; [
    # editors
    nano
    vim

    # core
    git
    curl
    wget
    unzip
    less
    file
    tree

    # inspection
    htop
    lsof
    jq

    # hardware
    pciutils
    usbutils

    # network
    tcpdump
    dnsutils
    iperf3
    ethtool

    # sessions
    tmux
  ];
}
