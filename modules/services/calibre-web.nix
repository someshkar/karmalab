# modules/services/calibre-web.nix
# ============================================================================
# CALIBRE-WEB - EBOOK LIBRARY WEB INTERFACE
# ============================================================================
#
# Calibre-Web is a web app providing a clean interface for browsing, reading,
# and downloading eBooks using an existing Calibre database. It's designed to
# work alongside the Calibre desktop app and provide remote access to your
# ebook library.
#
# Features:
# - Browse and search your Calibre library
# - Read books in-browser (EPUB, PDF, CBR, CBZ)
# - Download books in various formats
# - Send books to Kindle via email
# - OPDS feed support (for mobile reading apps)
# - User management with per-user shelf support
# - Metadata editing
# - Upload new books
#
# Integration:
# - Works with existing Calibre library database
# - Shelfmark (search UI) → Download to Mac → Calibre Desktop (Mac) → Syncthing → NUC
# - Calibre-Web displays the synced library (no auto-import, Mac does organization)
# - Syncthing provides bidirectional sync between Mac and NUC
#
# Storage:
# - Config/database: /var/lib/calibre-web (on NVMe SSD, 5GB quota)
# - Calibre library: /data/media/ebooks/calibre-library (on ZFS, 100GB quota)
# - Library structure:
#   /data/media/ebooks/calibre-library/
#     ├── metadata.db (Calibre database - Calibre-Web reads this)
#     ├── Author Name/
#     │   └── Book Title (ID)/
#     │       ├── cover.jpg
#     │       ├── metadata.opf
#     │       └── book.epub
#
# Access:
# - Local: http://192.168.0.200:8083
# - External: https://books.somesh.dev (via Cloudflare Tunnel)
#
# Post-deployment setup:
# 1. Access http://192.168.0.200:8083
# 2. Login with default admin credentials:
#    - Username: admin
#    - Password: admin123
# 3. Change admin password immediately
# 4. Set database location: /calibre-library/metadata.db
# 5. Create your user account (username: somesh)
# 6. Optional: Configure OPDS feed for mobile apps
# 7. Optional: Configure Kindle email for send-to-kindle
#
# OPDS Feed Access:
# - OPDS URL: http://192.168.0.200:8083/opds
# - Use with mobile reading apps (KyBook, FBReader, etc.)
#
# Security:
# - Login required (no anonymous access)
# - Admin can create additional users
# - Per-user bookshelves and reading progress
#
# Workflow (Mac-Centric with Syncthing):
# 1. Use Shelfmark web UI to search and download ebooks (saves to /tmp on NUC or Mac browser)
# 2. Transfer ebook to Mac (via Shelfmark download or scp from NUC)
# 3. Add to Calibre Desktop on Mac → Auto-fetch metadata, organize, curate
# 4. Syncthing automatically syncs Mac Calibre library → NUC /data/media/ebooks/calibre-library/
# 5. Calibre-Web detects updated metadata.db → Book appears in web UI immediately
# 6. Read via Calibre-Web, download formats, or sync to Kindle via Mac
#
# ============================================================================

{ config, lib, pkgs, ... }:

let
  # Port configuration
  httpPort = 8083;
  
  # Paths
  configDir = "/var/lib/calibre-web";
  calibreLibrary = "/data/media/ebooks/calibre-library";
in
{
  # ============================================================================
  # CALIBRE-WEB SERVICE (using NixOS native module)
  # ============================================================================
  
  services.calibre-web = {
    enable = true;
    
    listen = {
      port = httpPort;
      ip = "0.0.0.0";  # Listen on all interfaces
    };
    
    options = {
      # Point to Calibre library database
      calibreLibrary = calibreLibrary;
      
      # Enable uploads (so you can add books via web interface)
      enableBookUploading = true;
      
      # Enable ebook conversion (requires calibre package)
      # This allows format conversion (e.g., EPUB to MOBI for Kindle)
      enableBookConversion = true;
    };
  };
  
  # Install calibre for ebook conversion support
  environment.systemPackages = [ pkgs.calibre ];
  
  # ============================================================================
  # USER CONFIGURATION
  # ============================================================================
  
  # Add calibre-web user to media group for library access
  users.users.calibre-web = {
    extraGroups = [ "media" ];
  };
  
  # ============================================================================
  # DIRECTORY SETUP
  # ============================================================================
  
  # Ensure directories exist with correct permissions
  # Note: Calibre library directory is created by ZFS in storage.nix
  systemd.tmpfiles.rules = [
    # Config directory (managed by NixOS module, but ensure media group access)
    "d ${configDir} 0755 calibre-web calibre-web -"
    
    # Ensure Calibre library directory has correct permissions
    "d ${calibreLibrary} 0775 root media -"
  ];
  
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
  
  systemd.services.calibre-web = {
    # Ensure calibre-web starts after storage is available
    after = [ "network-online.target" "storage-online.target" ];
    wants = [ "network-online.target" "storage-online.target" ];
  };
}
