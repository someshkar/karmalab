# configuration.nix
# ============================================================================
# NIXOS HOMELAB CONFIGURATION - ASUS NUC MEDIA SERVER
# ============================================================================
#
# This configuration provides a complete homelab stack with services for:
#
# MEDIA STACK:
# - Jellyfin: Media streaming with Intel Quick Sync hardware transcoding
# - Radarr/Sonarr/Bazarr/Prowlarr: Media automation (*arr stack)
# - Jellyseerr: User-friendly media request interface
#
# BOOKS:
# - Calibre-Web: Ebook library web interface
# - Shelfmark: Unified book & audiobook downloader
# - Audiobookshelf: Audiobook streaming server
#
# PHOTOS:
# - Immich: Self-hosted Google Photos alternative (Docker)
#
# INFRASTRUCTURE:
# - Deluge: Torrent client with VPN isolation (Surfshark WireGuard)
# - aria2: HTTP/FTP download manager with AriaNg web UI
# - Firefox Browser: Web-accessible browser for authenticated downloads
# - Uptime Kuma: Service monitoring and status pages
# - Time Machine: macOS backup server (Samba with vfs_fruit)
# - Homepage: Service dashboard with system metrics (Glances)
# - Caddy: Reverse proxy for local network access
#
# PRODUCTIVITY:
# - Syncthing: File synchronization (Obsidian vault + Calibre library sync)
# - Forgejo: Self-hosted Git server
# - Vaultwarden: Self-hosted password manager (Bitwarden-compatible)
#
# NETWORKING:
# - Tailscale: Mesh VPN for secure remote access (exit node enabled)
# - Cloudflare Tunnel: External access without port forwarding
#   - git.somesh.dev, immich.somesh.dev, jellyfin.somesh.dev
#   - jellyseer.somesh.dev, sync.somesh.dev, vault.somesh.dev
#   - abs.somesh.dev, books.somesh.dev, shelfmark.somesh.dev
#
# Key Design Principles:
# - Graceful degradation: System boots even if 20TB USB HDD is disconnected
# - VPN isolation: All torrent traffic routed through WireGuard namespace
# - Native services: Using NixOS services instead of Docker where possible
# - ZFS storage: With proper timeouts for slow USB device enumeration
# - Hardware acceleration: Intel Quick Sync (VAAPI) for Jellyfin AND Immich
#
# ============================================================================

