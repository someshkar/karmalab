# modules/services/audiobookshelf.nix
# ============================================================================
# AUDIOBOOKSHELF - AUDIOBOOK & EBOOK SERVER
# ============================================================================
#
# Audiobookshelf is a self-hosted audiobook and podcast server with a clean
# web interface and native mobile apps. It can also serve ebooks.
#
# Features:
# - Audiobook streaming with playback position sync
# - Podcast management and automatic downloads
# - Ebook reading (EPUB, PDF, etc.)
# - iOS and Android apps with offline playback
# - Multi-user support
# - Collections and series organization
# - Chapter support and bookmarks
#
# Storage:
# - Config/database: /var/lib/audiobookshelf (on NVMe SSD)
# - Audiobooks: /data/media/audiobooks (on ZFS, 500GB quota)
# - Podcasts: /data/media/podcasts (on ZFS)
# 
# Note: Ebooks are now managed by Calibre-Web, not Audiobookshelf
#
# Access:
# - Local: http://192.168.0.200:13378
# - External: https://audiobooks.somesh.dev (via Cloudflare Tunnel)
#
# Mobile Apps:
# - iOS: https://apps.apple.com/app/audiobookshelf/id1582599210
# - Android: https://play.google.com/store/apps/details?id=com.audiobookshelf.app
#
# Post-deployment setup:
# 1. Access http://192.168.0.200:13378
# 2. Create admin account
# 3. Add libraries:
#    - Audiobooks: /audiobooks (type: Audiobook)
#    - Podcasts: /podcasts (type: Podcast)
# 4. Install mobile app and connect to server
#
# Integration with Shelfmark:
# - Shelfmark downloads audiobooks → /data/media/audiobooks
# - Audiobookshelf auto-scans and imports
#
# ============================================================================

{ config, lib, pkgs, ... }:

let
  # Port configuration
  httpPort = 13378;
  
  # Paths
  configDir = "/var/lib/audiobookshelf";
  audiobooksDir = "/data/media/audiobooks";
  podcastsDir = "/data/media/podcasts";
in
{
  # ============================================================================
  # AUDIOBOOKSHELF SERVICE
  # ============================================================================
  
  services.audiobookshelf = {
    enable = true;
    port = httpPort;
    host = "0.0.0.0";
    
    # Use default data directory
    # dataDir = configDir;  # Default is /var/lib/audiobookshelf
  };

  # ============================================================================
  # DIRECTORY SETUP
  # ============================================================================
  
  # Ensure podcast directory exists (audiobooks and ebooks are in ZFS)
  systemd.tmpfiles.rules = [
    "d ${podcastsDir} 0775 audiobookshelf media -"
  ];

  # ============================================================================
  # USER CONFIGURATION
  # ============================================================================
  
  # Add audiobookshelf user to media group for access to media directories
  users.users.audiobookshelf = {
    extraGroups = [ "media" ];
  };

  # ============================================================================
  # FIREWALL CONFIGURATION
  # ============================================================================
  
  networking.firewall = {
    # Allow HTTP port for local access and Cloudflare Tunnel
    allowedTCPPorts = [ httpPort ];
    
    # Also allow on Tailscale interface
    interfaces."tailscale0" = {
      allowedTCPPorts = [ httpPort ];
    };
  };

  # ============================================================================
  # SYSTEMD SERVICE OVERRIDES
  # ============================================================================
  
  systemd.services.audiobookshelf = {
    # Ensure audiobookshelf starts after storage is available
    after = [ "network-online.target" "storage-online.target" ];
    wants = [ "network-online.target" "storage-online.target" ];
  };
}
