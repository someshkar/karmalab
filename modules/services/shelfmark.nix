# modules/services/shelfmark.nix
# ============================================================================
# SHELFMARK - UNIFIED BOOK & AUDIOBOOK DOWNLOADER
# ============================================================================
#
# Shelfmark is a unified web interface for searching and downloading books
# and audiobooks from multiple sources - all in one place. Works with popular
# web sources (Anna's Archive, Libgen, Z-Library), no configuration required.
#
# Features:
# - One-stop interface for searching and downloading from multiple sources
# - Full audiobook support with dedicated processing
# - Real-time download progress with unified queue
# - Built-in Cloudflare bypass for reliable access
# - Two search modes:
#   * Direct: Search web sources directly (default, no setup)
#   * Universal: Search metadata providers (Hardcover, Open Library) for
#                richer discovery with multi-source downloads
#
# Integration:
# - Ebooks download to /tmp/shelfmark-downloads (temporary, manual transfer to Mac)
# - Audiobooks download to audiobooks directory → Audiobookshelf serves
# - Shelfmark is a search UI only - user manually organizes ebooks with Calibre Desktop on Mac
#
# Storage:
# - Config/database: /var/lib/shelfmark (on NVMe SSD, 10GB quota)
# - Ebook downloads: /tmp/shelfmark-downloads (temporary, manually transfer to Mac)
# - Audiobook downloads: /data/media/audiobooks (auto-imported by Audiobookshelf)
#
# Network:
# - Runs on host network (not tunneled through VPN)
# - Book sources (Anna's Archive, Z-Library) accessible from India without VPN
# - WebUI directly accessible on local network
#
# Access:
# - Local: http://192.168.0.200:8084
# - External: https://shelfmark.somesh.dev (via Cloudflare Tunnel)
#
# Security:
# - ⚠️  IMPORTANT: Enable authentication in Shelfmark settings after deployment!
# - Settings → Authentication → Enable login requirement
# - Create admin account (username: somesh) with a STRONG password
# - Until auth is enabled, anyone with the URL can access Shelfmark
#
# Post-deployment setup:
# 1. Access http://192.168.0.200:8084 or https://shelfmark.somesh.dev
# 2. **PRIORITY: Enable Authentication (Settings → Authentication)**
#    - Enable "Require Authentication"
#    - Create admin account: username "somesh", STRONG password
#    - Save and test login
# 3. Configure download paths in Settings:
#    - Ebooks: /books/downloads (temporary storage)
#    - Audiobooks: /books/audiobooks
# 4. Use Shelfmark web UI to download books directly to your Mac browser
# 5. Or use scp to transfer from /tmp/shelfmark-downloads to Mac
# 6. Organize with Calibre Desktop on Mac, sync via Syncthing to NUC
# 7. Optional: Configure metadata providers (Hardcover API key)
# 8. Optional: Add IRC/Prowlarr sources
#
# File Processing:
# - Customizable download paths and file renaming
# - Template-based renaming with metadata
# - Atomic writes (via .crdownload files) to prevent partial imports
#
# Sources:
# - Anna's Archive (primary)
# - Libgen (fallback)
# - Z-Library via Anna's Archive
# - Optional: IRC, Prowlarr indexers, Usenet
#
# ============================================================================

{ config, lib, pkgs, ... }:

let
  # Port configuration
  httpPort = 8084;
  
  # Paths
  configDir = "/var/lib/shelfmark";
  ebooksDir = "/tmp/shelfmark-downloads";  # Temporary downloads
  audiobooksDir = "/data/media/audiobooks";
  
  # Docker image
  image = "ghcr.io/calibrain/shelfmark:latest";
in
{
  # ============================================================================
  # DOCKER CONTAINER ON HOST NETWORK
  # ============================================================================
  
  # Simple Docker container running on host network
  # Book sources (Anna's Archive, Z-Library) are accessible from India
  # without requiring VPN tunneling
  
  systemd.services.docker-shelfmark = {
    description = "Shelfmark Book Downloader";
    
    after = [ 
      "docker.service" 
      "storage-online.target" 
    ];
    requires = [ "docker.service" ];
    wants = [ "storage-online.target" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = "10s";
      TimeoutStartSec = "0";
      TimeoutStopSec = "120";
    };
    
    # Pre-start: Pull image and cleanup old container
    preStart = ''
      ${pkgs.docker}/bin/docker pull ${image}
      ${pkgs.docker}/bin/docker rm -f shelfmark 2>/dev/null || true
    '';
    
    # Start: Run container on host network
    script = ''
      ${pkgs.docker}/bin/docker run \
        --name=shelfmark \
        --network=host \
        --rm \
        -v ${configDir}:/config \
        -v ${ebooksDir}:/books/downloads \
        -v ${audiobooksDir}:/books/audiobooks \
        -e TZ=Asia/Kolkata \
        -e PUID=2000 \
        -e PGID=2000 \
        -e UMASK=002 \
        -e FLASK_PORT=8084 \
        -e INGEST_DIR=/books/downloads \
        -e SEARCH_MODE=direct \
        -e LOG_LEVEL=INFO \
        -e HTTP_PROXY=http://127.0.0.1:8888 \
        -e HTTPS_PROXY=http://127.0.0.1:8888 \
        ${image}
    '';
    
    # Stop: Graceful container stop
    preStop = ''
      ${pkgs.docker}/bin/docker stop shelfmark 2>/dev/null || true
    '';
    
    postStop = ''
      ${pkgs.docker}/bin/docker rm -f shelfmark 2>/dev/null || true
    '';
  };
  
  # ============================================================================
  # DIRECTORY SETUP
  # ============================================================================
  
  # Ensure config directory exists with correct permissions
  systemd.tmpfiles.rules = [
    "d ${configDir} 0755 2000 2000 -"
    "d ${ebooksDir} 1777 root root -"  # World-writable temp directory
    # Note: audiobook directory already exists from other services
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
