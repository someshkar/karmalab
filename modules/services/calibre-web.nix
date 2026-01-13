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
# - Shelfmark downloads ebooks → Calibre library → Auto-import → Calibre-Web serves
# - Syncthing syncs Calibre library to MacBook for Kindle transfers
# - Auto-import: Systemd path unit watches library and triggers refresh on new files
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
# Workflow:
# 1. Shelfmark downloads ebook → /data/media/ebooks/calibre-library
# 2. Systemd path unit detects new file → Restarts Calibre-Web (triggers library scan)
# 3. Calibre-Web serves the updated library (book appears within ~10 seconds)
# 4. Syncthing syncs to Mac → Transfer to Kindle via USB from Mac Calibre app
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
  
  # ============================================================================
  # AUTO-IMPORT: WATCH FOR NEW BOOKS
  # ============================================================================
  
  # Path unit watches Calibre library directory for changes
  # When new files are added (e.g., by Shelfmark), triggers library refresh
  systemd.paths.calibre-library-watch = {
    description = "Watch Calibre library for new books";
    wantedBy = [ "multi-user.target" ];
    
    pathConfig = {
      # Trigger on any changes to the directory (new books, modified files)
      PathChanged = calibreLibrary;
      # Wait 10 seconds before triggering (allows file writes to complete)
      TriggerLimitIntervalSec = "10s";
      TriggerLimitBurst = 1;
      Unit = "calibre-web-refresh.service";
    };
  };
  
  # Service triggered by path unit to refresh library
  systemd.services.calibre-web-refresh = {
    description = "Trigger Calibre-Web library refresh";
    
    serviceConfig = {
      Type = "oneshot";
    };
    
    script = ''
      echo "New file detected in Calibre library at $(date)"
      echo "Waiting 5 seconds for file write to complete..."
      sleep 5
      
      echo "Restarting Calibre-Web to import new books..."
      ${pkgs.systemd}/bin/systemctl restart calibre-web.service
      
      echo "Calibre-Web restarted. New books should appear in library."
    '';
  };
}
