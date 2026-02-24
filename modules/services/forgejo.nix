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
# - Git LFS (Large File Storage) support - up to 5GB per file
# - Container Registry (OCI/Docker images) - images at git.somesh.dev/<user>/<image>
# - Optional CI/CD (Actions, disabled by default)
#
# Storage:
# - Data directory: /var/lib/forgejo (on NVMe SSD)
# - Database: SQLite (simple, sufficient for personal use)
# - Repositories stored in /var/lib/forgejo/repositories/
# - LFS objects stored in /var/lib/forgejo/data/lfs/
#
# Access:
# - Web UI: http://192.168.0.200:3030
# - SSH: ssh://git@192.168.0.200:2222/user/repo.git
# - HTTPS clone: http://192.168.0.200:3030/user/repo.git
# - Container Registry: https://git.somesh.dev/<owner>/<image>:<tag>
#
# Container Registry Usage:
# 1. Login: docker login git.somesh.dev
# 2. Build: docker build -t git.somesh.dev/<user>/<image>:<tag> .
# 3. Push: docker push git.somesh.dev/<user>/<image>:<tag>
# 4. Pull: docker pull git.somesh.dev/<user>/<image>:<tag>
# 5. Browse: git.somesh.dev/<user>/-/packages
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
  # SYSTEM PACKAGES
  # ============================================================================
  
  # Add git-lfs to system packages (required for LFS support)
  environment.systemPackages = with pkgs; [
    git-lfs
  ];
  
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
        
        # LFS (Large File Storage) settings
        LFS_START_SERVER = true;
        LFS_HTTP_AUTH_EXPIRY = "30m";  # 30 minutes for large file uploads
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
      
      # LFS (Large File Storage) configuration
      lfs = {
        # Storage path for LFS objects
        PATH = "/var/lib/forgejo/data/lfs";
        
        # Maximum file size: 5GB = 5368709120 bytes
        # Supports ML models, game assets, large videos
        MAX_FILE_SIZE = 5368709120;
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
      
      # Package Registry (includes Container Registry for Docker/OCI images)
      package = {
        # Enable package registry
        ENABLED = true;
        
        # Container registry settings
        # Images accessible at: git.somesh.dev/<owner>/<image>:<tag>
        # Web UI: git.somesh.dev/<owner>/-/packages/container/<image>
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
