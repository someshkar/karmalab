# modules/services/cloudflared.nix
# ============================================================================
# CLOUDFLARE TUNNEL (CLOUDFLARED)
# ============================================================================
#
# Cloudflare Tunnel provides secure external access to homelab services
# without exposing ports or requiring a static IP.
#
# Exposed Services:
# - git.somesh.dev      → Forgejo (port 3030)
# - immich.somesh.dev   → Immich (port 2283)
# - jellyfin.somesh.dev → Jellyfin (port 8096)
# - request.somesh.dev  → Jellyseerr (port 5055)
# - sync.somesh.dev     → Syncthing protocol (port 22000, TCP)
#
# Setup:
# 1. Create tunnel in Cloudflare Zero Trust dashboard
# 2. Add public hostnames for each service
# 3. Copy tunnel token to /etc/nixos/secrets/cloudflared-tunnel-token
#
# The tunnel token is from the "Install connector" step in Cloudflare dashboard.
# It looks like: eyJhIjoiYWM2NzY3ODU3YjQ0Mjg0MTVkODgyMTgx...
#
# ============================================================================

{ config, lib, pkgs, ... }:

let
  # Path to the tunnel token file
  tunnelTokenFile = "/etc/nixos/secrets/cloudflared-tunnel-token";
in
{
  # ============================================================================
  # CLOUDFLARED SERVICE
  # ============================================================================

  services.cloudflared = {
    enable = true;
    
    # Use tunnel token for authentication
    # The token contains all configuration including ingress rules
    # that were set up in the Cloudflare dashboard
    tunnels = {
      "karmalab" = {
        credentialsFile = tunnelTokenFile;
        default = "http_status:404";
        
        # Ingress rules - these should match what's in Cloudflare dashboard
        # The dashboard config takes precedence, but we define them here for documentation
        ingress = {
          "git.somesh.dev" = "http://localhost:3030";
          "immich.somesh.dev" = "http://localhost:2283";
          "jellyfin.somesh.dev" = "http://localhost:8096";
          "request.somesh.dev" = "http://localhost:5055";
          # Note: sync.somesh.dev (TCP) is configured in dashboard only
        };
      };
    };
  };

  # ============================================================================
  # SYSTEM PACKAGES
  # ============================================================================

  environment.systemPackages = with pkgs; [
    cloudflared  # CLI tool for debugging
  ];
}
