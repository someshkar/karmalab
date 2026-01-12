# modules/services/forgejo.nix
# ============================================================================
# FORGEJO GIT SERVER
# ============================================================================
#
# Forgejo is a lightweight, self-hosted Git forge (GitHub/GitLab alternative).
# It's a community fork of Gitea focused on sustainability and independence.
#
# Features:
# - Git repository hosting
# - Web-based code browsing
# - Issue tracking
# - Pull requests
# - SSH and HTTPS access
# - Optional CI/CD (Actions, disabled by default)
#
# Storage:
# - Data directory: /var/lib/forgejo (on NVMe SSD)
# - Database: SQLite (simple, sufficient for personal use)
# - Repositories stored in /var/lib/forgejo/repositories/
#
# Access:
# - Web UI: http://192.168.0.200:3030
# - SSH: ssh://git@192.168.0.200:2222/user/repo.git
# - HTTPS clone: http://192.168.0.200:3030/user/repo.git
#
# Post-deployment setup:
# 1. Access http://192.168.0.200:3030
# 2. Complete initial setup wizard
# 3. Create admin account (recommend: somesh)
# 4. Add SSH key in Settings -> SSH/GPG Keys
# 5. Create repositories
#
# Future (Cloudflare Tunnel):
# - https://git.somesh.xyz
#
# ============================================================================

{ config, lib, pkgs, ... }:

let
  # Ports
  httpPort = 3030;
  sshPort = 2222;
  
  # Domain for external access via Cloudflare Tunnel
  domain = "git.somesh.dev";
in
{
  # ============================================================================
  # FORGEJO SERVICE
  # ============================================================================
  
  services.forgejo = {
    enable = true;
    
    # Database - SQLite for simplicity
    database.type = "sqlite3";
    
    # LFS (Large File Storage) support
    lfs.enable = true;
    
    # Forgejo settings (maps to app.ini)
    settings = {
      # Server settings
      server = {
        # HTTP settings
        HTTP_PORT = httpPort;
        HTTP_ADDR = "0.0.0.0";
        DOMAIN = domain;
        ROOT_URL = "https://${domain}/";
        
        # SSH settings
        START_SSH_SERVER = true;
        SSH_PORT = sshPort;
        SSH_LISTEN_HOST = "0.0.0.0";
        
        # Landing page
        LANDING_PAGE = "login";
      };
      
      # Service settings
      service = {
        # Disable public registration - only admin can create accounts
        DISABLE_REGISTRATION = true;
        
        # Require sign-in to view anything
        REQUIRE_SIGNIN_VIEW = false;
        
        # Default settings for new users
        DEFAULT_KEEP_EMAIL_PRIVATE = true;
        DEFAULT_ALLOW_CREATE_ORGANIZATION = true;
      };
      
      # Repository settings
      repository = {
        # Default branch name
        DEFAULT_BRANCH = "main";
        
        # Enable repository statistics
        ENABLE_PUSH_CREATE_USER = true;  # Allow creating repos via push
      };
      
      # Session settings
      session = {
        # Use cookie for sessions
        PROVIDER = "file";
        
        # Session lifetime (in seconds, 7 days)
        SESSION_LIFE_TIME = 604800;
      };
      
      # Security settings
      security = {
        # Minimum password length
        MIN_PASSWORD_LENGTH = 8;
        # Note: INSTALL_LOCK is managed automatically by NixOS module
      };
      
      # UI settings
      ui = {
        # Default theme
        DEFAULT_THEME = "forgejo-auto";
        
        # Show repo sizes
        SHOW_USER_EMAIL = false;
      };
      
      # Actions (CI/CD) - disabled for now
      actions = {
        ENABLED = false;
      };
      
      # Mailer - disabled (no email server configured)
      mailer = {
        ENABLED = false;
      };
      
      # Picture/avatar settings
      picture = {
        # Use Gravatar for avatars
        ENABLE_FEDERATED_AVATAR = true;
        DISABLE_GRAVATAR = false;
      };
      
      # Logging
      log = {
        LEVEL = "Info";
        MODE = "console";
      };
    };
  };
  
  # ============================================================================
  # FIREWALL CONFIGURATION
  # ============================================================================
  
  networking.firewall = {
    # Allow HTTP and SSH ports
    allowedTCPPorts = [ httpPort sshPort ];
    
    # Also allow on Tailscale interface
    interfaces."tailscale0" = {
      allowedTCPPorts = [ httpPort sshPort ];
    };
  };
  
  # ============================================================================
  # SYSTEMD SERVICE OVERRIDES
  # ============================================================================
  
  systemd.services.forgejo = {
    # Ensure forgejo starts after network is available
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };
}
