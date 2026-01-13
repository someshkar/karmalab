# modules/wireguard-vpn-iceland.nix
# ============================================================================
# WIREGUARD VPN NAMESPACE FOR SURFSHARK ICELAND
# ============================================================================
#
# This module creates an isolated network namespace for Iceland VPN traffic.
# Used for indexer searches and subtitle downloads to bypass geo-blocks.
#
# Architecture:
# - Creates a separate network namespace "vpn-iceland"
# - WireGuard interface runs inside this namespace
# - Services bound to the namespace have ALL traffic routed through Iceland VPN
# - Kill-switch: If VPN disconnects, traffic is blocked (not leaked)
# - veth pair connects host namespace to vpn-iceland namespace for local access
#
# Usage:
# - Services that need Iceland VPN use: networkNamespace = "vpn-iceland";
# - Access services from host via veth peer IP (10.200.2.1)
#
# Services using Iceland VPN:
# - Prowlarr (indexer searches) - bypasses 1337x blocks in India/Singapore
# - Bazarr (subtitle downloads) - bypasses OpenSubtitles blocks
# - Shelfmark (book downloads) - bypasses Anna's Archive/Z-Library blocks
#
# Surfshark Configuration:
# - Download WireGuard config from Surfshark dashboard (Iceland server)
# - Extract PrivateKey and server endpoint
# - Store credentials in /etc/wireguard/surfshark-iceland.conf
#
# ============================================================================

{ config, lib, pkgs, ... }:

let
  # VPN namespace name
  vpnNamespace = "vpn-iceland";
  
  # veth pair configuration for host <-> vpn-iceland namespace communication
  # This allows accessing services in the Iceland namespace from the host
  vethHost = "veth-host2";
  vethVpn = "veth-ice";
  hostIp = "10.200.2.1";
  vpnIp = "10.200.2.2";
  subnetMask = "24";
  
  # WireGuard interface name
  wgInterface = "wg-iceland";
  
  # Surfshark Iceland configuration file path
  # This file should contain PrivateKey and peer configuration
  surfsharkConfig = "/etc/wireguard/surfshark-iceland.conf";
