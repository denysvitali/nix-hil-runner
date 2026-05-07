{ config, lib, pkgs, ... }:
let
  setupScript = pkgs.writeShellApplication {
    name = "hil-setup";
    runtimeInputs = with pkgs; [ curl coreutils gnused systemd ];
    text = ''
      set -euo pipefail

      if [ "$(id -u)" -ne 0 ]; then
        echo "hil-setup must be run as root (try: sudo hil-setup)" >&2
        exit 1
      fi

      PERM=/perm
      install -d -m 0755 "$PERM"

      echo
      echo "=== HIL Runner Setup ==="
      echo "This wizard configures this device. All input is written"
      echo "to /perm and applied on reboot."
      echo

      read -r -p "Hostname [hil-runner]: " hostname || true
      hostname="''${hostname:-hil-runner}"

      echo
      echo "SSH authorized keys:"
      echo "  - paste public keys, one per line"
      echo "  - or enter 'gh:<username>' to fetch from github.com/<user>.keys"
      echo "  - empty line to finish"
      keys=""
      while true; do
        read -r -p "> " line || break
        [ -z "$line" ] && break
        if [[ "$line" == gh:* ]]; then
          gh_user="''${line#gh:}"
          fetched=$(curl -fsSL "https://github.com/''${gh_user}.keys" || true)
          if [ -z "$fetched" ]; then
            echo "  (no keys fetched for $gh_user; try again)"
            continue
          fi
          keys+="$fetched"$'\n'
        else
          keys+="$line"$'\n'
        fi
      done
      keys=$(printf '%s' "$keys" | sed '/^$/d')
      if [ -z "$keys" ]; then
        echo "no keys provided; aborting" >&2
        exit 1
      fi

      echo
      read -r -p "GitHub runner repo URL (e.g. https://github.com/owner/repo): " runner_url
      if [ -z "$runner_url" ]; then echo "URL required" >&2; exit 1; fi

      read -r -p "Runner name [$hostname]: " runner_name || true
      runner_name="''${runner_name:-$hostname}"

      read -r -p "Runner labels (comma-separated) [aarch64,nixos]: " runner_labels || true
      runner_labels="''${runner_labels:-aarch64,nixos}"

      read -r -p "Runner registration token: " runner_token
      if [ -z "$runner_token" ]; then echo "token required" >&2; exit 1; fi

      echo
      echo "=== Summary ==="
      echo "  hostname: $hostname"
      echo "  runner:   $runner_url"
      echo "  name:     $runner_name"
      echo "  labels:   $runner_labels"
      echo "  keys:     $(printf '%s\n' "$keys" | wc -l) line(s)"
      echo
      read -r -p "Write to /perm and reboot? [y/N]: " confirm || true
      case "$confirm" in
        y|Y|yes|YES) ;;
        *) echo "aborted"; exit 1 ;;
      esac

      umask 077
      printf '%s\n' "$hostname"      > "$PERM/hostname"
      printf '%s\n' "$keys"          > "$PERM/authorized_keys"
      printf '%s'   "$runner_token"  > "$PERM/runner.token"
      cat > "$PERM/runner.env" <<EOF
      URL=$runner_url
      NAME=$runner_name
      LABELS=$runner_labels
      EOF
      chmod 0600 "$PERM/authorized_keys" "$PERM/runner.token" "$PERM/runner.env"
      chmod 0644 "$PERM/hostname"
      touch "$PERM/configured"

      echo
      echo "Configuration saved. Rebooting in 3s..."
      sleep 3
      systemctl reboot
    '';
  };
in
{
  environment.systemPackages = [ setupScript ];
}
