# modules/services/lazylibrarian.nix
# ============================================================================
# LAZYLIBRARIAN - EBOOK & AUDIOBOOK AUTOMATION (Docker)
# ============================================================================
#
# LazyLibrarian is an automated ebook and audiobook manager that works like
# Radarr/Sonarr but for books. It monitors authors and series, searches
# multiple sources, and downloads via Deluge or direct download.
#
# Implementation: LinuxServer.io Docker image with Calibre Docker Mod
# - Actively maintained (last update: Jan 24, 2026)
# - Includes Calibre suite for library management
# - Multi-architecture support (amd64, arm64)
#
# Features:
# - Author and series monitoring with release notifications
# - Multi-source search (public sources + private trackers via Prowlarr)
# - Support for ebooks (EPUB, MOBI, PDF) and audiobooks (M4B, MP3)
# - Calibre integration for automatic library management
# - Magazine support
# - Quality preferences and file size limits
#
# Workflow:
# 1. Add author or book to LazyLibrarian wanted list
# 2. LazyLibrarian searches:
#    - Ebooks: Public sources first (Anna's Archive, Libgen), then MAM (freeleech only)
#    - Audiobooks: MAM first (freeleech preferred), then public sources
# 3. Downloads via Deluge (torrents) or direct HTTP download (via proxy)
# 4. Post-processing:
#    - Ebooks → Auto-import to Calibre library → Appears in Calibre-Web
#    - Audiobooks → /data/media/audiobooks → Auto-import to Audiobookshelf
#
# Storage:
# - Config/database: /var/lib/lazylibrarian (on NVMe SSD, ~50MB)
# - Downloads: /data/media/downloads/complete/lazylibrarian (ZFS, 800GB quota)
# - Ebook library: /data/media/ebooks/calibre-library (shared with Calibre-Web)
# - Audiobook library: /data/media/audiobooks (shared with Audiobookshelf)
#
# Network:
# - HTTP proxy: Gluetun (127.0.0.1:8888) for Iceland VPN
# - Routes public sources through VPN for privacy (ISP can't see traffic)
# - Torrents downloaded via Deluge in VPN namespace
#
# Access:
# - Local: http://192.168.0.200:5299
# - Tailscale: http://karmalab:5299
#
# Post-deployment setup (see DEPLOYMENT.md for detailed instructions):
# 1. Access http://192.168.0.200:5299 and set admin password
# 2. Configure Calibre integration (calibredb path: /usr/bin/calibredb)
# 3. Configure Prowlarr integration (add MAM + TorrentLeech with freeleech filter)
# 4. Configure Deluge (host: 127.0.0.1:58846, seed ratio: 2.0, seed time: 168h)
# 5. Set search priorities (ebooks: public first, audiobooks: MAM first)
# 6. Configure quality preferences (EPUB > MOBI, M4B > MP3)
# 7. Verify HTTP proxy working (traffic via Iceland VPN)
#
# ============================================================================

{ config, lib, pkgs, ... }:

let
  # Port configuration
  httpPort = 5299;
  
  # Docker image
  image = "lscr.io/linuxserver/lazylibrarian:latest";
  
  # Paths
  configDir = "/var/lib/lazylibrarian";
  downloadsDir = "/data/media/downloads/complete/lazylibrarian";
  ebooksDir = "/data/media/ebooks/calibre-library";
  audiobooksDir = "/data/media/audiobooks";
in
{
  # ============================================================================
  # DOCKER CONTAINER WITH CALIBRE INTEGRATION
  # ============================================================================
  
  virtualisation.oci-containers.containers.lazylibrarian = {
    image = image;
    autoStart = true;
    
    environment = {
      # User/group configuration
      PUID = "2000";  # media user
      PGID = "2000";  # media group
      TZ = "Asia/Kolkata";
      UMASK = "002";  # rw-rw-r-- permissions
      
      # Calibre Docker Mod (adds Calibre suite to container)
      DOCKER_MODS = "linuxserver/mods:universal-calibre";
      
      # HTTP proxy for public sources (via Gluetun Iceland VPN)
      # Routes Anna's Archive, Libgen, Z-Library through VPN for privacy
      HTTP_PROXY = "http://127.0.0.1:8888";
      HTTPS_PROXY = "http://127.0.0.1:8888";
    };
    
    volumes = [
      "${configDir}:/config"
      "${downloadsDir}:/downloads"
      "${ebooksDir}:/books"
      "${audiobooksDir}:/audiobooks"
    ];
    
    ports = [ "${toString httpPort}:5299" ];
    
    # Use host network to access Gluetun proxy on localhost
    extraOptions = [ "--network=host" ];
  };
  
  # ============================================================================
  # SYSTEMD SERVICE CONFIGURATION
  # ============================================================================
  
  systemd.services.docker-lazylibrarian = {
    description = "LazyLibrarian - Ebook & Audiobook Automation (Docker)";
    
    # Wait for Docker, Gluetun proxy, and storage
    after = [ 
      "docker.service" 
      "docker-gluetun.service"
      "storage-online.target"
    ];
    requires = [ "docker.service" ];
    wants = [ 
      "docker-gluetun.service"  # HTTP proxy dependency
      "storage-online.target"   # ZFS storage dependency
    ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Restart = "always";
      RestartSec = "10s";
    };
  };
  
  # ============================================================================
  # DIRECTORY SETUP
  # ============================================================================
  
  # Ensure config directory exists with correct permissions
  # Other directories (downloads, ebooks, audiobooks) already exist from storage.nix
  systemd.tmpfiles.rules = [
    "d ${configDir} 0755 2000 2000 -"
  ];
  
  # ============================================================================
  # FIREWALL CONFIGURATION
  # ============================================================================
  
  networking.firewall = {
    # Allow HTTP port for local access
    allowedTCPPorts = [ httpPort ];
    
    # Also allow on Tailscale interface
    interfaces."tailscale0" = {
      allowedTCPPorts = [ httpPort ];
    };
  };
}
