# modules/storage.nix
# ============================================================================
# ZFS STORAGE CONFIGURATION WITH GRACEFUL DEGRADATION
# ============================================================================
#
# This module manages the 20TB USB HDD ZFS pool separately from disko.
# Key features:
# - Extended timeouts for USB device enumeration (USB HDDs can take 10-30s)
# - Graceful degradation: system boots even if HDD is disconnected
# - All mounts use nofail to prevent boot failures
# - Services use "wants" instead of "requires" for soft dependencies
#
# Storage Architecture:
# ┌─────────────────────────────────────────────────────────────────────┐
# │ NVMe SSD (500GB) - Fast storage for databases and caches           │
# │   /var/lib/immich/postgres/    - Immich database                   │
# │   /var/lib/immich/model-cache/ - ML models (~20GB)                 │
# │   /var/lib/uptime-kuma/        - Monitoring config                 │
# │   /var/lib/nextcloud/          - Nextcloud database/config         │
# └─────────────────────────────────────────────────────────────────────┘
# ┌─────────────────────────────────────────────────────────────────────┐
# │ USB HDD ZFS Pool (20TB) - Large storage for media, photos, backups │
# │                                                                     │
# │   MEDIA (6.5TB total):                                             │
# │     storagepool/media/movies/       - Movies (2TB quota)           │
# │     storagepool/media/tv/           - TV Shows (2TB quota)         │
# │     storagepool/media/downloads/    - Temp downloads (500GB)       │
# │     storagepool/media/ebooks/       - Ebooks (100GB quota)         │
# │     storagepool/media/audiobooks/   - Audiobooks (1TB quota)       │
# │                                                                     │
# │   IMMICH (2TB total):                                              │
# │     storagepool/immich/photos/      - Photo library (2TB quota)    │
# │     storagepool/immich/upload/      - Temp uploads (50GB)          │
# │                                                                     │
# │   CLOUD & BACKUP (2.5TB total):                                    │
# │     storagepool/nextcloud/          - Nextcloud files (1TB quota)  │
# │     storagepool/timemachine/        - Mac backups (1.5TB quota)    │
# │                                                                     │
# │   SERVICES (~150GB):                                               │
# │     storagepool/services/           - Service configs              │
# │                                                                     │
# │   UNALLOCATED: ~7.75TB for future expansion                        │
# └─────────────────────────────────────────────────────────────────────┘
#
# ============================================================================

{ config, lib, pkgs, ... }:

let
  # Configuration for the storage pool
  poolName = "storagepool";
  
  # USB device path (used for documentation, actual import uses pool name)
  usbDeviceId = "usb-Seagate_Expansion_HDD_00000000NT17VP0M-0:0";
  
  # Timeout settings for slow USB enumeration
  deviceTimeout = "120";  # 2 minutes for USB device to appear
  mountTimeout = "60";    # 1 minute for mount operation
  
  # Common mount options for ZFS datasets
  # Note: Do NOT use "zfsutil" here - datasets have mountpoint=legacy
  # which requires standard mount, not ZFS's internal mount mechanism
  zfsMountOpts = [
    "nofail"                                    # Boot continues if mount fails
    "x-systemd.device-timeout=${deviceTimeout}" # Wait for USB device
    "x-systemd.mount-timeout=${mountTimeout}"   # Wait for mount
  ];
