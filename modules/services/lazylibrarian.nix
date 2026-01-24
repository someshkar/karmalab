# modules/services/lazylibrarian.nix
# ============================================================================
# LAZYLIBRARIAN - EBOOK & AUDIOBOOK AUTOMATION
# ============================================================================
#
# LazyLibrarian is an automated ebook and audiobook manager that works like
# Radarr/Sonarr but for books. It monitors authors and series, searches
# multiple sources, and downloads via Deluge or direct download.
#
# Features:
# - Author and series monitoring with release notifications
# - Multi-source search (public sources + private trackers via Prowlarr)
# - Support for ebooks (EPUB, MOBI, PDF) and audiobooks (M4B, MP3)
# - Calibre integration for library management
# - Magazine support
# - Quality preferences and file size limits
#
# Workflow:
# 1. Add author or book to LazyLibrarian wanted list
# 2. LazyLibrarian searches:
#    - Ebooks: Public sources first (Anna's Archive, Libgen), then MAM (freeleech only)
#    - Audiobooks: MAM first (freeleech preferred), then public sources
# 3. Downloads via Deluge (torrents) or direct HTTP download
# 4. Post-processing:
#    - Ebooks → /data/media/ebooks/calibre-library → Auto-import to Calibre-Web
#    - Audiobooks → /data/media/audiobooks → Auto-import to Audiobookshelf
#
# Storage:
# - Config/database: /var/lib/lazylibrarian (on ZFS, 5GB quota)
# - Ebook library: /data/media/ebooks/calibre-library (shared with Calibre-Web)
# - Audiobook library: /data/media/audiobooks (shared with Audiobookshelf)
# - Downloads: /data/media/downloads/complete (shared with Deluge)
#
# Network:
# - HTTP proxy: Gluetun (192.168.0.200:8888) for Iceland VPN
# - Used for accessing geo-blocked public sources
#
# Access:
# - Local: http://192.168.0.200:5299
# - Tailscale: http://karmalab:5299
#
# Post-deployment setup:
# 1. Access http://192.168.0.200:5299
# 2. Complete initial setup wizard (set admin password)
# 3. Configure download client (Deluge):
#    - Settings → Download Client → Deluge
#    - Host: 192.168.0.200, Port: 58846
#    - Category: lazylibrarian
# 4. Configure Prowlarr integration:
#    - Settings → Indexers → Prowlarr
#    - URL: http://192.168.0.200:9696
#    - API Key: (from Prowlarr settings)
# 5. Configure Calibre integration:
#    - Settings → Calibre → Path: /data/media/ebooks/calibre-library
#    - Enable auto-import
# 6. Set search priorities:
#    - Ebooks: Public sources first, MAM last (freeleech only)
#    - Audiobooks: MAM first (freeleech preferred)
# 7. Configure quality preferences:
#    - Ebook formats: EPUB > MOBI > AZW3 > PDF
#    - Audiobook formats: M4B > MP3
#    - Max sizes: 50MB (ebooks), 500MB (audiobooks)
#
# ============================================================================

{ config, lib, pkgs, ... }:

let
  # Port configuration
  httpPort = 5299;
  
  # Paths
  dataDir = "/var/lib/lazylibrarian";
  ebooksDir = "/data/media/ebooks/calibre-library";
  audiobooksDir = "/data/media/audiobooks";
  downloadsDir = "/data/media/downloads/complete";
in
{
  # ============================================================================
  # LAZYLIBRARIAN SERVICE
  # ============================================================================
  
  # NixOS doesn't have a native LazyLibrarian module, so we create a systemd service
  systemd.services.lazylibrarian = {
    description = "LazyLibrarian - Ebook & Audiobook Automation";
    after = [ "network-online.target" "storage-online.target" ];
    wants = [ "network-online.target" "storage-online.target" ];
    wantedBy = [ "multi-user.target" ];
    
    environment = {
      # HTTP proxy for public sources (via Gluetun Iceland VPN)
      HTTP_PROXY = "http://127.0.0.1:8888";
      HTTPS_PROXY = "http://127.0.0.1:8888";
    };
    
    serviceConfig = {
      Type = "simple";
      User = "lazylibrarian";
      Group = "media";
      
      # LazyLibrarian command
      ExecStart = ''
        ${pkgs.lazylibrarian}/bin/LazyLibrarian \
          --datadir ${dataDir} \
          --config ${dataDir}/config.ini \
          --port ${toString httpPort} \
          --nolaunch
      '';
      
      Restart = "on-failure";
      RestartSec = "10s";
      
      # Security hardening
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ dataDir ebooksDir audiobooksDir downloadsDir ];
    };
  };
  
  # ============================================================================
  # USER CONFIGURATION
  # ============================================================================
  
  users.users.lazylibrarian = {
    isSystemUser = true;
    group = "media";  # Member of media group for write access to media directories
    home = dataDir;
  };
  
  # ============================================================================
  # DIRECTORY SETUP
  # ============================================================================
  
  # Ensure data directory exists with correct permissions
  # Other directories (ebooks, audiobooks, downloads) already exist from storage.nix
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0755 lazylibrarian media -"
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
  
  # ============================================================================
  # SYSTEMD SERVICE OVERRIDES
  # ============================================================================
  
  # Ensure LazyLibrarian starts after storage is available
  # (already configured in service definition above)
}
