# modules/services/timemachine.nix
# ============================================================================
# TIME MACHINE BACKUP SERVER (Samba with Fruit VFS)
# ============================================================================
#
# This module provides a Time Machine-compatible network backup destination
# for macOS clients using Samba's vfs_fruit module.
#
# Features:
# - Native Time Machine support (auto-discovered via Avahi/Bonjour)
# - Quota enforcement (1.5TB = 3x 512GB Mac drive)
# - Secure authentication (requires Samba user/password)
# - ZFS backend with compression
#
# Architecture:
# - Samba with vfs_fruit provides Apple SMB extensions
# - Avahi advertises the share as a Time Machine destination
# - ZFS dataset at /data/timemachine stores sparse bundle images
#
# Setup Requirements (one-time, after deployment):
# 1. Create a Samba user: sudo smbpasswd -a somesh
# 2. On Mac: System Preferences → Time Machine → Select Disk → karmalab
#
# Storage:
# - ZFS dataset: storagepool/timemachine (1.5TB quota)
# - Mount point: /data/timemachine
#
# ============================================================================

{ config, lib, pkgs, ... }:

let
  # Time Machine share configuration
  shareName = "timemachine";
  sharePath = "/data/timemachine";
  
  # Quota in MB (1.5TB = 1536GB = 1572864MB)
  # This is the Time Machine quota advertised to macOS
  timeMachineQuotaMB = 1572864;
in
{
  # ============================================================================
  # SAMBA FILE SERVER
  # ============================================================================
  
  services.samba = {
    enable = true;
    
    # Security settings
    openFirewall = false;  # We'll manage firewall manually for Tailscale
    
    # Samba configuration
    settings = {
      global = {
        # Server identification
        "server string" = "Karmalab NAS";
        "netbios name" = "karmalab";
        "workgroup" = "WORKGROUP";
        
        # Security
        "security" = "user";
        "map to guest" = "never";
        "invalid users" = [ "root" ];
        
        # Apple/macOS optimizations
        "vfs objects" = "fruit streams_xattr";
        "fruit:metadata" = "stream";
        "fruit:model" = "MacSamba";
        "fruit:posix_rename" = "yes";
        "fruit:veto_appledouble" = "no";
        "fruit:nfs_aces" = "no";
        "fruit:wipe_intentionally_left_blank_rfork" = "yes";
        "fruit:delete_empty_adfiles" = "yes";
        
        # Performance tuning
        "server min protocol" = "SMB2";
        "server max protocol" = "SMB3";
        "ea support" = "yes";
        
        # Logging
        "log level" = "1";
        "log file" = "/var/log/samba/log.%m";
        "max log size" = "1000";
      };
      
      # Time Machine share
      ${shareName} = {
        "path" = sharePath;
        "comment" = "Time Machine Backups";
        
        # Access control
        "valid users" = "somesh";
        "read only" = "no";
        "browseable" = "yes";
        
        # Time Machine specific settings
        "fruit:time machine" = "yes";
        "fruit:time machine max size" = "${toString timeMachineQuotaMB}M";
        
        # Permissions
        "create mask" = "0660";
        "directory mask" = "0770";
        "force user" = "somesh";
        "force group" = "users";
        
        # VFS objects (inherit from global + spotlight for search)
        "vfs objects" = "fruit streams_xattr";
      };
    };
  };
  
  # ============================================================================
  # AVAHI/BONJOUR SERVICE DISCOVERY
  # ============================================================================
  # Advertises the Time Machine share so macOS auto-discovers it
  
  services.avahi = {
    enable = true;
    
    # Allow other devices to discover us
    publish = {
      enable = true;
      userServices = true;
    };
    
    # Advertise Time Machine service
    extraServiceFiles = {
      timemachine = ''
        <?xml version="1.0" standalone='no'?>
        <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
        <service-group>
          <name replace-wildcards="yes">%h Time Machine</name>
          <service>
            <type>_smb._tcp</type>
            <port>445</port>
          </service>
          <service>
            <type>_adisk._tcp</type>
            <port>9</port>
            <txt-record>sys=waMa=0,adVF=0x100</txt-record>
            <txt-record>dk0=adVN=${shareName},adVF=0x82</txt-record>
          </service>
        </service-group>
      '';
    };
  };
  
  # ============================================================================
  # FIREWALL CONFIGURATION
  # ============================================================================
  # Only allow Samba access from local network and Tailscale
  
  networking.firewall = {
    # Allow Samba on local network
    allowedTCPPorts = [ 
      445   # SMB
      139   # NetBIOS Session
    ];
    allowedUDPPorts = [ 
      137   # NetBIOS Name Service
      138   # NetBIOS Datagram
    ];
    
    # Also allow on Tailscale interface
    interfaces."tailscale0" = {
      allowedTCPPorts = [ 445 139 ];
      allowedUDPPorts = [ 137 138 ];
    };
  };
  
  # ============================================================================
  # SAMBA USER SETUP REMINDER
  # ============================================================================
  # Note: Samba requires a separate password database.
  # After deployment, run: sudo smbpasswd -a somesh
  # This creates the Samba user with a password for Time Machine auth.
  
  # ============================================================================
  # SYSTEMD DEPENDENCIES
  # ============================================================================
  # Ensure Samba starts after ZFS datasets are mounted
  
  systemd.services.samba-smbd = {
    after = [ "storage-online.target" ];
    wants = [ "storage-online.target" ];
  };
  
  # ============================================================================
  # PACKAGES
  # ============================================================================
  # Include samba package for smbpasswd command
  
  environment.systemPackages = with pkgs; [
    samba  # Provides smbpasswd, smbclient, etc.
  ];
}
