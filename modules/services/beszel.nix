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
# Security: Credentials stored in /etc/beszel/ (outside git repository)
# - /etc/beszel/key: SSH public key for agent authentication
# - /etc/beszel/token: Token for hub-agent communication
#
# Connection: Network-based (localhost:45876) - hub connects to agent via TCP
#
# ============================================================================

{ config, lib, pkgs, ... }:

let
  # Port configuration
  hubPort = 8090;
  agentPort = 45876;
  
  # Paths
  hubDataDir = "/var/lib/beszel";
  agentDataDir = "/var/lib/beszel-agent";
  
  # Credential files (outside git repository)
  keyFile = "/etc/beszel/key";
  tokenFile = "/etc/beszel/token";
  
  # Docker images
  hubImage = "henrygd/beszel:latest";
  agentImage = "henrygd/beszel-agent:latest";
in
{
  # ============================================================================
  # FILE VALIDATION AND SECURITY CHECKS
  # ============================================================================
  
  # Ensure credential files exist and have correct format before building
  assertions = [
    {
      assertion = builtins.pathExists keyFile;
      message = ''
        Beszel key file missing: ${keyFile}
        Run: echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHXaSnmtNUWd4ATzK5b6agpX+G9a4GcDyOA0Clj8mQ+m' | sudo tee ${keyFile}
      '';
    }
    {
      assertion = builtins.pathExists tokenFile;  
      message = ''
        Beszel token file missing: ${tokenFile}
        Run: echo 'bfd-a40957f8778-1f39-ae53606608' | sudo tee ${tokenFile}
      '';
    }
    {
      assertion = lib.hasPrefix "ssh-ed25519" (lib.removeSuffix "\n" (builtins.readFile keyFile));
      message = ''
        Invalid Beszel key format in ${keyFile}
        Expected format: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5...
        Current content: ${builtins.readFile keyFile}
      '';
    }
    {
      assertion = lib.hasPrefix "bfd-" (lib.removeSuffix "\n" (builtins.readFile tokenFile));
      message = ''
        Invalid Beszel token format in ${tokenFile}
        Expected format: bfd-a40957f8778-1f39-ae53606608
        Current content: ${builtins.readFile tokenFile}
      '';
    }
  ];
  
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
        
        # Data storage (no socket volume needed for network connection)
        volumes = [
          "${hubDataDir}:/beszel_data"
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
        
        # Volumes for Docker monitoring (no socket volume needed)
        volumes = [
          "/var/run/docker.sock:/var/run/docker.sock:ro"
          "${agentDataDir}:/var/lib/beszel-agent"
        ];
        
        # Agent configuration - Network-based connection
        environment = {
          # Network connection configuration
          PORT = toString agentPort;  # Agent listens on localhost:45876
          HUB_URL = "http://localhost:${toString hubPort}";
          
          # Authentication credentials (read from secure files)
          KEY = lib.removeSuffix "\n" (builtins.readFile keyFile);
          TOKEN = lib.removeSuffix "\n" (builtins.readFile tokenFile);
          
          # System configuration
          TZ = "Asia/Kolkata";
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
  ];
  
  # ============================================================================
  # NETWORKING
  # ============================================================================
  
  networking.firewall = {
    # Allow Beszel hub port access from LAN
    allowedTCPPorts = [ hubPort ];
    
    # Also allow on Tailscale interface
    interfaces."tailscale0".allowedTCPPorts = [ hubPort ];
    
    # Agent port only needs localhost access (automatically allowed)
    # No need to open agentPort (45876) to external networks
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