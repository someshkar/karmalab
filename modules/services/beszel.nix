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
  agentPort = 45876;  # Default Beszel agent port
  
  # Paths
  hubDataDir = "/var/lib/beszel";
  hubDataVolume = "beszel_data";
  agentDataVolume = "beszel_agent_data";
  socketVolume = "beszel_socket";
  
  # Docker images
  hubImage = "henrygd/beszel:latest";
  agentImage = "henrygd/beszel-agent:latest";
in
{
  # ============================================================================
  # DOCKER CONTAINERS WITH OCI CONTAINERS BACKEND
  # ============================================================================
  
  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      beszel-hub = {
        image = hubImage;
        container_name = "beszel";
        autoStart = true;
        
        # Port mapping
        ports = [ "${toString hubPort}:8090" ];
        
        # Volumes for data storage
        volumes = [
          "${hubDataVolume}:${hubDataDir}"
          "${socketVolume}:/beszel_socket"
        ];
        
        # Restart policy
        extraOptions = "--restart=unless-stopped";
        
        # Environment variables (optional, can add later)
        environment = {
          TZ = "Asia/Kolkata";
        };
      };
      
      beszel-agent = {
        image = agentImage;
        container_name = "beszel-agent";
        autoStart = true;
        
        # Host network mode for system metrics access
        extraOptions = [
          "--network=host"
        ];
        
        # Volumes for Docker socket, data, and socket communication
        volumes = [
          "/var/run/docker.sock:/var/run/docker.sock:ro"
          "${agentDataVolume}:/var/lib/beszel-agent"
          "${socketVolume}:/beszel_socket"
        ];
        
        # Environment variables for connection
        environment = {
          LISTEN = "/beszel_socket/beszel.sock";
          HUB_URL = "http://localhost:${toString hubPort}";
          TZ = "Asia/Kolkata";
          # KEY and TOKEN will be generated automatically on first connection
          # These can be set manually for automation:
          # KEY = "";
          # TOKEN = "";
        };
        
        # Restart policy
          extraOptions = "--restart=unless-stopped";
       };
     };
   };
  };
  
  # ============================================================================
  # SYSTEMD SERVICE CONFIGURATION
  # ============================================================================
  
  systemd = {
    # Beszel Hub Service (Docker container management)
    services.docker-beszel = {
      description = "Beszel Hub - Lightweight server monitoring dashboard";
      serviceConfig = {
        Type = "simple";
        
        # Wait for Docker daemon and network
        After = [ "docker.service" "network-online.target" "storage-online.target" ];
        Wants = [ "docker.service" "network-online.target" ];
        RequiredBy = [ "multi-user.target" ];
        
        # Use Docker Compose approach (equivalent to docker compose up -d)
        ExecStart = "${pkgs.docker-compose}/bin/docker-compose -f ${pkgs.writeText "docker-compose.yml" ''
          version: '3.8'
          
          services:
            beszel:
              image: ${hubImage}
              container_name: beszel
              restart: unless-stopped
              ports:
                - "${toString hubPort}:8090"
              volumes:
                - ${hubDataVolume}:${hubDataDir}
                - ${socketVolume}:/beszel_socket
              environment:
                TZ: Asia/Kolkata
        ''} -p /var/lib/beszel up -d";
        
        ExecStop = "${pkgs.docker-compose}/bin/docker-compose -f ${pkgs.writeText "docker-compose.yml" ''
          version: '3.8'
          
          services:
            beszel:
              image: ${hubImage}
              container_name: beszel
              restart: unless-stopped
              ports:
                - "${toString hubPort}:8090"
              volumes:
                - ${hubDataVolume}:${hubDataDir}
                - ${socketVolume}:/beszel_socket
              environment:
                TZ: Asia/Kolkata
        ''} -p /var/lib/beszel down";
        
        Restart = "always";
        RestartSec = "10s";
      };
    };
    
    # Beszel Agent Service (Docker container management)
    services.docker-beszel-agent = {
      description = "Beszel Agent - System metrics collector";
      serviceConfig = {
        Type = "simple";
        
        # Wait for Docker daemon, network, and hub
        After = [ "docker.service" "network-online.target" "docker-beszel.service" ];
        Wants = [ "docker.service" "network-online.target" ];
        RequiredBy = [ "multi-user.target" ];
        
        # Use Docker Compose approach
        ExecStart = "${pkgs.docker-compose}/bin/docker-compose -f ${pkgs.writeText "docker-compose-agent.yml" ''
          version: '3.8'
          
          services:
            beszel-agent:
              image: ${agentImage}
              container_name: beszel-agent
              restart: unless-stopped
              network_mode: host
              volumes:
                - /var/run/docker.sock:/var/run/docker.sock:ro
                - ${agentDataVolume}:/var/lib/beszel-agent
                - ${socketVolume}:/beszel_socket
              environment:
                LISTEN: /beszel_socket/beszel.sock
                HUB_URL: http://localhost:${toString hubPort}
                TZ: Asia/Kolkata
        ''} -p /var/lib/beszel-agent up -d";
        
        ExecStop = "${pkgs.docker-compose}/bin/docker-compose -f ${pkgs.writeText "docker-compose-agent.yml" ''
          version: '3.8'
          
          services:
            beszel-agent:
              image: ${agentImage}
              container_name: beszel-agent
              restart: unless-stopped
              network_mode: host
              volumes:
                - /var/run/docker.sock:/var/run/docker.sock:ro
                - ${agentDataVolume}:/var/lib/beszel-agent
                - ${socketVolume}:/beszel_socket
              environment:
                LISTEN: /beszel_socket/beszel.sock
                HUB_URL: http://localhost:${toString hubPort}
                TZ: Asia/Kolkata
        ''} -p /var/lib/beszel-agent down";
        
        Restart = "always";
        RestartSec = "10s";
      };
    };
  };
  
  # ============================================================================
  # DIRECTORY SETUP
  # ============================================================================
  
  # Create data directories with correct permissions
  systemd.tmpfiles.rules = [
    # Hub data directory (owned by root, but readable by containers)
    "d ${hubDataDir} 0755 root root -"
    
    # Hub socket directory for agent communication
    "d /var/lib/beszel/${socketVolume} 0755 root root -"
    
    # Agent data directory
    "d /var/lib/beszel-agent 0755 root root -"
  ];
  
  # ============================================================================
  # FIREWALL CONFIGURATION
  # ============================================================================
  
  networking.firewall = {
    # Allow Beszel hub port access from LAN and Tailscale
    allowedTCPPorts = [ hubPort ];
    
    # Also allow on Tailscale interface
    interfaces."tailscale0".allowedTCPPorts = [ hubPort ];
  };
  
  # ============================================================================
  # PACKAGE REQUIREMENTS
  # ============================================================================
  
  # Docker Compose for container management
  environment.systemPackages = with pkgs; [
    docker
    docker-compose
  ];
  
  # ============================================================================
  # STORAGE DEPENDENCIES
  # ============================================================================
  
  # Ensure Beszel services start after storage is available
  systemd.services.beszel-hub.after = [ "storage-online.target" ];
  systemd.services.beszel-hub.wants = [ "storage-online.target" ];
  
  systemd.services.beszel-agent.after = [ "storage-online.target" ];
  systemd.services.beszel-agent.wants = [ "storage-online.target" ];
}