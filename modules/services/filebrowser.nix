# modules/services/filebrowser.nix
# ============================================================================
# FILEBROWSER - WEB-BASED FILE MANAGER
# ============================================================================
#
# FileBrowser is a lightweight web-based file manager written in Go. It provides
# a clean, modern UI for browsing, uploading, downloading, and managing files
# directly in the browser - perfect for manual media management.
#
# Features:
# - File operations: copy, move, rename, delete, upload, download
# - Multi-file operations (select multiple, drag-and-drop)
# - File preview (videos, images, text files)
# - Search across all files
# - Share files via temporary download links
# - Custom commands (can add shell commands to right-click menu)
# - User management with per-user permissions
#
# Use Cases:
# - Manual torrent management: Move files from /downloads/complete to /movies or /tv
# - Quick file organization: Rename, reorganize media files
# - Preview before moving: Click video file to preview before organizing
# - Trigger Jellyfin scan: Custom command to refresh Jellyfin library
#
# Workflow Example:
# 1. Download torrent manually via Deluge (saves to /downloads/complete)
# 2. Open FileBrowser: http://karmalab:8085
# 3. Navigate to downloads/complete/
# 4. Find movie file, right-click → Cut
# 5. Navigate to movies/
# 6. Right-click → Paste
# 7. Right-click → "Refresh Jellyfin Library" (custom command)
# 8. Movie appears in Jellyfin within 30 seconds
#
# Storage:
# - Config/database: /var/lib/filebrowser (on NVMe SSD, ~10MB)
# - Root directory: /data/media (access to all media subdirectories)
#
# Access:
# - Local: http://192.168.0.200:8085
# - Tailscale: http://karmalab:8085
# - External: https://files.somesh.dev (local/Tailscale only - no public access)
#
# Security:
# - Username/password authentication required
# - No anonymous access
# - Local network and Tailscale only (not exposed publicly)
# - Respects Linux file permissions (media group)
#
# Post-deployment setup:
# 1. Access http://192.168.0.200:8085
# 2. Login with default credentials: admin/admin
# 3. IMMEDIATELY change password:
#    - Settings → User Management → Edit admin user → Change password
# 4. Create your user:
#    - Settings → User Management → Add User
#    - Username: somesh
#    - Password: (strong password)
#    - Scope: /data/media
#    - Permissions: Admin, Execute, Create, Rename, Modify, Delete, Share, Download
# 5. Logout and login as somesh
# 6. Delete default admin user:
#    - Settings → User Management → Delete admin
# 7. Disable signup:
#    - Settings → Global Settings → Signup: Disable
# 8. Add custom command "Refresh Jellyfin":
#    - Settings → Commands → Add Command
#    - Name: Refresh Jellyfin Library
#    - Command: curl -X POST "http://192.168.0.200:8096/Library/Refresh" -H "X-MediaBrowser-Token: YOUR_API_KEY"
#    - Get API key from Jellyfin: Dashboard → API Keys → Add API Key
#
# ============================================================================

{ config, lib, pkgs, ... }:

let
  # Port configuration
  httpPort = 8085;
  
  # Paths
  dataDir = "/var/lib/filebrowser";
  rootDir = "/data/media";  # Root directory for file browsing
in
{
  # ============================================================================
  # FILEBROWSER SERVICE
  # ============================================================================
  
  systemd.services.filebrowser = {
    description = "FileBrowser - Web File Manager";
    after = [ "network-online.target" "storage-online.target" ];
    wants = [ "network-online.target" "storage-online.target" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "simple";
      User = "filebrowser";
      Group = "media";  # Member of media group for write access
      
      # FileBrowser command
      ExecStart = ''
        ${pkgs.filebrowser}/bin/filebrowser \
          --address 0.0.0.0 \
          --port ${toString httpPort} \
          --database ${dataDir}/filebrowser.db \
          --root ${rootDir} \
          --noauth=false
      '';
      
      Restart = "on-failure";
      RestartSec = "10s";
      
      # Security hardening
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ dataDir rootDir ];
    };
  };
  
  # ============================================================================
  # USER CONFIGURATION
  # ============================================================================
  
  users.users.filebrowser = {
    isSystemUser = true;
    group = "media";  # Member of media group for write access to /data/media
    home = dataDir;
  };
  
  # ============================================================================
  # DIRECTORY SETUP
  # ============================================================================
  
  # Ensure data directory exists with correct permissions
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0755 filebrowser media -"
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
