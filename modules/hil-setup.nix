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

      if [ -e "$PERM/configured" ]; then
        echo "WARNING: this device is already configured."
        echo "Continuing will overwrite /perm/*."
        read -r -p "Continue? [y/N]: " cont || true
        case "$cont" in
          y|Y|yes|YES) ;;
          *) echo "aborted"; exit 1 ;;
        esac
        echo
      fi

      # ---- helpers ----------------------------------------------------------

      valid_hostname() {
        [[ "$1" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]]
      }

      valid_runner_url() {
        # https://github.com/<owner>/<repo>  OR  https://github.com/<org>
        [[ "$1" =~ ^https://github\.com/[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)?$ ]]
      }

      valid_ssh_key_line() {
        case "$1" in
          "ssh-ed25519 "*|"ssh-rsa "*|"ecdsa-sha2-"*|"sk-ssh-ed25519 "*|"sk-ecdsa-sha2-"*) return 0 ;;
          *) return 1 ;;
        esac
      }

      add_keys_from_text() {
        # stdin: raw text; appends valid lines to global $keys, returns count via $LAST_ADDED
        local text="$1" line added=0
        while IFS= read -r line; do
          [ -z "$line" ] && continue
          if valid_ssh_key_line "$line"; then
            keys+="$line"$'\n'
            added=$((added + 1))
          else
            echo "  (skipped: does not look like an SSH key: ''${line:0:40}...)"
          fi
        done <<< "$text"
        LAST_ADDED=$added
      }

      prompt_hostname() {
        while true; do
          read -r -p "Hostname [hil-runner]: " hostname || true
          hostname="''${hostname:-hil-runner}"
          if valid_hostname "$hostname"; then
            return
          fi
          echo "  invalid hostname; must match [a-z0-9][a-z0-9-]{0,62}"
        done
      }

      prompt_keys() {
        keys=""
        echo
        echo "SSH authorized keys:"
        echo "  - paste public keys, one per line (ssh-ed25519/ssh-rsa/ecdsa-sha2-/sk-*)"
        echo "  - or enter 'gh:<username>' to fetch from github.com/<user>.keys"
        echo "  - empty line to finish"
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
            add_keys_from_text "$fetched"
            echo "  (added $LAST_ADDED key(s) for $gh_user)"
          else
            add_keys_from_text "$line"
          fi
        done
        keys=$(printf '%s' "$keys" | sed '/^$/d')
        if [ -z "$keys" ]; then
          echo "no valid keys provided; please try again"
          prompt_keys
        fi
      }

      prompt_runner_url() {
        while true; do
          read -r -p "GitHub runner URL (https://github.com/owner/repo or https://github.com/org): " runner_url || true
          if valid_runner_url "$runner_url"; then
            return
          fi
          echo "  invalid URL; expected https://github.com/<owner>/<repo> or https://github.com/<org>"
        done
      }

      prompt_runner_name() {
        read -r -p "Runner name [$hostname]: " runner_name || true
        runner_name="''${runner_name:-$hostname}"
      }

      prompt_runner_labels() {
        read -r -p "Runner labels (comma-separated) [aarch64,nixos]: " runner_labels || true
        runner_labels="''${runner_labels:-aarch64,nixos}"
        # strip whitespace around commas, and any leading/trailing whitespace
        runner_labels=$(printf '%s' "$runner_labels" | sed -E 's/[[:space:]]*,[[:space:]]*/,/g; s/^[[:space:]]+//; s/[[:space:]]+$//')
      }

      prompt_runner_token() {
        while true; do
          read -r -s -p "Runner registration token (input hidden): " runner_token || true
          echo
          if [ -n "$runner_token" ]; then
            return
          fi
          echo "  token required"
        done
      }

      # ---- main flow --------------------------------------------------------

      prompt_hostname
      prompt_keys
      echo
      prompt_runner_url
      prompt_runner_name
      prompt_runner_labels
      prompt_runner_token

      while true; do
        echo
        echo "=== Summary ==="
        echo "  1) hostname: $hostname"
        echo "  2) keys:     $(printf '%s\n' "$keys" | wc -l) line(s)"
        echo "  3) url:      $runner_url"
        echo "  4) name:     $runner_name"
        echo "  5) labels:   $runner_labels"
        echo "  6) token:    (hidden, $(printf '%s' "$runner_token" | wc -c) chars)"
        echo
        read -r -p "Write to /perm and reboot? [y/N/edit number]: " confirm || true
        case "$confirm" in
          y|Y|yes|YES) break ;;
          1) prompt_hostname ;;
          2) prompt_keys ;;
          3) prompt_runner_url ;;
          4) prompt_runner_name ;;
          5) prompt_runner_labels ;;
          6) prompt_runner_token ;;
          n|N|no|NO|"")
            read -r -p "Edit which field? [1-6, or 'q' to abort]: " sel || true
            case "$sel" in
              1) prompt_hostname ;;
              2) prompt_keys ;;
              3) prompt_runner_url ;;
              4) prompt_runner_name ;;
              5) prompt_runner_labels ;;
              6) prompt_runner_token ;;
              q|Q) echo "aborted"; exit 1 ;;
              *) echo "  (unknown selection)" ;;
            esac
            ;;
          *) echo "  (unknown answer; type y, n, or a field number)" ;;
        esac
      done

      umask 077
      printf '%s\n' "$hostname"      > "$PERM/hostname"
      printf '%s\n' "$keys"          > "$PERM/authorized_keys"
      printf '%s'   "$runner_token"  > "$PERM/runner.token"
      cat > "$PERM/runner.env" <<EOF
      URL=$runner_url
      NAME=$runner_name
      LABELS=$runner_labels
      EOF
      chmod 0600 "$PERM/authorized_keys" "$PERM/runner.env"
      # The runner unit runs as `github-runner` and cats this file directly,
      # so the file must be group-readable by that group.
      chown root:github-runner "$PERM/runner.token"
      chmod 0640 "$PERM/runner.token"
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
