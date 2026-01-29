# modules/services/beszel.nix
# ============================================================================
# BESZEL - LIGHTWEIGHT SERVER MONITORING HUB + AGENT
# ============================================================================
#
# Beszel is a lightweight server monitoring platform written in Go that includes Docker 
# statistics, historical data, and alert functions. It consists of two components:
#
# 1. Hub: Web application built on PocketBase that provides dashboard
# 2. Agent: Runs on each system and communicates metrics to hub
#
# Features:
# - Lightweight: Smaller and less resource-intensive than leading solutions
# - Simple: Easy setup, ready to use out of box
# - Docker stats: Tracks CPU, memory, network usage for each container
# - Historical data: Configurable retention (1 month default)
# - Alerts: CPU, memory, disk, bandwidth, temperature, load average
# - Multi-user: Users manage their own systems
# - Systemd services: Monitor individual native services
#
# Perfect for hybrid setup: NixOS native services + Docker containers
# - Native services: jellyfin, radarr, sonarr, bazarr, deluge, etc.
# - Docker containers: lazylibrarian, immich, gluetun, etc.
#
# Access:
# - Local: http://192.168.0.200:8090
# - Tailscale: http://karmalab:8090
# - External: https://status.somesh.dev (via Cloudflare Tunnel)
#
# Data storage: /var/lib/beszel (NVMe SSD, minimal space usage)
# Data retention: 1 month (3 days detailed, 30 days daily summaries)
#
# ============================================================================

{ config, lib, pkgs, ... }:

let
  # Port configuration
  hubPort = 8090;
  
  # Paths
  hubDataDir = "/var/lib/beszel";
  agentDataDir = "/var/lib/beszel-agent";
  socketDir = "/var/lib/beszel-socket";
  
  # Docker images
  hubImage = "henrygd/beszel:latest";
  agentImage = "henrygd/beszel-agent:latest";
in
{
  # ============================================================================
  # DOCKER CONTAINERS
  # ============================================================================
  
  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      # Beszel Hub - Web dashboard
      beszel-hub = {
        image = hubImage;
        autoStart = true;
        
        # Port mapping
        ports = [ "${toString hubPort}:8090" ];
        
        # Data storage
        volumes = [
          "${hubDataDir}:/beszel_data"
          "${socketDir}:/beszel_socket"
        ];
        
        # Configuration
        extraOptions = [
          # NixOS oci-containers handles restart policy automatically
        ];
        
        environment = {
          TZ = "Asia/Kolkata";
        };
      };
      
      # Beszel Agent - System metrics collector
      beszel-agent = {
        image = agentImage;
        autoStart = true;
        
        # Host network mode for system metrics + Docker socket access
        extraOptions = [
          "--network=host"
          # NixOS oci-containers handles restart policy automatically
        ];
        
        # Volumes for Docker monitoring and communication
        volumes = [
          "/var/run/docker.sock:/var/run/docker.sock:ro"
          "${agentDataDir}:/var/lib/beszel-agent"
          "${socketDir}:/beszel_socket"
        ];
        
        # Agent configuration
        environment = {
          # Use Unix socket for hub communication (no network overhead)
          LISTEN = "/beszel_socket/beszel.sock";
          HUB_URL = "http://localhost:${toString hubPort}";
          TZ = "Asia/Kolkata";
          # KEY and TOKEN will be generated automatically on first connection
        };
      };
    };
  };
  
  # ============================================================================
  # STORAGE SETUP
  # ============================================================================
  
  # Create data directories with correct permissions
  systemd.tmpfiles.rules = [
    "d ${hubDataDir} 0755 root root -"
    "d ${agentDataDir} 0755 root root -"
    "d ${socketDir} 0755 root root -"
  ];
  
  # ============================================================================
  # NETWORKING
  # ============================================================================
  
  networking.firewall = {
    # Allow Beszel hub port access from LAN
    allowedTCPPorts = [ hubPort ];
    
    # Also allow on Tailscale interface
    interfaces."tailscale0".allowedTCPPorts = [ hubPort ];
  };
  
  # ============================================================================
  # SERVICE DEPENDENCIES
  # ============================================================================
  
  # Ensure containers start after Docker and storage are ready
  systemd.services = {
    docker-beszel-hub = {
      after = [ "docker.service" "storage-online.target" ];
      wants = [ "storage-online.target" ];
    };
    
    docker-beszel-agent = {
      after = [ "docker.service" "docker-beszel-hub.service" ];
      wants = [ "docker-beszel-hub.service" ];
    };
  };
}