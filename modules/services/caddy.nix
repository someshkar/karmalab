# modules/services/caddy.nix
# ============================================================================
# CADDY REVERSE PROXY
# ============================================================================
#
# Caddy serves as the local reverse proxy for the homelab dashboard and services.
# It provides:
# - Port 80 access to Homepage dashboard (no need to remember ports)
# - Future: Can proxy other services via paths (e.g., /jellyfin)
# - Automatic HTTPS with self-signed certs (if enabled later)
#
# Access:
# - http://192.168.0.200 → Homepage dashboard
# - http://192.168.0.200:8096 → Jellyfin (direct, not proxied)
#
# Note: External access is handled by Cloudflare Tunnel, not Caddy.
# Caddy is for local network convenience only.
#
# ============================================================================

{ config, lib, pkgs, ... }:

let
  # Homepage port (default 8082 for homepage-dashboard)
  homepagePort = 8082;
  
  # AriaNg port
  ariangPort = 6880;
in
{
  # ============================================================================
  # CADDY SERVICE
  # ============================================================================

  services.caddy = {
    enable = true;
    
    # Global options
    globalConfig = ''
      # Disable automatic HTTPS for local network
      auto_https off
    '';
    
    # Virtual hosts configuration
    virtualHosts = {
      # Default site - Homepage dashboard
      "http://:80" = {
        extraConfig = ''
          # Serve update status JSON for Homepage widget
          handle /updates.json {
            root * /var/lib/beszel-agent/custom-metrics
            file_server
            header Content-Type application/json
          }
          
          # Root path goes to Homepage
          reverse_proxy localhost:${toString homepagePort}
        '';
      };
      
      # AriaNg web UI on port 6880
      "http://:${toString ariangPort}" = {
        extraConfig = ''
          root * ${pkgs.ariang}/share/ariang
          file_server
        '';
      };
    };
  };

  # ============================================================================
  # FIREWALL CONFIGURATION
  # ============================================================================

  networking.firewall = {
    allowedTCPPorts = [
      80      # HTTP - Homepage via Caddy
      ariangPort  # AriaNg web UI
    ];
  };
}
