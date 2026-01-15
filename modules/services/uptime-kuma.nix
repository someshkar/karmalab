# modules/services/uptime-kuma.nix
# ============================================================================
# UPTIME KUMA - SERVICE MONITORING
# ============================================================================
#
# Uptime Kuma is a self-hosted monitoring tool like "Uptime Robot".
# It monitors all services and can send notifications when things go down.
#
# Features:
# - HTTP(s), TCP, Ping, DNS monitoring
# - Beautiful status pages
# - Notifications via Email, Telegram, Discord, Slack, etc.
# - Certificate expiry monitoring
#
# Access:
# - LAN: http://192.168.0.200:3001
# - Tailscale: http://nuc-server:3001
# - External: https://status.somesh.dev (via Cloudflare Tunnel)
#
# Note: Notifications are a post-setup task - configure manually via UI
#
# ============================================================================

{ config, lib, pkgs, ... }:

let
  uptimeKumaPort = 3001;
in
{
  # ============================================================================
  # UPTIME KUMA SERVICE
  # ============================================================================
  # Using native NixOS service (available in nixpkgs)
  
  services.uptime-kuma = {
    enable = true;
    
    settings = {
      # Port to listen on
      PORT = toString uptimeKumaPort;
      
      # Listen on all interfaces (not just 127.0.0.1)
      HOST = "0.0.0.0";
      
      # DATA_DIR is managed automatically by NixOS (defaults to /var/lib/uptime-kuma/)
    };
  };
  
  # ============================================================================
  # SERVICE DEPENDENCIES
  # ============================================================================
  # Uptime Kuma should start after storage is available
  
  systemd.services.uptime-kuma = {
    after = [ "storage-online.target" "network-online.target" ];
    wants = [ "storage-online.target" "network-online.target" ];
  };
  
  # ============================================================================
  # FIREWALL
  # ============================================================================
  # Accessible from LAN, Tailscale, and Cloudflare Tunnel
  
  networking.firewall = {
    # Allow LAN access
    allowedTCPPorts = [ uptimeKumaPort ];
    
    # Allow Tailscale access
    interfaces."tailscale0".allowedTCPPorts = [ uptimeKumaPort ];
  };
}
