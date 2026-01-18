# modules/services/firefox-browser.nix
# ============================================================================
# FIREFOX BROWSER - WEB-ACCESSIBLE BROWSER FOR AUTHENTICATED DOWNLOADS
# ============================================================================
#
# LinuxServer Firefox container provides a full Firefox browser accessible
# via web UI, enabling authenticated downloads directly to NUC storage.
#
# Use Case:
# - Google Takeout downloads requiring login
# - Any website requiring authentication before download
# - Browser-based downloads that can't be offloaded to aria2
#
# Access:
# - HTTPS: https://192.168.0.200:3011 (recommended - required for modern features)
# - HTTP: http://192.168.0.200:3010
#
# Downloads:
# - Firefox downloads go to: /downloads (in-container)
# - Mapped to: /data/media/downloads (on host)
# - For Google Takeout: Set Firefox to save to /downloads/google-takeout/{account}/
#
# Usage for Google Takeout:
# 1. Open https://192.168.0.200:3011
# 2. Navigate to takeout.google.com
# 3. Log into your Google account
# 4. Click download - files save directly to NUC storage
# 5. Firefox's built-in download manager handles resume on failure
#
# ============================================================================

{ config, lib, pkgs, ... }:

let
  # Port configuration
  httpPort = 3010;   # KasmVNC HTTP
  httpsPort = 3011;  # KasmVNC HTTPS (recommended)
  
  # Paths
  configDir = "/var/lib/firefox-browser";
  downloadDir = "/data/media/downloads";
  
  # Docker image
  image = "lscr.io/linuxserver/firefox:latest";
in
{
  # ============================================================================
  # FIREFOX DOCKER CONTAINER
  # ============================================================================
  
  virtualisation.oci-containers.containers.firefox-browser = {
    image = image;
    autoStart = true;
    
    ports = [
      "${toString httpPort}:3000"   # KasmVNC HTTP
      "${toString httpsPort}:3001"  # KasmVNC HTTPS
    ];
    
    volumes = [
      "${configDir}:/config:rw"
      "${downloadDir}:/downloads:rw"
    ];
    
    environment = {
      TZ = "Asia/Kolkata";
      PUID = "2000";
      PGID = "2000";
      # Optional: Basic auth (uncomment to enable)
      # CUSTOM_USER = "somesh";
      # PASSWORD = "your-password-here";
    };
    
    # Required for modern websites (YouTube, etc.)
    # Without this, browser tabs may crash
    extraOptions = [
      "--shm-size=1g"
    ];
  };
  
  # ============================================================================
  # DIRECTORY SETUP
  # ============================================================================
  
  systemd.tmpfiles.rules = [
    "d ${configDir} 0755 2000 2000 -"
  ];
  
  # ============================================================================
  # FIREWALL CONFIGURATION
  # ============================================================================
  
  networking.firewall = {
    allowedTCPPorts = [ httpPort httpsPort ];
    
    interfaces."tailscale0" = {
      allowedTCPPorts = [ httpPort httpsPort ];
    };
  };
}
