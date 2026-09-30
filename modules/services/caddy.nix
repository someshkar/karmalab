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

  # Browser-based readers (e.g. Readest web at web.readest.com) fetch KOSync
  # cross-origin, which needs CORS. Neither the official nor self-hosted KOSync
  # servers send CORS headers, so we add them at the proxy for the browser
  # reader origins only. Native apps (KOReader, Readest desktop/iOS) are
  # unaffected — CORS is a browser concept.
  kosyncCorsOrigins = [
    "https://web.readest.com"
    "https://readest.com"
  ];
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

      # Public HTTPS entrypoint for KOSync, reached via the Cloudflare Tunnel
      # (kosync.somesh.dev -> localhost:7200; see modules/services/cloudflared.nix).
      # Caddy's auto_https is off because Cloudflare terminates TLS. This block
      # exists to add CORS headers for browser-based readers.
      "http://kosync.somesh.dev" = lib.mkIf config.services.kosync.enable {
        extraConfig = ''
          # Only reflect an allow-listed browser origin.
          @corsOrigin header_regexp Origin ^https://(web\.readest\.com|readest\.com)$

          header @corsOrigin {
            Access-Control-Allow-Origin "{http.request.header.Origin}"
            Access-Control-Allow-Methods "GET, PUT, POST, OPTIONS"
            Access-Control-Allow-Headers "x-auth-user, x-auth-key, content-type, accept"
            Access-Control-Max-Age "86400"
            Vary "Origin"
          }

          # The app does not implement OPTIONS, so answer preflight here.
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
