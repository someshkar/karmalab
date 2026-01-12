# modules/services/vaultwarden.nix
# ============================================================================
# VAULTWARDEN - SELF-HOSTED PASSWORD MANAGER
# ============================================================================
#
# Vaultwarden is a lightweight, Rust implementation of the Bitwarden server API.
# It's fully compatible with official Bitwarden clients (browser, desktop, mobile).
#
# Features:
# - Password vault with end-to-end encryption
# - TOTP/2FA support
# - Password sharing (organizations)
# - Password generator
# - Secure notes, cards, identities
#
# Storage:
# - Data directory: /var/lib/vaultwarden (on NVMe SSD)
# - SQLite database (simple, sufficient for personal use)
#
# Access:
# - Local: http://192.168.0.200:8222
# - External: https://vault.somesh.dev (via Cloudflare Tunnel)
#
# Security Notes:
# - ALWAYS access via HTTPS in production (Cloudflare Tunnel provides this)
# - Admin panel disabled by default (enable only when needed)
# - Signups disabled after creating your account
#
# Post-deployment setup:
# 1. Access https://vault.somesh.dev (or local URL)
# 2. Create your account
# 3. Set SIGNUPS_ALLOWED = false in this file
# 4. Rebuild to disable further signups
# 5. Install Bitwarden app/extension and connect to your server
#
# ============================================================================

{ config, lib, pkgs, ... }:

let
  # Port configuration
  httpPort = 8222;
  
  # Domain for external access
  domain = "vault.somesh.dev";
in
{
  # ============================================================================
  # VAULTWARDEN SERVICE
  # ============================================================================
  
  services.vaultwarden = {
    enable = true;
    
    # Environment configuration
    config = {
      # Server settings
      DOMAIN = "https://${domain}";
      ROCKET_ADDRESS = "0.0.0.0";
      ROCKET_PORT = httpPort;
      
      # Signups - DISABLED after account creation for security
      SIGNUPS_ALLOWED = false;
      
      # Invitations - allow inviting users even when signups disabled
      INVITATIONS_ALLOWED = true;
      
      # Admin panel - disabled for security
      # To enable temporarily: set ADMIN_TOKEN to a secure value
      # ADMIN_TOKEN = "your-secure-admin-token";
      
      # WebSocket notifications (for real-time sync)
      WEBSOCKET_ENABLED = true;
      
      # Show password hints (disable for better security)
      SHOW_PASSWORD_HINT = false;
      
      # Disable icon downloads from external sites (privacy)
      DISABLE_ICON_DOWNLOAD = false;
      
      # Emergency access
      EMERGENCY_ACCESS_ALLOWED = true;
      
      # Sends (encrypted file sharing)
      SENDS_ALLOWED = true;
      
      # Organization settings
      ORG_CREATION_USERS = "all";  # or specific email addresses
      
      # Log level
      LOG_LEVEL = "info";
      
      # Extended logging for troubleshooting (disable in production)
      EXTENDED_LOGGING = false;
    };
  };

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
  
  systemd.services.vaultwarden = {
    # Ensure vaultwarden starts after network is available
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };
}
