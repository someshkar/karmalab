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
# - Local: http://localhost:3001
# - Tailscale: http://nuc-server:3001
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
      
      # Data directory (will be on ZFS via storage.nix mount)
      DATA_DIR = "/var/lib/private/uptime-kuma";
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
  # Only accessible via Tailscale (admin interface)
  
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 
    uptimeKumaPort 
  ];
}
