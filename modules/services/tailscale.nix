# modules/services/tailscale.nix
# ============================================================================
# TAILSCALE VPN SERVICE
# ============================================================================
#
# Tailscale provides secure remote access to the homelab from anywhere.
# This configuration sets up the NUC as an exit node and subnet router,
# allowing remote access to the entire home network (192.168.0.0/24).
#
# Features:
# - Secure mesh VPN (WireGuard-based)
# - Exit node capability for routing internet traffic through home network
# - Subnet routing for accessing ALL home network devices (192.168.0.0/24)
# - MagicDNS for easy device discovery
# - No port forwarding required
#
# Setup:
# 1. Create auth key at https://login.tailscale.com/admin/settings/keys
#    - Make it reusable if you want to rebuild without new keys
#    - Enable "Pre-authorized" to skip manual approval
# 2. Store the key in /etc/nixos/secrets/tailscale-auth-key
# 3. After deployment, approve exit node AND subnet route in Tailscale admin console
#    - Go to https://login.tailscale.com/admin/machines
#    - Find "karmalab" device
#    - Approve subnet route: 192.168.0.0/24
#
# Usage:
# - Access karmalab services via Tailscale IP or MagicDNS name
# - Access ANY home network device via 192.168.0.x (printer, router, etc.)
# - Enable exit node on client devices to route all internet traffic through home
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
    
    # Advertise as exit node and subnet router
    extraUpFlags = [
      "--advertise-exit-node"
      "--advertise-routes=192.168.0.0/24"  # Advertise home network subnet
      "--accept-routes"
      "--accept-dns=false"  # Don't override local DNS
    ];
    
    # Open firewall for Tailscale
    openFirewall = true;
  };

  # ============================================================================
  # IP FORWARDING FOR EXIT NODE AND SUBNET ROUTING
  # ============================================================================
  
  # Required for exit node and subnet router functionality - allows forwarding traffic
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
    
    # Enable masquerading for exit node and subnet routing (NAT for forwarded traffic)
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
