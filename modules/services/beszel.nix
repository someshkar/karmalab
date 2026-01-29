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
# Security: Credentials stored in /etc/nixos/secrets/ (outside git repository)
# - /etc/nixos/secrets/beszel-key: SSH public key for agent authentication
# - /etc/nixos/secrets/beszel-token: Token for hub-agent communication
#
# Setup:
# 1. Create credentials files:
#    echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHXaSnmtNUWd4ATzK5b6agpX+G9a4GcDyOA0Clj8mQ+m' | sudo tee /etc/nixos/secrets/beszel-key
#    echo 'bfd-a40957f8778-1f39-ae53606608' | sudo tee /etc/nixos/secrets/beszel-token
# 2. Deploy with nixos-rebuild switch
# 3. Add system in dashboard with Host/IP: localhost, Port: 45876
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
  
  # Credential files (following existing pattern: /etc/nixos/secrets/)
  keyFile = "/etc/nixos/secrets/beszel-key";
  tokenFile = "/etc/nixos/secrets/beszel-token";
  
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
        
        # Volumes for Docker monitoring + ZFS filesystem access
        volumes = [
          "/var/run/docker.sock:/var/run/docker.sock:ro"
          "${agentDataDir}:/var/lib/beszel-agent"
          # Host filesystem access for ZFS pool and dataset monitoring
          "/:/host:ro,rslave"
        ];
        
        # Load secrets from environment file (created by systemd prestart)
        environmentFiles = [
          "/tmp/beszel-agent.env"
        ];
        
        # Agent configuration - Network-based connection + ZFS monitoring
        environment = {
          # Network connection configuration
          PORT = toString agentPort;  # Agent listens on localhost:45876
          HUB_URL = "http://localhost:${toString hubPort}";
          
          # System configuration
          TZ = "Asia/Kolkata";
          
          # Host filesystem monitoring configuration
          FILESYSTEM_ROOT = "/host";
          
          # Filter out system/virtual filesystems to reduce dashboard noise
          DISK_EXCLUDE = "/host/dev/*,/host/proc/*,/host/sys/*,/host/run/*,/host/var/lib/docker/*,/host/boot/*,/host/tmp/*,/host/var/tmp/*,/host/nix/store*";
          
          # Authentication credentials loaded from environmentFiles
        };
      };
    };
  };
  
  # ============================================================================
  # SYSTEMD SERVICE CONFIGURATION (Environment File Secret Injection)
  # ============================================================================
  
  # Override the systemd service to inject secrets via environment file
  systemd.services.docker-beszel-agent = {
    # Add service dependencies
    after = [ "docker.service" "docker-beszel-hub.service" ];
    wants = [ "docker-beszel-hub.service" ];
    
    serviceConfig = {
      # Pre-start script to create environment file with secrets
      ExecStartPre = let
        preStartScript = pkgs.writeShellScript "beszel-agent-prestart" ''
          # Check if secret files exist
          if [ ! -f "${keyFile}" ]; then
            echo "ERROR: Beszel key file not found: ${keyFile}"
            echo "Run: echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHXaSnmtNUWd4ATzK5b6agpX+G9a4GcDyOA0Clj8mQ+m' | sudo tee ${keyFile}"
            exit 1
          fi
          
          if [ ! -f "${tokenFile}" ]; then
            echo "ERROR: Beszel token file not found: ${tokenFile}"
            echo "Run: echo 'bfd-a40957f8778-1f39-ae53606608' | sudo tee ${tokenFile}"
            exit 1
          fi
          
          # Read secrets and create environment file
          echo "KEY=$(cat ${keyFile})" > /tmp/beszel-agent.env
          echo "TOKEN=$(cat ${tokenFile})" >> /tmp/beszel-agent.env
          
          # Secure the environment file
          chmod 600 /tmp/beszel-agent.env
        '';
      in "+${preStartScript}";  # "+" runs as root despite User= setting
    };
  };
  
  # ============================================================================
  # STORAGE SETUP
  # ============================================================================
  
  # Create data directories with correct permissions
  systemd.tmpfiles.rules = [
    "d ${hubDataDir} 0755 root root -"
    "d ${agentDataDir} 0755 root root -"
    # Ensure secrets directory exists (following existing pattern)
    "d /etc/nixos/secrets 0700 root root -"
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
}