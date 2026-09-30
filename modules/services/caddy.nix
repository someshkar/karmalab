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
  statsInternalPort = config.services.koinsight.internalPort;
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

      # KOSync reading-progress sync on port 7200. Serves both the LAN
      # (devices use http://<lan-ip>:7200) and the Cloudflare Tunnel
      # (kosync.somesh.dev -> http://localhost:7200). Because the tunnel
      # forwards to this port, CORS must be configured here rather than on a
      # separate hostname block.
      "http://:${toString kosyncPort}" = lib.mkIf config.services.kosync.enable {
        extraConfig = ''
          # Browser-based readers (Readest web) need CORS; native apps don't.
          # Reflect only allow-listed origins.
          @corsOrigin header_regexp Origin ^https://(web\.readest\.com|readest\.com)$

          header @corsOrigin {
            Access-Control-Allow-Origin "{http.request.header.Origin}"
            Access-Control-Allow-Methods "GET, PUT, POST, OPTIONS"
            Access-Control-Allow-Headers "x-auth-user, x-auth-key, content-type, accept"
            Access-Control-Max-Age "86400"
            Vary "Origin"
          }

          # The app answers OPTIONS with 405, which fails CORS preflight.
          @preflight method OPTIONS
          respond @preflight 204

          reverse_proxy 127.0.0.1:${toString kosyncInternalPort}
        '';
      };

      # KoInsight reading-stats dashboard (LAN + Tailscale).
      "http://:${toString statsPort}" = lib.mkIf config.services.koinsight.enable {
        extraConfig = ''
          reverse_proxy 127.0.0.1:${toString statsInternalPort}
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
