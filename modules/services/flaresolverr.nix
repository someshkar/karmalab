# modules/services/flaresolverr.nix
# ============================================================================
# FLARESOLVERR - Cloudflare Bypass Proxy for Prowlarr
# ============================================================================
#
# FlareSolverr is a proxy server to bypass Cloudflare and DDoS-GUARD protection.
# It uses a headless browser (Chrome) to solve challenges automatically.
#
# Used by: Prowlarr (for indexers behind Cloudflare)
# Port: 8191
# Access: http://localhost:8191
#
# Configuration in Prowlarr:
#   Settings → Indexers → Add Indexer Proxy → FlareSolverr
#   Host: http://localhost:8191
#   Request Timeout: 60
#
# ============================================================================

{ config, lib, pkgs, ... }:

let
  flareSolverrPort = 8191;
in
{
  # FlareSolverr runs as a Docker container
  virtualisation.oci-containers.containers.flaresolverr = {
    image = "ghcr.io/flaresolverr/flaresolverr:latest";
    autoStart = true;
    ports = [ "${toString flareSolverrPort}:8191" ];
    environment = {
      LOG_LEVEL = "info";
      TZ = "Asia/Kolkata";
    };
  };

  # Open firewall port for local network access
  networking.firewall.allowedTCPPorts = [ flareSolverrPort ];
}