in
{
  # ============================================================================
  # WIREGUARD CONFIGURATION
  # ============================================================================
  
  # Enable WireGuard kernel module
  boot.kernelModules = [ "wireguard" ];
  
  # Install wireguard-tools for wg command
  environment.systemPackages = [ pkgs.wireguard-tools ];
  
  # ============================================================================
  # NETWORK NAMESPACE SETUP
  # ============================================================================
  
  # Create the Iceland VPN network namespace
  systemd.services.netns-vpn-iceland = {
    description = "Create Iceland VPN network namespace";
    before = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.iproute2}/bin/ip netns add ${vpnNamespace}";
      ExecStop = "${pkgs.iproute2}/bin/ip netns delete ${vpnNamespace}";
    };
    
    # Don't fail if namespace already exists
    preStart = ''
      ${pkgs.iproute2}/bin/ip netns delete ${vpnNamespace} 2>/dev/null || true
    '';
  };
  
  # Create veth pair for host <-> Iceland VPN namespace communication
  systemd.services.netns-vpn-iceland-veth = {
    description = "Create veth pair for Iceland VPN namespace";
    after = [ "netns-vpn-iceland.service" ];
    requires = [ "netns-vpn-iceland.service" ];
    before = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    
    script = ''
      # Create veth pair
      ${pkgs.iproute2}/bin/ip link add ${vethHost} type veth peer name ${vethVpn}
      
      # Move one end to the Iceland VPN namespace
      ${pkgs.iproute2}/bin/ip link set ${vethVpn} netns ${vpnNamespace}
      
      # Configure host side
      ${pkgs.iproute2}/bin/ip addr add ${hostIp}/${subnetMask} dev ${vethHost}
      ${pkgs.iproute2}/bin/ip link set ${vethHost} up
      
      # Configure Iceland VPN namespace side
      ${pkgs.iproute2}/bin/ip netns exec ${vpnNamespace} ${pkgs.iproute2}/bin/ip addr add ${vpnIp}/${subnetMask} dev ${vethVpn}
      ${pkgs.iproute2}/bin/ip netns exec ${vpnNamespace} ${pkgs.iproute2}/bin/ip link set ${vethVpn} up
      ${pkgs.iproute2}/bin/ip netns exec ${vpnNamespace} ${pkgs.iproute2}/bin/ip link set lo up
    '';
    
    preStart = ''
      # Cleanup any existing veth interfaces
      ${pkgs.iproute2}/bin/ip link delete ${vethHost} 2>/dev/null || true
    '';
  };
  
  # ============================================================================
  # WIREGUARD IN ICELAND VPN NAMESPACE
  # ============================================================================
  
  systemd.services.wireguard-vpn-iceland = {
    description = "WireGuard VPN in namespace (Surfshark Iceland)";
    after = [ "netns-vpn-iceland-veth.service" "network-online.target" ];
    requires = [ "netns-vpn-iceland-veth.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    
    # Clean up any stale WireGuard interface before starting
    preStart = ''
      ${pkgs.iproute2}/bin/ip link delete ${wgInterface} 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip netns exec ${vpnNamespace} ${pkgs.iproute2}/bin/ip link delete ${wgInterface} 2>/dev/null || true
    '';
    
    script = ''
      # Create WireGuard interface in host namespace, then move to vpn-iceland namespace
      ${pkgs.iproute2}/bin/ip link add ${wgInterface} type wireguard
      ${pkgs.iproute2}/bin/ip link set ${wgInterface} netns ${vpnNamespace}
      
      # Configure WireGuard inside the namespace
      ${pkgs.iproute2}/bin/ip netns exec ${vpnNamespace} ${pkgs.wireguard-tools}/bin/wg setconf ${wgInterface} ${surfsharkConfig}
      
      # Get the address from config (Surfshark provides this)
      # Default Surfshark address is typically 10.14.0.2/16
      ${pkgs.iproute2}/bin/ip netns exec ${vpnNamespace} ${pkgs.iproute2}/bin/ip addr add 10.14.0.2/16 dev ${wgInterface}
      ${pkgs.iproute2}/bin/ip netns exec ${vpnNamespace} ${pkgs.iproute2}/bin/ip link set ${wgInterface} up
      
      # Set default route through WireGuard (this is the kill-switch)
      ${pkgs.iproute2}/bin/ip netns exec ${vpnNamespace} ${pkgs.iproute2}/bin/ip route add default dev ${wgInterface}
      
      # Allow traffic to host via veth (for local service access)
      ${pkgs.iproute2}/bin/ip netns exec ${vpnNamespace} ${pkgs.iproute2}/bin/ip route add ${hostIp}/32 via ${vpnIp} dev ${vethVpn}
      
      # Add route to local network (allows Bazarr to reach Radarr/Sonarr)
      ${pkgs.iproute2}/bin/ip netns exec ${vpnNamespace} ${pkgs.iproute2}/bin/ip route add 192.168.0.0/24 via ${hostIp} dev ${vethVpn}
    '';
    
    preStop = ''
      ${pkgs.iproute2}/bin/ip netns exec ${vpnNamespace} ${pkgs.iproute2}/bin/ip link delete ${wgInterface} 2>/dev/null || true
    '';
  };
  
  # ============================================================================
  # DNS RESOLUTION IN ICELAND VPN NAMESPACE
  # ============================================================================
  
  # Create resolv.conf for the Iceland VPN namespace
  # Uses Surfshark DNS or Cloudflare as fallback
  systemd.services.vpn-iceland-dns = {
    description = "Configure DNS for Iceland VPN namespace";
    after = [ "wireguard-vpn-iceland.service" ];
    requires = [ "wireguard-vpn-iceland.service" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    
    script = ''
      mkdir -p /etc/netns/${vpnNamespace}
      cat > /etc/netns/${vpnNamespace}/resolv.conf << EOF
# Surfshark DNS servers (for privacy)
nameserver 162.252.172.57
nameserver 149.154.159.92
# Cloudflare fallback
nameserver 1.1.1.1
nameserver 1.0.0.1
EOF
    '';
  };
  
  # ============================================================================
  # VPN STATUS CHECK SERVICE
  # ============================================================================
  
  # Periodic check to verify Iceland VPN is working
  systemd.services.vpn-iceland-health-check = {
    description = "Check Iceland VPN connection health";
    after = [ "wireguard-vpn-iceland.service" ];
    requires = [ "wireguard-vpn-iceland.service" ];
    
    serviceConfig = {
      Type = "oneshot";
    };
    
    script = ''
      echo "Checking Iceland VPN connection..."
      PUBLIC_IP=$(${pkgs.iproute2}/bin/ip netns exec ${vpnNamespace} ${pkgs.curl}/bin/curl -s --connect-timeout 10 https://api.ipify.org)
      if [ -n "$PUBLIC_IP" ]; then
        echo "Iceland VPN connected. Public IP: $PUBLIC_IP"
      else
        echo "WARNING: Iceland VPN may be disconnected!"
        exit 1
      fi
    '';
  };
  
  # Run health check every 5 minutes
  systemd.timers.vpn-iceland-health-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "5min";
      Unit = "vpn-iceland-health-check.service";
    };
  };
  
  # ============================================================================
  # FIREWALL RULES FOR ICELAND VPN NAMESPACE
  # ============================================================================
  
  # Allow traffic from host to Iceland VPN namespace via veth
  networking.firewall.extraCommands = ''
    # Allow all traffic on veth interface (host <-> vpn-iceland namespace)
    iptables -A INPUT -i ${vethHost} -j ACCEPT
    iptables -A OUTPUT -o ${vethHost} -j ACCEPT
    
    # Allow forwarding for namespace communication
    iptables -A FORWARD -i ${vethHost} -j ACCEPT
    iptables -A FORWARD -o ${vethHost} -j ACCEPT
  '';
}
