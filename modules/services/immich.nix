# modules/services/immich.nix
# ============================================================================
# IMMICH PHOTO MANAGEMENT SERVICE
# ============================================================================
#
# Immich is a self-hosted Google Photos alternative.
# This module manages Immich via Docker Compose (official recommended method).
#
# Architecture:
# - immich-server: Main API server (port 2283)
# - immich-machine-learning: Face/object recognition (CPU)
# - redis: Caching layer
# - postgres: Database with pgvector extension
#
# Storage Layout:
# - /data/immich/photos/      - Photo library (ZFS, 4TB quota)
# - /data/immich/upload/      - Temporary uploads (ZFS, 50GB)
# - /var/lib/immich/postgres/ - Database (NVMe SSD for speed)
# - /var/lib/immich/model-cache/ - ML models (NVMe SSD)
#
# Hardware Acceleration:
# - Intel Quick Sync (VAAPI) for video transcoding
# - Passes through /dev/dri to containers
#
# Access:
# - Local: http://localhost:2283
# - Tailscale: http://nuc-server:2283
# - Public: https://immich.somesh.xyz (via Cloudflare Tunnel, Phase 4)
#
# ============================================================================

{ config, lib, pkgs, ... }:

let
  # Immich version - pinned for stability
  immichVersion = "v2.4.1";
  
  # Paths
  composeDir = "/var/lib/immich";
  photosDir = "/data/immich/photos";
  uploadDir = "/data/immich/upload";
  postgresDir = "/var/lib/immich/postgres";
  modelCacheDir = "/var/lib/immich/model-cache";
  
  # Port
  immichPort = 2283;
in
{
  # ============================================================================
  # DOCKER REQUIREMENT
  # ============================================================================
  
  virtualisation.docker = {
    enable = true;
    
    # Automatic cleanup of unused images/containers
    autoPrune = {
      enable = true;
      dates = "weekly";
      flags = [ "--all" ];
    };
    
    # Start Docker on boot
    enableOnBoot = true;
  };
  
  # ============================================================================
  # IMMICH DOCKER COMPOSE SERVICE
  # ============================================================================
  
  systemd.services.immich = {
    description = "Immich Photo Management (Docker Compose)";
    
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
      # Ensure directories exist
      mkdir -p ${composeDir}
      mkdir -p ${postgresDir}
      mkdir -p ${modelCacheDir}
      
      # Check if .env exists
      if [ ! -f ${composeDir}/.env ]; then
        echo "ERROR: ${composeDir}/.env not found!"
        echo "Copy /etc/nixos/docker/immich/.env.example to ${composeDir}/.env and configure it"
        exit 1
      fi
      
      # Copy docker-compose.yml if it doesn't exist or is outdated
      if [ ! -f ${composeDir}/docker-compose.yml ]; then
        cp /etc/nixos/docker/immich/docker-compose.yml ${composeDir}/
      fi
    '';
  };
  
  # ============================================================================
  # IMMICH HEALTH CHECK
  # ============================================================================
  
  systemd.services.immich-health = {
    description = "Immich Health Check";
    after = [ "immich.service" ];
    
    serviceConfig = {
      Type = "oneshot";
    };
    
    script = ''
      # Wait for Immich to be ready
      for i in $(seq 1 30); do
        if ${pkgs.curl}/bin/curl -sf http://localhost:${toString immichPort}/api/server/ping > /dev/null 2>&1; then
          echo "Immich is healthy"
          exit 0
        fi
        echo "Waiting for Immich... ($i/30)"
        sleep 2
      done
      echo "Immich health check failed"
      exit 1
    '';
  };
  
  # Run health check periodically
  systemd.timers.immich-health = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "15min";
      Unit = "immich-health.service";
    };
  };
  
  # ============================================================================
  # FIREWALL
  # ============================================================================
  
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 
    immichPort  # Immich web UI
  ];
  
  # ============================================================================
  # PACKAGES
  # ============================================================================
  
  environment.systemPackages = with pkgs; [
    docker-compose
  ];
}
