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
# - Server acts as always-on sync node and backup
#
# Architecture:
#   MacBook (Syncthing) <---> Karmalab (Syncthing) <---> iPhone (Sushitrain)
#
# Storage:
# - Data directory: /var/lib/syncthing (on NVMe SSD for fast sync)
# - Shared folders stored under /var/lib/syncthing/sync/
#
# Access:
# - Web UI: http://192.168.0.171:8384 (requires authentication)
# - Sync Protocol: Port 22000 (TCP/UDP)
# - Local Discovery: Port 21027 (UDP)
#
# Post-deployment setup:
# 1. Access Web UI at http://192.168.0.171:8384
# 2. Set up GUI username/password in Settings -> GUI
# 3. Note the Device ID for pairing
# 4. Add remote devices (MacBook, iPhone)
# 5. Create shared folders (e.g., "Obsidian")
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
  
  # Paths
  dataDir = "/var/lib/syncthing";
  syncDir = "/var/lib/syncthing/sync";
in
{
  # ============================================================================
  # SYNCTHING SERVICE
  # ============================================================================
  
  services.syncthing = {
    enable = true;
    
    # Run as your user for easy file access
    user = "somesh";
    group = "users";
    
    # Data and config directory
    dataDir = dataDir;
    configDir = "${dataDir}/.config/syncthing";
    
    # Open firewall for sync protocol
    openDefaultPorts = true;
    
    # GUI settings
    guiAddress = "0.0.0.0:${toString guiPort}";
    
    # Override default settings
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
  # DIRECTORY SETUP
  # ============================================================================
  
  systemd.tmpfiles.rules = [
    # Main sync directory for shared folders
    "d ${syncDir} 0750 somesh users -"
    
    # Obsidian vault directory (will be created when folder is added)
    "d ${syncDir}/Obsidian 0750 somesh users -"
  ];
  
  # ============================================================================
  # FIREWALL CONFIGURATION
  # ============================================================================
  
  networking.firewall = {
    # Sync protocol ports (opened by openDefaultPorts, but explicit here)
    allowedTCPPorts = [ syncPort guiPort ];
    allowedUDPPorts = [ syncPort discoveryPort ];
    
    # Also allow on Tailscale interface
    interfaces."tailscale0" = {
      allowedTCPPorts = [ syncPort guiPort ];
      allowedUDPPorts = [ syncPort discoveryPort ];
    };
  };
  
  # ============================================================================
  # SYSTEMD SERVICE OVERRIDES
  # ============================================================================
  
  systemd.services.syncthing = {
    # Ensure syncthing starts after network is available
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    
    # Restart on failure
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };
}
