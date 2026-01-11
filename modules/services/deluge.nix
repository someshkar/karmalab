# modules/services/deluge.nix
# ============================================================================
# NATIVE DELUGE SERVICE IN VPN NAMESPACE
# ============================================================================
#
# This module configures Deluge torrent client to run inside the VPN namespace.
# All torrent traffic is isolated and routed through WireGuard VPN.
#
# Architecture:
# - deluged (daemon) runs in VPN namespace - handles all torrent traffic
# - deluge-web runs in VPN namespace - web UI accessible via veth
# - Kill-switch: If VPN fails, no traffic leaks (namespace has no other route)
#
# Access:
# - Web UI: http://10.200.1.2:8112 (from host)
# - Daemon: 10.200.1.2:58846 (for Radarr/Sonarr integration)
#
# Integration with *arr stack:
# - Radarr/Sonarr connect to Deluge at 10.200.1.2:58846
# - Download path: /data/media/downloads/complete
# - Incomplete path: /data/media/downloads/incomplete
#
# ============================================================================

{ config, lib, pkgs, ... }:

let
  # VPN namespace settings (must match wireguard-vpn.nix)
  vpnNamespace = "vpn";
  vpnIp = "10.200.1.2";
  hostIp = "10.200.1.1";
  
  # Deluge ports
  webPort = 8112;
  daemonPort = 58846;
  
  # User/group configuration
  delugeUser = "deluge";
  delugeGroup = "media";  # Share with other media services
  
  # Data paths
  configDir = "/var/lib/deluge";
  downloadComplete = "/data/media/downloads/complete";
  downloadIncomplete = "/data/media/downloads/incomplete";
