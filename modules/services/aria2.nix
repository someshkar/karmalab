# modules/services/aria2.nix
# ============================================================================
# ARIA2 DOWNLOAD MANAGER
# ============================================================================
#
# aria2 is a lightweight multi-protocol download utility supporting
# HTTP/HTTPS, FTP, SFTP, BitTorrent, and Metalink.
#
# Features:
# - Multi-connection downloads for faster speeds
# - Resume interrupted downloads
# - Remote control via JSON-RPC
# - AriaNg web UI for easy management
#
# Access:
# - AriaNg Web UI: http://192.168.0.200:6880
# - RPC Endpoint: http://192.168.0.200:6800/jsonrpc
#
# Setup:
# 1. Create RPC secret in /etc/nixos/secrets/aria2-rpc-secret
# 2. Configure AriaNg with the RPC secret in the web UI
#
# Downloads are stored in the same location as Deluge:
# - /data/media/downloads/complete
#
# ============================================================================

{ config, lib, pkgs, ... }:

let
  # aria2 configuration
  aria2User = "media";
  aria2Group = "media";
  
  # Ports
  rpcPort = 6800;
  
  # Paths
  downloadDir = "/data/media/downloads/complete";
  configDir = "/var/lib/aria2";
  sessionFile = "${configDir}/aria2.session";
  rpcSecretFile = "/etc/nixos/secrets/aria2-rpc-secret";
  
  # aria2 configuration file content
  aria2Config = pkgs.writeText "aria2.conf" ''
    # Basic settings
    dir=${downloadDir}
    continue=true
    max-concurrent-downloads=5
    max-connection-per-server=16
    min-split-size=1M
    split=16
    
    # RPC settings
    enable-rpc=true
    rpc-listen-all=true
    rpc-listen-port=${toString rpcPort}
    rpc-allow-origin-all=true
    
    # Session management (resume downloads after restart)
    input-file=${sessionFile}
    save-session=${sessionFile}
    save-session-interval=60
    
    # File settings
    auto-file-renaming=true
    allow-overwrite=true
    
    # Performance tuning
    disk-cache=64M
    file-allocation=falloc
    
    # Download limits (0 = unlimited)
    max-overall-download-limit=0
    max-overall-upload-limit=50K
    
    # Logging
    log-level=warn
    
    # BitTorrent settings (if using for torrents)
    bt-enable-lpd=true
    bt-max-peers=50
    bt-request-peer-speed-limit=100K
    enable-dht=true
    enable-peer-exchange=true
  '';
in
{
  # ============================================================================
  # ARIA2 SERVICE
  # ============================================================================

  systemd.services.aria2 = {
    description = "aria2 Download Manager";
    after = [ "network.target" "storage-online.target" ];
    wants = [ "storage-online.target" ];
    wantedBy = [ "multi-user.target" ];
    
    preStart = ''
      # Ensure download directory exists (owned by root:media with setgid)
      # No chown needed - aria2 runs as 'media' user and can write via group permissions
      mkdir -p ${downloadDir} || true
      
      # Create session file if it doesn't exist
      if [ ! -f "${sessionFile}" ]; then
        touch ${sessionFile}
        chown ${aria2User}:${aria2Group} ${sessionFile}
      fi
      
      # Generate RPC secret if it doesn't exist
      if [ ! -f ${rpcSecretFile} ]; then
        echo "Generating aria2 RPC secret..."
        mkdir -p $(dirname ${rpcSecretFile})
        ${pkgs.openssl}/bin/openssl rand -base64 32 > ${rpcSecretFile}
        chmod 600 ${rpcSecretFile}
        echo "RPC secret saved to ${rpcSecretFile}"
        echo "Configure AriaNg with this secret: $(cat ${rpcSecretFile})"
      fi
    '';
    
    serviceConfig = {
      Type = "simple";
      User = aria2User;
      Group = aria2Group;
      
      # StateDirectory auto-creates /var/lib/aria2 with correct permissions
      # This fixes the "Failed to set up mount namespacing" error
      StateDirectory = "aria2";
      
      # Build the command with optional RPC secret
      ExecStart = let
        secretArg = if builtins.pathExists rpcSecretFile 
          then "--rpc-secret=$(cat ${rpcSecretFile})"
          else "";
      in "${pkgs.aria2}/bin/aria2c --conf-path=${aria2Config} ${secretArg}";
      
      Restart = "on-failure";
      RestartSec = "5s";
      
      # Security hardening
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      
      # Only need write access to download directory (config dir handled by StateDirectory)
      ReadWritePaths = [ downloadDir ];
    };
  };

  # ============================================================================
  # ARIANG WEB UI
  # ============================================================================
  
  # AriaNg is served by Caddy on port 6880 (see caddy.nix)
  # The package is referenced there directly

  # ============================================================================
  # FIREWALL CONFIGURATION
  # ============================================================================

  networking.firewall = {
    allowedTCPPorts = [
      rpcPort  # aria2 RPC
    ];
  };

  # ============================================================================
  # SYSTEM PACKAGES
  # ============================================================================

  environment.systemPackages = with pkgs; [
    aria2   # CLI tool
    ariang  # Web UI (served by Caddy)
  ];
}
