# modules/wireguard-vpn.nix
# ============================================================================
# WIREGUARD VPN NAMESPACE FOR SURFSHARK
# ============================================================================
#
# This module creates an isolated network namespace for VPN traffic.
# Inspired by Wolfgang's nix-config approach.
#
# Architecture:
# - Creates a separate network namespace "vpn"
# - WireGuard interface runs inside this namespace
# - Services bound to the namespace have ALL traffic routed through VPN
# - Kill-switch: If VPN disconnects, traffic is blocked (not leaked)
# - veth pair connects host namespace to vpn namespace for local access
#
# Usage:
# - Services that need VPN use: networkNamespace = "vpn";
# - Access services from host via veth peer IP (10.200.1.1)
#
# Surfshark Configuration:
# - Download WireGuard config from Surfshark dashboard
# - Extract PrivateKey and server endpoint
# - Store credentials in /etc/wireguard/surfshark.conf
#
# ============================================================================

{ config, lib, pkgs, ... }:

let
  # VPN namespace name
  vpnNamespace = "vpn";
  
  # veth pair configuration for host <-> vpn namespace communication
  # This allows accessing services in the VPN namespace from the host
  vethHost = "veth-host";
  vethVpn = "veth-vpn";
  hostIp = "10.200.1.1";
  vpnIp = "10.200.1.2";
  subnetMask = "24";
  
  # WireGuard interface name
  wgInterface = "wg-surfshark";
  
  # Surfshark configuration file path
  # This file should contain PrivateKey and peer configuration
  surfsharkConfig = "/etc/wireguard/surfshark.conf";
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
  
  # Create the VPN network namespace
  systemd.services.netns-vpn = {
    description = "Create VPN network namespace";
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
  
  # Create veth pair for host <-> VPN namespace communication
  systemd.services.netns-vpn-veth = {
    description = "Create veth pair for VPN namespace";
    after = [ "netns-vpn.service" ];
    requires = [ "netns-vpn.service" ];
    before = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    
    script = ''
      # Create veth pair
      ${pkgs.iproute2}/bin/ip link add ${vethHost} type veth peer name ${vethVpn}
      
      # Move one end to the VPN namespace
      ${pkgs.iproute2}/bin/ip link set ${vethVpn} netns ${vpnNamespace}
      
      # Configure host side
      ${pkgs.iproute2}/bin/ip addr add ${hostIp}/${subnetMask} dev ${vethHost}
      ${pkgs.iproute2}/bin/ip link set ${vethHost} up
      
      # Configure VPN namespace side
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
  # WIREGUARD IN VPN NAMESPACE
  # ============================================================================
  
  systemd.services.wireguard-vpn = {
    description = "WireGuard VPN in namespace (Surfshark)";
    after = [ "netns-vpn-veth.service" "network-online.target" ];
    requires = [ "netns-vpn-veth.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    
    script = ''
      # Create WireGuard interface in host namespace, then move to vpn namespace
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
    '';
    
    preStop = ''
      ${pkgs.iproute2}/bin/ip netns exec ${vpnNamespace} ${pkgs.iproute2}/bin/ip link delete ${wgInterface} 2>/dev/null || true
    '';
  };
  
  # ============================================================================
  # DNS RESOLUTION IN VPN NAMESPACE
  # ============================================================================
  
  # Create resolv.conf for the VPN namespace
  # Uses Surfshark DNS or Cloudflare as fallback
  systemd.services.vpn-dns = {
    description = "Configure DNS for VPN namespace";
    after = [ "wireguard-vpn.service" ];
    requires = [ "wireguard-vpn.service" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    
    script = ''
      mkdir -p /etc/netns/${vpnNamespace}
      cat > /etc/netns/${vpnNamespace}/resolv.conf << EOF
# Surfshark DNS servers (optional, for privacy)
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
  
  # Periodic check to verify VPN is working
  systemd.services.vpn-health-check = {
    description = "Check VPN connection health";
    after = [ "wireguard-vpn.service" ];
    requires = [ "wireguard-vpn.service" ];
    
    serviceConfig = {
      Type = "oneshot";
    };
    
    script = ''
      echo "Checking VPN connection..."
      PUBLIC_IP=$(${pkgs.iproute2}/bin/ip netns exec ${vpnNamespace} ${pkgs.curl}/bin/curl -s --connect-timeout 10 https://api.ipify.org)
      if [ -n "$PUBLIC_IP" ]; then
        echo "VPN connected. Public IP: $PUBLIC_IP"
      else
        echo "WARNING: VPN may be disconnected!"
        exit 1
      fi
    '';
  };
  
  # Run health check every 5 minutes
  systemd.timers.vpn-health-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "5min";
      Unit = "vpn-health-check.service";
    };
  };
  
  # ============================================================================
  # FIREWALL RULES FOR VPN NAMESPACE
  # ============================================================================
  
  # Allow traffic from host to VPN namespace via veth
  networking.firewall.extraCommands = ''
    # Allow all traffic on veth interface (host <-> vpn namespace)
    iptables -A INPUT -i ${vethHost} -j ACCEPT
    iptables -A OUTPUT -o ${vethHost} -j ACCEPT
  '';
}
