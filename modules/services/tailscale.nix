# modules/services/tailscale.nix
# ============================================================================
# TAILSCALE VPN SERVICE
# ============================================================================
#
# Tailscale provides secure remote access to the homelab from anywhere.
# This configuration sets up the NUC as an exit node, allowing other devices
# to route their traffic through the home network.
#
# Features:
# - Secure mesh VPN (WireGuard-based)
# - Exit node capability for routing traffic through home network
# - MagicDNS for easy device discovery
# - No port forwarding required
#
# Setup:
# 1. Create auth key at https://login.tailscale.com/admin/settings/keys
#    - Make it reusable if you want to rebuild without new keys
#    - Enable "Pre-authorized" to skip manual approval
# 2. Store the key in /etc/nixos/secrets/tailscale-auth-key
# 3. After deployment, approve exit node in Tailscale admin console
#
# Usage:
# - Access services via Tailscale IP or MagicDNS name
# - Enable exit node on client devices to route all traffic through home
#
# ============================================================================

{ config, lib, pkgs, ... }:

let
  # Path to the auth key file (not stored in git)
  authKeyFile = "/etc/nixos/secrets/tailscale-auth-key";
in
{
  # ============================================================================
  # TAILSCALE SERVICE
  # ============================================================================

  services.tailscale = {
    enable = true;
    
    # Use the auth key file for automatic authentication
    authKeyFile = authKeyFile;
    
    # Advertise as exit node so other devices can route through this server
    extraUpFlags = [
      "--advertise-exit-node"
      "--accept-routes"
      "--accept-dns=false"  # Don't override local DNS
    ];
    
    # Open firewall for Tailscale
    openFirewall = true;
  };

  # ============================================================================
  # IP FORWARDING FOR EXIT NODE
  # ============================================================================
  
  # Required for exit node functionality - allows forwarding traffic
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # ============================================================================
  # FIREWALL CONFIGURATION
  # ============================================================================

  networking.firewall = {
    # Trust the Tailscale interface
    trustedInterfaces = [ "tailscale0" ];
    
    # Allow Tailscale UDP port
    allowedUDPPorts = [ config.services.tailscale.port ];
    
    # Enable masquerading for exit node (NAT for forwarded traffic)
    extraCommands = ''
      iptables -t nat -A POSTROUTING -o enp1s0 -j MASQUERADE
    '';
    extraStopCommands = ''
      iptables -t nat -D POSTROUTING -o enp1s0 -j MASQUERADE || true
    '';
  };

  # ============================================================================
  # SYSTEM PACKAGES
  # ============================================================================

  environment.systemPackages = with pkgs; [
    tailscale  # CLI tool for managing Tailscale
  ];
}
