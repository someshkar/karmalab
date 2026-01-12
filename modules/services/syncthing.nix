# modules/services/syncthing.nix
# ============================================================================
# SYNCTHING FILE SYNCHRONIZATION SERVICE
# ============================================================================
#
# Syncthing is a decentralized file synchronization tool that syncs files
# between devices without requiring a central server.
#
# Use Case:
# - Obsidian vault sync across MacBook, iPhone (Sushitrain), and server
# - Calibre library sync between server and MacBook (for Kindle workflow)
# - Server acts as always-on sync node and backup
#
# Architecture:
#   MacBook (Syncthing) <---> Karmalab (Syncthing) <---> iPhone (Sushitrain)
#   
#   Synced Folders:
#   - Obsidian vault: /var/lib/syncthing/sync/Obsidian
#   - Calibre library: /data/media/ebooks/calibre-library
#
# Storage:
# - Config/database: /var/lib/syncthing (managed by NixOS module)
# - Synced folders:
#   * Obsidian: /var/lib/syncthing/sync/Obsidian
#   * Calibre: /data/media/ebooks/calibre-library (bidirectional)
#
# Access:
# - Web UI: http://192.168.0.200:8384 (requires authentication)
# - Sync Protocol: Port 22000 (TCP only - for Cloudflare Tunnel compatibility)
# - Local Discovery: Port 21027 (UDP)
# - External: sync.somesh.dev (via Cloudflare Tunnel)
#
# Post-deployment setup:
# 1. Access Web UI at http://192.168.0.200:8384
# 2. Set up GUI username/password in Settings -> GUI
# 3. Note the Device ID for pairing
# 4. Add remote devices (MacBook, iPhone)
# 5. Create shared folders:
#    a) Obsidian: /var/lib/syncthing/sync/Obsidian (bidirectional)
#    b) Calibre Library: /data/media/ebooks/calibre-library (bidirectional)
#       - On Mac, point to: /Users/somesh/Calibre Library
#       - This enables: Server downloads → Mac Calibre app → USB to Kindle
#
# Remote device configuration:
# - For devices connecting via Cloudflare Tunnel, set the server address to:
#   tcp://sync.somesh.dev:443
# - This bypasses global relay servers for faster direct sync
#
# iPhone App:
# - Install "Sushitrain" (Synctrain) via TestFlight:
#   https://testflight.apple.com/join/2f54I4CM
#
# ============================================================================

{ config, lib, pkgs, ... }:

let
  # Ports
  guiPort = 8384;
  syncPort = 22000;
  discoveryPort = 21027;
  
  # Paths - let NixOS module manage dataDir, we just create sync subdirectory
  syncDir = "/var/lib/syncthing/sync";
  calibreLibrary = "/data/media/ebooks/calibre-library";
in
{
  # ============================================================================
  # SYNCTHING SERVICE (using NixOS native module)
  # ============================================================================
  
  services.syncthing = {
    enable = true;
    
    # Run as your user for easy file access
    user = "somesh";
    group = "users";
    
    # Let NixOS module manage these directories with correct permissions
    # dataDir is where config/database lives (default: /var/lib/syncthing)
    # The module automatically creates this with correct ownership
    dataDir = "/var/lib/syncthing";
    
    # Open firewall for sync protocol
    openDefaultPorts = true;
    
    # GUI settings - listen on all interfaces
    guiAddress = "0.0.0.0:${toString guiPort}";
    
    # Declarative settings
    settings = {
      # Global options
      options = {
        # Use UPnP for NAT traversal
        natEnabled = true;
        
        # Enable relaying (helps when direct connection fails)
        relaysEnabled = true;
        
        # Global discovery (find devices on the internet)
        globalAnnounceEnabled = true;
        
        # Local discovery (find devices on LAN)
        localAnnounceEnabled = true;
        localAnnouncePort = discoveryPort;
        
        # Listen on TCP only (required for Cloudflare Tunnel)
        # QUIC/UDP doesn't work through Cloudflare Tunnel
        listenAddresses = [
          "tcp://0.0.0.0:${toString syncPort}"
          "dynamic+https://relays.syncthing.net/endpoint"  # Fallback to relays
        ];
        
        # Limit bandwidth if needed (0 = unlimited)
        maxSendKbps = 0;
        maxRecvKbps = 0;
        
        # URAccepted: -1 = not decided, 0 = declined, 1 = accepted
        # Set to 0 to disable usage reporting
        urAccepted = 0;
      };
      
      # GUI settings - authentication configured via Web UI
      # Note: On first access, set up username/password in Settings -> GUI
      gui = {
        theme = "default";
        # insecureSkipHostcheck allows access from any hostname
        # Required for accessing via IP address or Cloudflare Tunnel
        insecureSkipHostcheck = true;
      };
    };
    
    # Don't override folders/devices - manage via Web UI for flexibility
    overrideDevices = false;
    overrideFolders = false;
  };
  
  # ============================================================================
  # USER CONFIGURATION
  # ============================================================================
  
  # Add syncthing user to media group for Calibre library access
  users.users.somesh = {
    extraGroups = [ "media" ];
  };
  
  # ============================================================================
  # DIRECTORY SETUP
  # ============================================================================
  
  # Create sync subdirectory for shared folders
  # The parent /var/lib/syncthing is managed by the NixOS syncthing module
  systemd.tmpfiles.rules = [
    # Main sync directory for shared folders
    "d ${syncDir} 0750 somesh users -"
    
    # Obsidian vault directory (ready for when you add the folder)
    "d ${syncDir}/Obsidian 0750 somesh users -"
    
    # Ensure Calibre library has correct permissions for syncing
    "d ${calibreLibrary} 0775 somesh media -"
  ];
  
  # ============================================================================
  # FIREWALL CONFIGURATION
  # ============================================================================
  
  networking.firewall = {
    # GUI port (sync ports already opened by openDefaultPorts)
    allowedTCPPorts = [ guiPort ];
    
    # Also allow on Tailscale interface
    interfaces."tailscale0" = {
      allowedTCPPorts = [ syncPort guiPort ];
      allowedUDPPorts = [ syncPort discoveryPort ];
    };
  };
}
