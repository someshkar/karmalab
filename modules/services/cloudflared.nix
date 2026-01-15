# modules/services/cloudflared.nix
# ============================================================================
# CLOUDFLARE TUNNEL (CLOUDFLARED)
# ============================================================================
#
# Cloudflare Tunnel provides secure external access to homelab services
# without exposing ports or requiring a static IP.
#
# Exposed Services (configured in Cloudflare Zero Trust dashboard):
# - git.somesh.dev      → Forgejo (port 3030)
# - immich.somesh.dev   → Immich (port 2283)
# - jellyfin.somesh.dev → Jellyfin (port 8096)
# - jellyseer.somesh.dev → Jellyseerr (port 5055)
# - sync.somesh.dev     → Syncthing protocol (port 22000, TCP)
# - vault.somesh.dev    → Vaultwarden (port 8222)
# - abs.somesh.dev      → Audiobookshelf (port 13378)
# - books.somesh.dev    → Calibre-Web (port 8083)
# - shelfmark.somesh.dev → Shelfmark (port 8084)
# - home.somesh.dev     → Homepage Dashboard (port 8082)
# - status.somesh.dev   → Uptime Kuma (port 3001) [optional]
#
# Setup:
# 1. Create tunnel in Cloudflare Zero Trust dashboard
# 2. Add public hostnames for each service in the dashboard
# 3. Copy tunnel token to /etc/nixos/secrets/cloudflared-tunnel-token
#
# The tunnel token is from the "Install connector" step in Cloudflare dashboard.
# It looks like: eyJhIjoiYWM2NzY3ODU3YjQ0Mjg0MTVkODgyMTgx...
#
# This uses token-based authentication (not credentials file), which means
# all routing/ingress rules are managed in the Cloudflare dashboard, not here.
#
# ============================================================================

{ config, lib, pkgs, ... }:

let
  # Path to the tunnel token file
  tunnelTokenFile = "/etc/nixos/secrets/cloudflared-tunnel-token";
in
{
  # ============================================================================
  # CLOUDFLARED TUNNEL SERVICE (Token-based)
  # ============================================================================
  #
  # We use a custom systemd service instead of services.cloudflared.tunnels
  # because the NixOS module expects a credentials JSON file, but we have
  # a tunnel token from the Cloudflare dashboard.
  #

  systemd.services.cloudflared-tunnel = {
    description = "Cloudflare Tunnel (token-based)";
    documentation = [ "https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/" ];
    
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "simple";
      
      # Run as root to read secrets
      User = "root";
      
      # Use cloudflared's native --token-file flag (cleaner than bash wrapper)
      # The token contains the tunnel ID and credentials
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel run --token-file ${tunnelTokenFile}";
      
      Restart = "on-failure";
      RestartSec = "5s";
      
      # Security hardening
      # Note: ProtectHome=true would break access to /etc/nixos/secrets
      # because /etc/nixos is symlinked to /home/somesh/karmalab
      NoNewPrivileges = true;
      PrivateTmp = true;
    };
  };

  # ============================================================================
  # SYSTEM PACKAGES
  # ============================================================================

  environment.systemPackages = with pkgs; [
    cloudflared  # CLI tool for debugging
  ];
}
