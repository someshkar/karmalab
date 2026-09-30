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
# - http://192.168.68.59 → Homepage dashboard
# - http://192.168.68.59:8096 → Jellyfin (direct, not proxied)
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

  # KOSync (reading progress sync) — public port and container loopback port
  kosyncPort = config.services.kosync.port;
  kosyncInternalPort = config.services.kosync.internalPort;

  # KoInsight reading-stats dashboard port
  statsPort = config.services.koinsight.port;
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

      # KOSync reading-progress sync on port 7200 (all interfaces, incl. LAN).
      # Proxies to the container on loopback so devices only ever need this URL.
      "http://:${toString kosyncPort}" = lib.mkIf config.services.kosync.enable {
        extraConfig = ''
          reverse_proxy 127.0.0.1:${toString kosyncInternalPort}
        '';
      };

      # KoInsight reading-stats dashboard (LAN + Tailscale).
      "http://:${toString statsPort}" = lib.mkIf config.services.koinsight.enable {
        extraConfig = ''
          reverse_proxy 127.0.0.1:${toString statsPort}
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
