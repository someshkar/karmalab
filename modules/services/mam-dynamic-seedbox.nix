{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.mam-dynamic-seedbox;
in
{
  options.services.mam-dynamic-seedbox = {
    enable = mkEnableOption "MAM dynamic seedbox IP updater";

    secretsFile = mkOption {
      type = types.str;
      default = "/etc/nixos/secrets/mam-id";
      description = "Path to file containing mam_id cookie";
    };

    interval = mkOption {
      type = types.str;
      default = "1h";
      description = "How often to update IP (systemd time format)";
    };
  };

  config = mkIf cfg.enable {
    # Systemd service to update MAM IP
    systemd.services.mam-dynamic-seedbox = {
      description = "Update MAM dynamic seedbox IP";
      
      # Dependencies: wait for VPN to be up
      after = [ "wireguard-vpn.service" "vpn-dns.service" ];
      requires = [ "wireguard-vpn.service" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        
        # CRITICAL: Run in VPN namespace (same as Deluge)
        NetworkNamespacePath = "/var/run/netns/vpn";
        
        # Script to call MAM API
        ExecStart = pkgs.writeShellScript "mam-update" ''
          #!${pkgs.bash}/bin/bash
          set -euo pipefail

          # Read mam_id from secrets file
          if [ ! -f "${cfg.secretsFile}" ]; then
            echo "ERROR: Secrets file not found: ${cfg.secretsFile}"
            exit 1
          fi

          MAM_ID=$(cat "${cfg.secretsFile}")

          if [ -z "$MAM_ID" ]; then
            echo "ERROR: mam_id is empty in ${cfg.secretsFile}"
            exit 1
          fi

          # Call MAM dynamic seedbox API
          echo "Updating MAM dynamic seedbox IP..."
          RESPONSE=$(${pkgs.curl}/bin/curl -s -b "$MAM_ID" \
            https://t.myanonamouse.net/json/dynamicSeedbox.php)

          echo "Response: $RESPONSE"

          # Check for success or no change
          if echo "$RESPONSE" | ${pkgs.gnugrep}/bin/grep -qE "Success|No Change"; then
            echo "MAM IP update successful"
            exit 0
          else
            echo "ERROR: Unexpected response from MAM API"
            exit 1
          fi
        '';
        
        # Logging
        StandardOutput = "journal";
        StandardError = "journal";
        
        # Security hardening
        PrivateTmp = true;
        NoNewPrivileges = true;
        ProtectSystem = false;  # Need access to /etc/nixos/secrets
        ProtectHome = true;
      };
    };

    # Timer to run service hourly
    systemd.timers.mam-dynamic-seedbox = {
      description = "Timer for MAM dynamic seedbox IP updates";
      wantedBy = [ "timers.target" ];
      
      timerConfig = {
        OnBootSec = "5min";              # First run 5 min after boot
        OnUnitActiveSec = cfg.interval;  # Then every interval (default 1h)
        Persistent = true;               # Catch up if system was off
        RandomizedDelaySec = "30s";      # Random delay to avoid thundering herd
      };
    };
  };
}
