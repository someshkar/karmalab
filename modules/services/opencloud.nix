# modules/services/opencloud.nix
# ============================================================================
# OPENCLOUD - SELF-HOSTED FILE SYNC & SHARE
# ============================================================================
#
# OpenCloud is the community fork of ownCloud Infinite Scale (oCIS).
# It's a modern, microservices-based file sync and share platform written in Go.
#
# Features:
# - File sync across desktop/mobile (ownCloud/Nextcloud clients compatible)
# - Web-based file manager
# - File/folder sharing with links
# - Spaces (project folders)
# - WebDAV support
#
# Architecture:
# - Single container deployment (no database required - uses embedded storage)
# - Docker Compose managed (like Immich)
#
# Storage Layout:
# - /data/opencloud/           - User files (ZFS HDD, 1TB quota)
# - /var/lib/opencloud/config/ - OpenCloud configuration (NVMe SSD)
# - /var/lib/opencloud/data/   - Internal data/metadata (NVMe SSD)
#
# Access:
# - Local: http://192.168.0.200:9200
# - External: https://cloud.somesh.dev (via Cloudflare Tunnel)
#
# Post-deployment setup:
# 1. Copy .env.example to /var/lib/opencloud/.env
# 2. Set ADMIN_PASSWORD in .env
# 3. Run nixos-rebuild switch
# 4. Add cloud.somesh.dev → http://localhost:9200 in Cloudflare dashboard
# 5. Access https://cloud.somesh.dev, login as 'admin'
#
# Desktop/Mobile Sync:
# - Use ownCloud desktop client or Nextcloud client
# - Server URL: https://cloud.somesh.dev
#
# ============================================================================

{ config, lib, pkgs, ... }:

let
  # Paths
  composeDir = "/var/lib/opencloud";
  configDir = "/var/lib/opencloud/config";
  dataDir = "/var/lib/opencloud/data";
  userFilesDir = "/data/opencloud";
  
  # Port
  opencloudPort = 9200;
in
{
  # ============================================================================
  # OPENCLOUD DOCKER COMPOSE SERVICE
  # ============================================================================
  
  systemd.services.opencloud = {
    description = "OpenCloud File Sync & Share (Docker Compose)";
    
    # Dependencies
    after = [ 
      "docker.service" 
      "network-online.target"
      "storage-online.target"
    ];
    wants = [ 
      "network-online.target"
      "storage-online.target"
    ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    
    # Service configuration
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      WorkingDirectory = composeDir;
      
      # Start the stack
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans";
      
      # Stop the stack gracefully
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
      
      # Longer timeout for pulling images on first start
      TimeoutStartSec = "600";
    };
    
    # Ensure compose file and env exist
    preStart = ''
      # Ensure directories exist with correct ownership
      mkdir -p ${composeDir}
      mkdir -p ${configDir}
      mkdir -p ${dataDir}
      
      # Set ownership for OpenCloud (runs as UID 1000)
      chown -R 1000:1000 ${configDir}
      chown -R 1000:1000 ${dataDir}
      
      # Check if .env exists
      if [ ! -f ${composeDir}/.env ]; then
        echo "ERROR: ${composeDir}/.env not found!"
        echo "Copy /etc/nixos/docker/opencloud/.env.example to ${composeDir}/.env and configure it"
        exit 1
      fi
      
      # Copy docker-compose.yml if it doesn't exist or is outdated
      if [ ! -f ${composeDir}/docker-compose.yml ]; then
        cp /etc/nixos/docker/opencloud/docker-compose.yml ${composeDir}/
      fi
    '';
  };
  
  # ============================================================================
  # OPENCLOUD HEALTH CHECK
  # ============================================================================
  
  systemd.services.opencloud-health = {
    description = "OpenCloud Health Check";
    after = [ "opencloud.service" ];
    
    serviceConfig = {
      Type = "oneshot";
    };
    
    script = ''
      # Wait for OpenCloud to be ready
      for i in $(seq 1 30); do
        if ${pkgs.curl}/bin/curl -sf http://localhost:${toString opencloudPort}/healthz > /dev/null 2>&1; then
          echo "OpenCloud is healthy"
          exit 0
        fi
        echo "Waiting for OpenCloud... ($i/30)"
        sleep 2
      done
      echo "OpenCloud health check failed"
      exit 1
    '';
  };
  
  # Run health check periodically
  systemd.timers.opencloud-health = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "15min";
      Unit = "opencloud-health.service";
    };
  };
  
  # ============================================================================
  # DIRECTORY SETUP
  # ============================================================================
  
  systemd.tmpfiles.rules = [
    # OpenCloud directories on NVMe SSD
    # UID/GID 1000 is the default user inside the OpenCloud container
    "d /var/lib/opencloud 0755 root root -"
    "d /var/lib/opencloud/config 0750 1000 1000 -"
    "d /var/lib/opencloud/data 0750 1000 1000 -"
  ];
  
  # ============================================================================
  # FIREWALL CONFIGURATION
  # ============================================================================
  
  networking.firewall = {
    # Allow OpenCloud port for local network and Cloudflare Tunnel
    allowedTCPPorts = [ opencloudPort ];
    
    # Also allow on Tailscale interface
    interfaces."tailscale0".allowedTCPPorts = [ 
      opencloudPort
    ];
  };
  
  # ============================================================================
  # PACKAGES
  # ============================================================================
  
  environment.systemPackages = with pkgs; [
    docker-compose
  ];
}
