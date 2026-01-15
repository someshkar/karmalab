{ config, pkgs, lib, ... }:

{
  # Gluetun VPN container for HTTP proxy
  # Connects to Surfshark Iceland VPN for geo-unblocking services
  # Used by: Shelfmark, Prowlarr, Bazarr
  #
  # Note: Gluetun does not support native SOCKS5. It only provides:
  # - HTTP proxy (standard HTTP/HTTPS tunneling) - port 8888
  # - Shadowsocks (SOCKS5-based but requires Shadowsocks clients) - not used
  # All services are configured to use the HTTP proxy.
  
  virtualisation.oci-containers.containers.gluetun = {
    image = "qmcgaw/gluetun:latest";
    autoStart = true;
    
    ports = [
      "0.0.0.0:8888:8888"  # HTTP proxy (accessible from LAN)
    ];
    
    environment = {
      # Surfshark VPN configuration
      VPN_SERVICE_PROVIDER = "surfshark";
      VPN_TYPE = "wireguard";
      SERVER_COUNTRIES = "Iceland";
      
      # Proxy configuration
      HTTPPROXY = "on";
      SHADOWSOCKS = "off";  # Not used - requires Shadowsocks clients
      
      # Firewall configuration
      FIREWALL_OUTBOUND_SUBNETS = "192.168.0.0/24";  # Allow LAN access
      
      # Timezone
      TZ = "Asia/Kolkata";
    };
    
    # Load credentials from environment file
    environmentFiles = [
      "/etc/gluetun/surfshark-credentials"
    ];
    
    # Required capabilities for VPN
    extraOptions = [
      "--cap-add=NET_ADMIN"
      "--device=/dev/net/tun"
    ];
  };
  
  # Health check service
  systemd.services.gluetun-health-check = {
    description = "Gluetun VPN health check";
    after = [ "docker-gluetun.service" ];
    wants = [ "docker-gluetun.service" ];
    
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "gluetun-health-check" ''
        #!/usr/bin/env bash
        set -e
        
        echo "Checking Gluetun VPN connection..."
        
        # Check if container is running
        if ! ${pkgs.docker}/bin/docker ps | grep -q gluetun; then
          echo "ERROR: Gluetun container not running"
          exit 1
        fi
        
        # Check VPN connection
        if ! ${pkgs.docker}/bin/docker logs gluetun 2>&1 | tail -50 | grep -q "ip address\|Public IP"; then
          echo "WARNING: VPN may not be connected yet"
          exit 0
        fi
        
        # Check public IP (should be Iceland)
        IP=$(${pkgs.docker}/bin/docker exec gluetun wget -qO- https://api.ipify.org || echo "unknown")
        echo "Gluetun public IP: $IP"
        
        # Check HTTP proxy
        if ${pkgs.curl}/bin/curl --proxy http://127.0.0.1:8888 -m 5 https://api.ipify.org >/dev/null 2>&1; then
          echo "HTTP proxy working"
        else
          echo "WARNING: HTTP proxy not responding"
        fi
        
        echo "Gluetun health check complete"
      '';
    };
  };
  
  # Run health check on timer
  systemd.timers.gluetun-health-check = {
    description = "Gluetun VPN health check timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "30min";
      Unit = "gluetun-health-check.service";
    };
  };
  
  # Open firewall for HTTP proxy
  networking.firewall.allowedTCPPorts = [ 8888 ];
}