in
{
  # ============================================================================
  # DELUGE USER CONFIGURATION
  # ============================================================================
  
  users.users.${delugeUser} = {
    isSystemUser = true;
    group = delugeGroup;
    home = configDir;
    createHome = true;
    description = "Deluge BitTorrent daemon";
  };
  
  # Media group is created in main configuration
  # users.groups.media = { gid = 2000; };
  
  # ============================================================================
  # DELUGE DAEMON SERVICE (in VPN namespace)
  # ============================================================================
  
  systemd.services.deluged = {
    description = "Deluge BitTorrent Daemon (VPN Isolated)";
    
    # Dependencies - use "wants" for graceful degradation
    after = [ 
      "network.target" 
      "wireguard-vpn.service"
      "storage-online.target"
    ];
    wants = [ 
      "wireguard-vpn.service"
      "storage-online.target"
    ];
    # Require VPN - we don't want torrents without VPN
    requires = [ "wireguard-vpn.service" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "simple";
      User = delugeUser;
      Group = delugeGroup;
      UMask = "002";
      
      # Run in VPN namespace - this is the key security feature
      NetworkNamespacePath = "/var/run/netns/${vpnNamespace}";
      
      # Deluge daemon command
      ExecStart = "${pkgs.deluge}/bin/deluged -d -c ${configDir} -l ${configDir}/deluged.log -L info";
      
      # Graceful shutdown
      ExecStop = "${pkgs.deluge}/bin/deluge-console -c ${configDir} halt";
      
      # Restart on failure
      Restart = "on-failure";
      RestartSec = "10s";
      
      # Security hardening
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ 
        configDir 
        downloadComplete 
        downloadIncomplete 
        "/data/media"
      ];
    };
    
    # Initialize config directory
    preStart = ''
      mkdir -p ${configDir}
      chown -R ${delugeUser}:${delugeGroup} ${configDir}
    '';
  };
  
  # ============================================================================
  # DELUGE WEB UI SERVICE (in VPN namespace)
  # ============================================================================
  
  systemd.services.deluge-web = {
    description = "Deluge Web UI (VPN Isolated)";
    
    after = [ "deluged.service" ];
    requires = [ "deluged.service" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "simple";
      User = delugeUser;
      Group = delugeGroup;
      
      # Run in VPN namespace
      NetworkNamespacePath = "/var/run/netns/${vpnNamespace}";
      
      # Bind to all interfaces in namespace (accessible via veth)
      ExecStart = "${pkgs.deluge}/bin/deluge-web -c ${configDir} -p ${toString webPort}";
      
      Restart = "on-failure";
      RestartSec = "10s";
      
      # Security hardening
      NoNewPrivileges = true;
      PrivateTmp = true;
    };
  };
  
  # ============================================================================
  # PORT FORWARDING FROM HOST TO VPN NAMESPACE
  # ============================================================================
  # This allows accessing Deluge from the host network
  
  systemd.services.deluge-port-forward = {
    description = "Forward Deluge ports from host to VPN namespace";
    
    after = [ "deluge-web.service" "netns-vpn-veth.service" ];
    requires = [ "netns-vpn-veth.service" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = "5s";
    };
    
    # Use socat to forward ports
    script = ''
      # Forward web UI port
      ${pkgs.socat}/bin/socat TCP-LISTEN:${toString webPort},fork,reuseaddr TCP:${vpnIp}:${toString webPort} &
      WEB_PID=$!
      
      # Forward daemon port
      ${pkgs.socat}/bin/socat TCP-LISTEN:${toString daemonPort},fork,reuseaddr TCP:${vpnIp}:${toString daemonPort} &
      DAEMON_PID=$!
      
      # Wait for either to exit
      wait $WEB_PID $DAEMON_PID
    '';
  };
  
  # ============================================================================
  # DELUGE INITIAL CONFIGURATION
  # ============================================================================
  # Creates default configuration files if they don't exist
  
  systemd.services.deluge-init = {
    description = "Initialize Deluge configuration";
    
    before = [ "deluged.service" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      User = delugeUser;
      Group = delugeGroup;
      RemainAfterExit = true;
    };
    
    # Only run if config doesn't exist
    unitConfig = {
      ConditionPathExists = "!${configDir}/core.conf";
    };
    
    script = ''
      mkdir -p ${configDir}
      
      # Create auth file (username:password:level)
      # Level 10 = admin
      cat > ${configDir}/auth << 'EOF'
localclient:deluge:10
admin:deluge:10
EOF
      chmod 600 ${configDir}/auth
      
      # Create core.conf with sensible defaults
      cat > ${configDir}/core.conf << EOF
{
    "file": 1,
    "format": 1
}{
    "add_paused": false,
    "allow_remote": true,
    "auto_managed": true,
    "copy_torrent_file": false,
    "daemon_port": ${toString daemonPort},
    "del_copy_torrent_file": false,
    "dht": true,
    "dont_count_slow_torrents": true,
    "download_location": "${downloadComplete}",
    "enabled_plugins": [],
    "enc_in_policy": 1,
    "enc_level": 2,
    "enc_out_policy": 1,
    "geoip_db_location": "/usr/share/GeoIP/GeoIP.dat",
    "ignore_limits_on_local_network": true,
    "listen_ports": [
        6881,
        6891
    ],
    "listen_random_port": true,
    "lsd": true,
    "max_active_downloading": 5,
    "max_active_limit": 10,
    "max_active_seeding": 10,
    "max_connections_global": 200,
    "max_connections_per_second": 20,
    "max_connections_per_torrent": -1,
    "max_download_speed": -1.0,
    "max_download_speed_per_torrent": -1,
    "max_half_open_connections": 50,
    "max_upload_slots_global": 4,
    "max_upload_slots_per_torrent": -1,
    "max_upload_speed": -1.0,
    "max_upload_speed_per_torrent": -1,
    "move_completed": true,
    "move_completed_path": "${downloadComplete}",
    "natpmp": true,
    "new_release_check": false,
    "outgoing_ports": [
        0,
        0
    ],
    "path_chooser_accelerator_string": "Tab",
    "path_chooser_auto_complete_enabled": true,
    "path_chooser_max_popup_rows": 20,
    "path_chooser_show_chooser_button_on_localhost": true,
    "path_chooser_show_hidden_files": false,
    "peer_tos": "0x00",
    "plugins_location": "${configDir}/plugins",
    "pre_allocate_storage": false,
    "prioritize_first_last_pieces": true,
    "queue_new_to_top": false,
    "random_outgoing_ports": true,
    "random_port": true,
    "rate_limit_ip_overhead": true,
    "remove_seed_at_ratio": false,
    "seed_time_limit": 180,
    "seed_time_ratio_limit": 7.0,
    "send_info": false,
    "sequential_download": false,
    "share_ratio_limit": 2.0,
    "shared": false,
    "stop_seed_at_ratio": false,
    "stop_seed_ratio": 2.0,
    "super_seeding": false,
    "torrentfiles_location": "${configDir}/torrents",
    "upnp": true,
    "utpex": true
}
EOF
      
      # Create web.conf for web UI
      cat > ${configDir}/web.conf << EOF
{
    "file": 1,
    "format": 1
}{
    "base": "/",
    "cert": "ssl/daemon.cert",
    "default_daemon": "",
    "enabled_plugins": [],
    "first_login": true,
    "https": false,
    "interface": "0.0.0.0",
    "language": "",
    "pkey": "ssl/daemon.pkey",
    "port": ${toString webPort},
    "pwd_salt": "",
    "pwd_sha1": "",
    "session_timeout": 3600,
    "show_session_speed": true,
    "show_sidebar": true,
    "sidebar_multiple_filters": true,
    "sidebar_show_zero": false,
    "theme": "gray"
}
EOF
      
      echo "Deluge configuration initialized"
      echo "Default credentials: admin / deluge"
      echo "Change password after first login!"
    '';
  };
  
  # ============================================================================
  # ENVIRONMENT PACKAGES
  # ============================================================================
  
  environment.systemPackages = with pkgs; [
    deluge    # CLI tools
    socat     # Port forwarding
  ];
  
  # ============================================================================
  # FIREWALL CONFIGURATION
  # ============================================================================
  
  networking.firewall = {
    # Deluge ports accessible via Tailscale
    interfaces."tailscale0".allowedTCPPorts = [ 
      webPort     # Web UI
      daemonPort  # Daemon for arr stack
    ];
    
    # Also allow on veth for local access
    interfaces."veth-host".allowedTCPPorts = [ 
      webPort
      daemonPort
    ];
  };
}