{ config, pkgs, inputs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disko-config.nix              # NVMe boot/root disk only
    ./modules/storage.nix           # ZFS pool management with graceful degradation
    ./modules/wireguard-vpn.nix     # VPN namespace for Surfshark (Singapore - torrents)
    # wireguard-vpn-iceland.nix removed - replaced by Gluetun HTTP proxy
    ./modules/gluetun.nix           # Gluetun HTTP proxy for Iceland VPN (Shelfmark/Prowlarr/Bazarr)
    ./modules/immich-go.nix          # immich-go tool for Google Photos Takeout migration
    ./modules/services/deluge.nix   # Native Deluge in VPN namespace
    ./modules/services/immich.nix   # Immich photo management (Docker)
    ./modules/services/uptime-kuma.nix # Service monitoring
    ./modules/services/flaresolverr.nix # Cloudflare bypass for Prowlarr
    ./modules/services/timemachine.nix  # Time Machine backup server (Samba)
    ./modules/services/syncthing.nix    # File synchronization (Obsidian + Calibre)
    ./modules/services/forgejo.nix      # Self-hosted Git server
    ./modules/services/tailscale.nix    # Tailscale VPN (remote access + exit node)
    ./modules/services/caddy.nix        # Reverse proxy for Homepage
    ./modules/services/homepage.nix     # Service dashboard with Glances
    ./modules/services/aria2.nix        # HTTP/FTP download manager
    ./modules/services/cloudflared.nix  # Cloudflare Tunnel for external access
    ./modules/services/vaultwarden.nix  # Password manager
    ./modules/services/audiobookshelf.nix  # Audiobook server
    ./modules/services/calibre-web.nix  # Ebook library web interface
    ./modules/services/shelfmark.nix    # Book & audiobook downloader
    ./modules/services/lazylibrarian.nix  # Ebook & audiobook automation
    ./modules/services/filebrowser.nix  # Web-based file manager
    ./modules/services/firefox-browser.nix  # Web browser for authenticated downloads (Google Takeout)
    ./modules/services/opencloud.nix  # OpenCloud file sync & share (cloud.somesh.dev)
    ./modules/services/mam-dynamic-seedbox.nix  # MAM dynamic seedbox IP updater
  ];

  # ============================================================================
  # BOOT CONFIGURATION
  # ============================================================================

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    
    # Load network drivers
    kernelModules = [ "r8169" "kvm-intel" ];  # Realtek RTL8125 2.5GbE + KVM
    
    # Intel N150 (Alder Lake-N) Quick Sync support
    # Device ID 46d4 needs force_probe; enable_guc=3 for GuC/HuC firmware
    kernelParams = [
      "i915.force_probe=46d4"
      "i915.enable_guc=3"
    ];
  };

  # ============================================================================
  # NETWORKING
  # ============================================================================

  networking = {
    hostName = "karmalab";
    
    # ZFS requires a unique hostId (generate with: head -c4 /dev/urandom | od -A none -t x4)
    hostId = "b291ad23";
    
    # NetworkManager for reliable network management (Ethernet only)
    networkmanager = {
      enable = true;
      # Don't manage WiFi - we only use Ethernet
      unmanaged = [ "wlo1" ];
    };
    
    # Disable WiFi completely - server uses Ethernet only
    wireless.enable = false;
    
    # Ethernet gets DHCP (router assigns static IP 192.168.0.200 via reservation)
    useDHCP = lib.mkDefault false;
    interfaces = {
      enp1s0.useDHCP = lib.mkDefault true;  # Ethernet only
    };
    
    # Firewall configuration
    firewall = {
      enable = true;
      
      # Ports open on all interfaces (local network access)
      allowedTCPPorts = [ 
        22      # SSH
        8096    # Jellyfin
        7878    # Radarr
        8989    # Sonarr
        6767    # Bazarr
        9696    # Prowlarr
        5055    # Jellyseerr
        8112    # Deluge Web UI
        2283    # Immich
        3001    # Uptime Kuma
        5299    # LazyLibrarian
        8085    # FileBrowser
      ];
      
      # Trusted interfaces
      trustedInterfaces = [
        "tailscale0"  # Tailscale VPN
        "lo"          # Localhost
      ];
      
      # Service ports accessible via Tailscale only
      # Note: Additional ports are defined in service modules:
      # - Immich (2283) in modules/services/immich.nix
      # - Uptime Kuma (3001) in modules/services/uptime-kuma.nix
      interfaces."tailscale0".allowedTCPPorts = [
        8096    # Jellyfin
        7878    # Radarr
        8989    # Sonarr
        6767    # Bazarr
        9696    # Prowlarr
        5055    # Jellyseerr
        # Deluge ports configured in modules/services/deluge.nix
      ];
      
      # Allow ping
      allowPing = true;
      logRefusedConnections = true;
      
      # Note: SSH rate limiting removed - was causing connection timeouts
      # Security is already handled by:
      # - SSH key-only authentication (PasswordAuthentication = false)
      # - Tailscale for remote access (not exposed to internet)
      # - Local network only exposure
    };
  };

  # ============================================================================
  # HARDWARE
  # ============================================================================

  hardware = {
    enableRedistributableFirmware = true;
    enableAllFirmware = true;
    
    # Intel microcode updates
    cpu.intel.updateMicrocode = true;
    
    # Intel N150 Quick Sync (VAAPI + QSV) for Jellyfin/Immich transcoding
    # Reference: https://wiki.nixos.org/wiki/Intel_Graphics
    graphics = {
      enable = true;
      extraPackages = with pkgs; [
        # VA-API driver (primary - for hardware decode/encode)
        intel-media-driver      # VAAPI iHD driver for Alder Lake N150
        
        # Quick Sync Video runtime (for QSV encoding)
        vpl-gpu-rt              # oneVPL GPU runtime for 11th gen+
        
        # OpenCL support (for HDR tone mapping in Jellyfin)
        intel-compute-runtime
        
        # Optional: VDPAU compatibility layer
        libva-vdpau-driver
        libvdpau-va-gl
      ];
    };
    
    # Enable intel-gpu-tools for diagnostics
    intel-gpu-tools.enable = true;
  };
  
  # Force iHD driver for VA-API
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD";
  };

  # ============================================================================
  # TIME AND LOCALE
  # ============================================================================

  time.timeZone = "Asia/Kolkata";

  # ============================================================================
  # USERS AND GROUPS
  # ============================================================================

  users.groups.media = {
    gid = 2000;  # Fixed GID for consistent file permissions
  };

  users.users = {
    root.hashedPassword = "$6$7uZoxc.V7nO7O7Bu$ufKbXcj5V32y2kZjrob2CkBgk8C6TfrWXotSaxKTrt2UfTfY59m9AACUISTIDKeY3ZHbfxPFr0s4FsNB/Q1Ni.";
    
    # System user for media services (aria2, etc.)
    media = {
      isSystemUser = true;
      group = "media";
      uid = 2000;  # Match GID for consistency
    };
    
    somesh = {
      isNormalUser = true;
      description = "Somesh";
      extraGroups = [
        "wheel"           # sudo
        "networkmanager"
        "media"           # Media file access
        "docker"          # Docker container management
      ];
      hashedPassword = "$6$7uZoxc.V7nO7O7Bu$ufKbXcj5V32y2kZjrob2CkBgk8C6TfrWXotSaxKTrt2UfTfY59m9AACUISTIDKeY3ZHbfxPFr0s4FsNB/Q1Ni.";
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFeWzy9kzmaFFNzXX/lAhYruiIHbf9Hszo9DrGc+X1on somesh@Someshs-MacBook-Pro.local"
      ];
    };
  };

  # ============================================================================
  # SSH
  # ============================================================================

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;  # SSH key only
      PermitRootLogin = "yes";        # Disable after initial setup
      MaxAuthTries = 3;
      ClientAliveInterval = 300;
      ClientAliveCountMax = 2;
    };
  };

  # ============================================================================
  # JELLYFIN - Media Streaming Server
  # ============================================================================

  services.jellyfin = {
    enable = true;
    openFirewall = false;  # Managed via Tailscale interface
    user = "jellyfin";
    group = "media";
  };

  users.users.jellyfin = {
    extraGroups = [ "render" "video" ];  # Hardware transcoding
  };

  # Jellyfin depends on storage but should start gracefully without it
  systemd.services.jellyfin = {
    after = [ "storage-online.target" ];
    wants = [ "storage-online.target" ];
    # Note: NOT using "requires" - allows Jellyfin to start even if storage unavailable
  };

  # ============================================================================
  # PROWLARR - Indexer Management
  # ============================================================================

  services.prowlarr = {
    enable = true;
    openFirewall = false;
  };

  users.users.prowlarr = {
    isSystemUser = true;
    group = "prowlarr";
    extraGroups = [ "media" ];
  };
  users.groups.prowlarr = {};

  systemd.services.prowlarr = {
    after = [ "network-online.target" "storage-online.target" ];
    wants = [ "network-online.target" "storage-online.target" ];
    # VPN handled by Gluetun HTTP proxy - configure in Prowlarr web UI:
    # Settings -> General -> Proxy -> HTTP(S) -> 192.168.0.200:8888
  };

  # ============================================================================
  # RADARR - Movie Automation
  # ============================================================================

  services.radarr = {
    enable = true;
    openFirewall = false;
    dataDir = "/var/lib/radarr";
    group = "media";
  };

  # Add radarr user to media group for /data/media write access
  users.users.radarr.extraGroups = [ "media" ];

  systemd.services.radarr = {
    after = [ "network-online.target" "storage-online.target" ];
    wants = [ "network-online.target" "storage-online.target" ];
  };

  # ============================================================================
  # SONARR - TV Show Automation
  # ============================================================================

  services.sonarr = {
    enable = true;
    openFirewall = false;
    dataDir = "/var/lib/sonarr";
    group = "media";
  };

  # Add sonarr user to media group for /data/media write access
  users.users.sonarr.extraGroups = [ "media" ];

  systemd.services.sonarr = {
    after = [ "network-online.target" "storage-online.target" ];
    wants = [ "network-online.target" "storage-online.target" ];
  };

  # ============================================================================
  # BAZARR - Subtitle Automation
  # ============================================================================

  services.bazarr = {
    enable = true;
    openFirewall = false;
    group = "media";
  };

  # Add bazarr user to media group for /data/media write access
  users.users.bazarr.extraGroups = [ "media" ];

  systemd.services.bazarr = {
    after = [ "network-online.target" "storage-online.target" ];
    wants = [ "network-online.target" "storage-online.target" ];
    # VPN handled by Gluetun HTTP proxy - configure in Bazarr web UI:
    # Settings -> General -> Proxy -> http://192.168.0.200:8888
  };

  # ============================================================================
  # JELLYSEERR - Media Request Interface
  # ============================================================================

  services.jellyseerr = {
    enable = true;
    openFirewall = false;
    port = 5055;
  };

  users.users.jellyseerr = {
    isSystemUser = true;
    group = "jellyseerr";
    extraGroups = [ "media" ];
  };
  users.groups.jellyseerr = {};

  systemd.services.jellyseerr = {
    after = [ "storage-online.target" ];
    wants = [ "storage-online.target" ];
  };

  # ============================================================================
  # MAM DYNAMIC SEEDBOX IP UPDATER
  # ============================================================================

  services.mam-dynamic-seedbox = {
    enable = true;
    # secretsFile defaults to /etc/nixos/secrets/mam-id
    # interval defaults to "1h"
  };

  # ============================================================================
  # SYSTEM PACKAGES
  # ============================================================================

  environment.systemPackages = with pkgs; [
    # System monitoring
    htop btop iotop ncdu
    
    # Network tools
    curl wget dig mtr netcat
    pciutils usbutils ethtool iproute2
    
    # File management
    tree rsync
    
    # Cloud sync (for Google Photos Takeout migration)
    rclone
    
    # Development
    git vim
    
    # ZFS tools
    zfs-prune-snapshots
    
    # System utilities
    lm_sensors
    tmux              # Terminal multiplexer for long-running tasks
  ];

  # ============================================================================
  # VIRTUALISATION (DOCKER)
  # ============================================================================

  # Set Docker as the backend for OCI containers
  # (Used by Shelfmark, Flaresolverr via virtualisation.oci-containers)
  virtualisation.oci-containers.backend = "docker";

  # ============================================================================
  # NIX CONFIGURATION
  # ============================================================================

  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # ============================================================================
  # STATE VERSION
  # ============================================================================

  system.stateVersion = "23.11";
}