in
{
  # ============================================================================
  # ZFS KERNEL AND POOL CONFIGURATION
  # ============================================================================
  
  boot = {
    # Enable ZFS support
    supportedFilesystems = [ "zfs" ];
    
    # Use kernel 6.12 for Intel N150 (Alder Lake-N) GPU support
    # The N150 iGPU needs recent i915 driver improvements
    # Note: linuxPackages_latest (6.18) breaks ZFS - use 6.12 which has full ZFS support
    kernelPackages = pkgs.linuxPackages_6_12;
    
    # Import the USB ZFS pool on boot
    # This is the key difference from disko - extraPools handles
    # missing pools gracefully and supports extended timeouts
    zfs = {
      extraPools = [ poolName ];
      
      # Don't force import - let ZFS handle this gracefully
      forceImportRoot = false;
      forceImportAll = false;
      
      # Use disk-by-id for reliable device identification
      devNodes = "/dev/disk/by-id";
    };
  };
  
  # ============================================================================
  # ZFS POOL IMPORT SERVICE OVERRIDE
  # ============================================================================
  # Extend the timeout for the ZFS import service to handle slow USB enumeration
  
  systemd.services."zfs-import-${poolName}" = {
    # Extended timeout for USB device enumeration
    serviceConfig = {
      TimeoutStartSec = "${deviceTimeout}";
    };
    
    # Don't fail boot if pool import fails
    unitConfig = {
      # Allow boot to continue even if this service fails
      FailureAction = "none";
    };
  };
  
  # ============================================================================
  # ZFS DATASET MOUNTS (USB HDD)
  # ============================================================================
  # All mounts use nofail and extended timeouts for resilience
  
  fileSystems = {
    # --- Root Data Mount ---
    "/data" = {
      device = "${poolName}/data";
      fsType = "zfs";
      options = zfsMountOpts;
    };
    
    # --- Immich Photo Library (on HDD for large storage) ---
    "/data/immich/photos" = {
      device = "${poolName}/immich/photos";
      fsType = "zfs";
      options = zfsMountOpts;
    };
    
    "/data/immich/upload" = {
      device = "${poolName}/immich/upload";
      fsType = "zfs";
      options = zfsMountOpts;
    };
    
    # --- Service Configuration Mounts ---
    # These are mounted to standard NixOS service directories
    
    "/var/lib/jellyfin" = {
      device = "${poolName}/services/jellyfin/config";
      fsType = "zfs";
      options = zfsMountOpts;
    };
    
    "/var/cache/jellyfin" = {
      device = "${poolName}/services/jellyfin/cache";
      fsType = "zfs";
      options = zfsMountOpts;
    };
    
    "/var/lib/deluge" = {
      device = "${poolName}/services/deluge/config";
      fsType = "zfs";
      options = zfsMountOpts;
    };
    
    "/var/lib/radarr" = {
      device = "${poolName}/services/radarr";
      fsType = "zfs";
      options = zfsMountOpts;
    };
    
    "/var/lib/sonarr" = {
      device = "${poolName}/services/sonarr";
      fsType = "zfs";
      options = zfsMountOpts;
    };
    
    "/var/lib/bazarr" = {
      device = "${poolName}/services/bazarr";
      fsType = "zfs";
      options = zfsMountOpts;
    };
    
    # Note: jellyseerr and prowlarr use NixOS defaults on NVMe SSD
    # They use DynamicUser=true which conflicts with ZFS mounts
    # Their data is small (config + SQLite) so NVMe is fine
    
    # Note: uptime-kuma uses NixOS default at /var/lib/uptime-kuma/
    # No ZFS mount needed - NixOS 25.11 manages this automatically
  };
  
  # ============================================================================
  # ZFS MAINTENANCE
  # ============================================================================
  
  services.zfs = {
    # Weekly scrub for data integrity
    autoScrub = {
      enable = true;
      interval = "weekly";
      pools = [ poolName ];
    };
    
    # Automatic snapshots (recommended for data safety)
    autoSnapshot = {
      enable = true;
      frequent = 4;   # Keep 4 15-minute snapshots
      hourly = 24;    # Keep 24 hourly snapshots
      daily = 7;      # Keep 7 daily snapshots
      weekly = 4;     # Keep 4 weekly snapshots
      monthly = 12;   # Keep 12 monthly snapshots
    };
  };
  
  # ============================================================================
  # ZFS DATASET CREATION SERVICE
  # ============================================================================
  # Creates all required ZFS datasets on boot if they don't exist.
  # This is idempotent - safe to run multiple times.
  
  systemd.services.create-zfs-datasets = {
    description = "Create ZFS datasets for homelab services";
    
    # Use "wants" not "requires" - allow graceful degradation
    wants = [ "zfs-import-${poolName}.service" "zfs-mount.service" ];
    after = [ "zfs-import-${poolName}.service" "zfs-mount.service" ];
    wantedBy = [ "multi-user.target" ];
    
    # Only run if the pool is actually imported
    unitConfig = {
      ConditionPathExists = "/data";
    };
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    
    script = ''
      set -e
      POOL="${poolName}"
      
      # Helper function to create dataset if it doesn't exist
      create_dataset() {
        local dataset="$1"
        shift
        if ! ${pkgs.zfs}/bin/zfs list "$dataset" &>/dev/null; then
          echo "Creating dataset: $dataset"
          ${pkgs.zfs}/bin/zfs create "$@" "$dataset"
        else
          echo "Dataset already exists: $dataset"
        fi
      }
      
      # Helper function to set ZFS properties
      set_property() {
        local dataset="$1"
        local property="$2"
        local value="$3"
        echo "Setting $property=$value on $dataset"
        ${pkgs.zfs}/bin/zfs set "$property=$value" "$dataset" || true
      }
      
      echo "=========================================="
      echo "Starting ZFS dataset creation..."
      echo "=========================================="
      
      # ===== ROOT DATA DATASET =====
      create_dataset "$POOL/data" -o mountpoint=legacy
      
      # ===== IMMICH DATASETS =====
      echo "--- Creating Immich datasets ---"
      create_dataset "$POOL/immich" -o mountpoint=none -o compression=lz4
      
      # Photo library (2TB quota, 1M recordsize for large files)
      create_dataset "$POOL/immich/photos" -o mountpoint=legacy
      set_property "$POOL/immich/photos" "quota" "2T"
      set_property "$POOL/immich/photos" "recordsize" "1M"
      set_property "$POOL/immich/photos" "atime" "off"
      
      # Upload buffer (50GB quota)
      create_dataset "$POOL/immich/upload" -o mountpoint=legacy
      set_property "$POOL/immich/upload" "quota" "50G"
      set_property "$POOL/immich/upload" "com.sun:auto-snapshot" "false"
      
      # ===== SET IMMICH DIRECTORY PERMISSIONS =====
      # UID/GID 999 is the postgres/immich user inside containers
      echo "--- Setting Immich directory permissions ---"
      chown -R 999:999 /data/immich/photos
      chown -R 999:999 /data/immich/upload
      chmod -R 755 /data/immich/photos
      chmod -R 755 /data/immich/upload
      
      # ===== MEDIA DATASETS =====
      echo "--- Creating Media datasets ---"
      create_dataset "$POOL/media" -o mountpoint=/data/media -o compression=lz4 -o atime=off
      
      # Movies (2TB quota, 1M recordsize for large files)
      create_dataset "$POOL/media/movies"
      set_property "$POOL/media/movies" "quota" "2T"
      set_property "$POOL/media/movies" "recordsize" "1M"
      
      # TV Shows (2TB quota, 1M recordsize for large files)
      create_dataset "$POOL/media/tv"
      set_property "$POOL/media/tv" "quota" "2T"
      set_property "$POOL/media/tv" "recordsize" "1M"
      
      # Downloads (500GB total)
      create_dataset "$POOL/media/downloads"
      set_property "$POOL/media/downloads" "quota" "500G"
      
      create_dataset "$POOL/media/downloads/complete"
      set_property "$POOL/media/downloads/complete" "quota" "400G"
      
      create_dataset "$POOL/media/downloads/incomplete"
      set_property "$POOL/media/downloads/incomplete" "quota" "200G"
      set_property "$POOL/media/downloads/incomplete" "com.sun:auto-snapshot" "false"
      
      # Ebooks (100GB quota - text files are tiny)
      create_dataset "$POOL/media/ebooks"
      set_property "$POOL/media/ebooks" "quota" "100G"
      set_property "$POOL/media/ebooks" "recordsize" "128K"
      
      # Audiobooks (1TB quota - ~1000-2000 audiobooks)
      create_dataset "$POOL/media/audiobooks"
      set_property "$POOL/media/audiobooks" "quota" "1T"
      set_property "$POOL/media/audiobooks" "recordsize" "1M"
      
      # ===== SET MEDIA DIRECTORY PERMISSIONS =====
      # Allow media group (radarr, sonarr, bazarr, deluge, jellyfin) to write
      echo "--- Setting media directory permissions ---"
      chown -R root:media /data/media
      chmod -R 775 /data/media
      
      # Ensure new files/dirs inherit group ownership
      chmod g+s /data/media /data/media/movies /data/media/tv /data/media/downloads /data/media/downloads/complete /data/media/downloads/incomplete /data/media/ebooks /data/media/audiobooks
      
      # ===== NEXTCLOUD DATASET =====
      echo "--- Creating Nextcloud dataset ---"
      create_dataset "$POOL/nextcloud" -o mountpoint=/data/nextcloud -o compression=lz4 -o atime=off
      set_property "$POOL/nextcloud" "quota" "1T"
      set_property "$POOL/nextcloud" "recordsize" "128K"
      
      # Set Nextcloud directory permissions (will be owned by nextcloud user)
      chown -R root:root /data/nextcloud
      chmod -R 750 /data/nextcloud
      
      # ===== TIME MACHINE DATASET =====
      echo "--- Creating Time Machine dataset ---"
      create_dataset "$POOL/timemachine" -o mountpoint=/data/timemachine -o compression=lz4 -o atime=off
      set_property "$POOL/timemachine" "quota" "1536G"  # 1.5TB (3x 512GB Mac drive)
      set_property "$POOL/timemachine" "recordsize" "1M"
      # Disable snapshots for Time Machine - it manages its own versioning
      set_property "$POOL/timemachine" "com.sun:auto-snapshot" "false"
      
      # Set Time Machine directory permissions
      chown -R root:root /data/timemachine
      chmod -R 770 /data/timemachine
      
      # ===== SERVICE CONFIG DATASETS =====
      echo "--- Creating Service datasets ---"
      create_dataset "$POOL/services" -o mountpoint=/var/lib/media-services -o compression=lz4 -o atime=off
      
      # Jellyfin
      create_dataset "$POOL/services/jellyfin"
      create_dataset "$POOL/services/jellyfin/config" -o mountpoint=legacy
      set_property "$POOL/services/jellyfin/config" "quota" "10G"
      set_property "$POOL/services/jellyfin/config" "recordsize" "8K"
      
      create_dataset "$POOL/services/jellyfin/cache" -o mountpoint=legacy
      set_property "$POOL/services/jellyfin/cache" "quota" "100G"
      set_property "$POOL/services/jellyfin/cache" "sync" "disabled"
      set_property "$POOL/services/jellyfin/cache" "com.sun:auto-snapshot" "false"
      
      # Deluge
      create_dataset "$POOL/services/deluge"
      create_dataset "$POOL/services/deluge/config" -o mountpoint=legacy
      set_property "$POOL/services/deluge/config" "quota" "5G"
      set_property "$POOL/services/deluge/config" "recordsize" "8K"
      
      # Radarr
      create_dataset "$POOL/services/radarr" -o mountpoint=legacy
      set_property "$POOL/services/radarr" "quota" "5G"
      set_property "$POOL/services/radarr" "recordsize" "8K"
      
      # Sonarr
      create_dataset "$POOL/services/sonarr" -o mountpoint=legacy
      set_property "$POOL/services/sonarr" "quota" "5G"
      set_property "$POOL/services/sonarr" "recordsize" "8K"
      
      # Bazarr
      create_dataset "$POOL/services/bazarr" -o mountpoint=legacy
      set_property "$POOL/services/bazarr" "quota" "5G"
      set_property "$POOL/services/bazarr" "recordsize" "8K"
      
      # Prowlarr
      create_dataset "$POOL/services/prowlarr" -o mountpoint=legacy
      set_property "$POOL/services/prowlarr" "quota" "5G"
      set_property "$POOL/services/prowlarr" "recordsize" "8K"
      
      # Jellyseerr
      create_dataset "$POOL/services/jellyseerr" -o mountpoint=legacy
      set_property "$POOL/services/jellyseerr" "quota" "5G"
      set_property "$POOL/services/jellyseerr" "recordsize" "8K"
      
      # Uptime Kuma
      create_dataset "$POOL/services/uptime-kuma" -o mountpoint=legacy
      set_property "$POOL/services/uptime-kuma" "quota" "1G"
      set_property "$POOL/services/uptime-kuma" "recordsize" "8K"
      
      echo "=========================================="
      echo "ZFS dataset creation completed!"
      echo "Run 'zfs list -o name,used,avail,quota,mountpoint' to verify"
      echo "=========================================="
    '';
  };
  
  # ============================================================================
  # NVMe SSD DIRECTORIES (Fast Storage)
  # ============================================================================
  # These directories are on the NVMe SSD for fast access
  # They are NOT ZFS - just regular directories on the root filesystem
  
  systemd.tmpfiles.rules = [
    # Immich database and model cache on NVMe for performance
    # UID/GID 999 is the postgres user inside the Immich containers
    "d /var/lib/immich 0755 root root -"
    "d /var/lib/immich/postgres 0700 999 999 -"
    "d /var/lib/immich/model-cache 0755 999 999 -"
  ];
  
  # ============================================================================
  # STORAGE READINESS TARGET
  # ============================================================================
  # Custom target that services can depend on.
  # This target is reached when storage is available OR after timeout.
  
  systemd.targets.storage-online = {
    description = "Storage Pool Available";
    wants = [ "zfs-mount.service" ];
    after = [ "zfs-mount.service" ];
  };
}
