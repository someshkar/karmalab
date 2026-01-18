# modules/services/jdownloader.nix
# ============================================================================
# JDOWNLOADER 2 - DOWNLOAD MANAGER WITH BROWSER EXTENSION SUPPORT
# ============================================================================
#
# JDownloader 2 is a powerful download manager with MyJDownloader integration,
# allowing downloads to be offloaded from any browser to the NUC.
#
# Features:
# - Browser extension: Right-click any link → "Send to JDownloader"
# - Multi-connection downloads (splits files for faster speed)
# - Auto-resume on failure
# - Embedded browser for authenticated downloads (Google, etc.)
# - Clipboard monitoring
#
# Access:
# - Web UI: http://192.168.0.200:5800
# - MyJDownloader: https://my.jdownloader.org (remote control)
# - Browser Extension: Sends links directly to JDownloader
#
# Downloads:
# - Output directory: /data/media/downloads/complete (same as aria2/Deluge)
#
# Setup:
# 1. Create credentials file: /etc/nixos/secrets/jdownloader.env
#    MYJDOWNLOADER_EMAIL=somesh.kar@gmail.com
#    MYJDOWNLOADER_PASSWORD=your-password-here
# 2. Deploy config: nixos-rebuild switch
# 3. Install browser extension:
#    - Chrome: https://chrome.google.com/webstore/detail/my-jdownloader/fbcohnmimjicjdomonkcbcpbpnhggkip
#    - Firefox: https://addons.mozilla.org/en-US/firefox/addon/myjdownloader-browser-extensi/
# 4. Link extension to your MyJDownloader account
# 5. Verify device "karmalab" appears at my.jdownloader.org
#
# For Google Takeout (authenticated downloads):
# 1. Open http://192.168.0.200:5800 (JDownloader Web UI)
# 2. Use embedded browser to navigate to takeout.google.com
# 3. Log into your Google account
# 4. Click download - JDownloader intercepts and downloads with resume support
#
# ============================================================================

{ config, lib, pkgs, ... }:

let
  # Port configuration
  webUIPort = 5800;
  
  # Paths
  configDir = "/var/lib/jdownloader";
  downloadDir = "/data/media/downloads/complete";
  secretsFile = "/etc/nixos/secrets/jdownloader.env";
  
  # Docker image
  image = "jlesage/jdownloader-2:latest";
in
{
  # ============================================================================
  # JDOWNLOADER DOCKER CONTAINER
  # ============================================================================
  
  virtualisation.oci-containers.containers.jdownloader = {
    image = image;
    autoStart = true;
    
    ports = [
      "${toString webUIPort}:5800"  # Web UI (browser-based VNC)
    ];
    
    volumes = [
      "${configDir}:/config:rw"
      "${downloadDir}:/output:rw"
    ];
    
    environment = {
      TZ = "Asia/Kolkata";
      KEEP_APP_RUNNING = "1";
      MYJDOWNLOADER_DEVICE_NAME = "karmalab";
      # User/group mapping
      USER_ID = "2000";
      GROUP_ID = "2000";
      UMASK = "002";
    };
    
    # Load MyJDownloader credentials from secrets file
    environmentFiles = [ secretsFile ];
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
    allowedTCPPorts = [ webUIPort ];
    
    interfaces."tailscale0" = {
      allowedTCPPorts = [ webUIPort ];
    };
  };
}
