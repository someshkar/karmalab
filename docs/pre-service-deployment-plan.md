
# Pre-Service Deployment Plan for NixOS Homelab

**System:** Asus NUC with Intel N150
**Storage:** 20TB USB ZFS Pool (`storagepool`)  
**Network:** Behind CGNAT  
**Target Services:** Immich, Jellyfin, and future homelab services

---

## Overview

This document outlines the essential infrastructure setup required before deploying individual services on your NixOS homelab. Complete these steps in order to ensure a secure, reliable, and well-organized system.

---

## 1. Firewall Configuration

### Why NixOS Built-in Firewall?

The NixOS built-in firewall (`networking.firewall`) is the best choice for your homelab because:

- **Declarative Configuration**: Firewall rules are part of your NixOS configuration, making them reproducible and version-controlled
- **Integration**: Automatically integrates with other NixOS services (SSH, web servers, etc.)
- **Simplicity**: Uses iptables/nftables under the hood with a clean NixOS interface
- **Atomicity**: Changes are applied atomically with system rebuilds, reducing misconfiguration risks
- **Service-aware**: NixOS services can automatically open required ports

### Recommended Firewall Configuration

Add this to [`configuration.nix`](configuration.nix:1):

```nix
# Firewall Configuration
networking.firewall = {
  enable = true;
  
  # Allow SSH (important for remote management)
  allowedTCPPorts = [ 22 ];
  
  # Allow ping for network diagnostics
  allowPing = true;
  
  # Log dropped packets (useful for debugging)
  logRefusedConnections = true;
  logRefusedPackets = false; # Set to true only for debugging (can be verbose)
  
  # Interfaces to protect (default is all interfaces)
  # trustedInterfaces = [ "tailscale0" ]; # Add after Tailscale is configured
  
  # Rate limiting for SSH protection (optional but recommended)
  extraCommands = ''
    # Allow established connections
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    
    # Rate limit new SSH connections (max 3 per minute)
    iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --set --name SSH
    iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --update --seconds 60 --hitcount 4 --name SSH -j DROP
  '';
};
```

### fail2ban Integration

fail2ban provides automatic intrusion prevention by banning IPs that show malicious signs.

Add to [`configuration.nix`](configuration.nix:1):

```nix
# fail2ban for additional security
services.fail2ban = {
  enable = true;
  maxretry = 3;
  bantime = "1h";
  
  jails = {
    # SSH protection
    sshd = {
      enabled = true;
      port = "22";
      filter = "sshd";
      maxretry = 5;
      findtime = "10m";
      bantime = "24h";
    };
  };
};
```

### Port Management Strategy

**General Rules:**
- ✅ **Keep SSH (22) open** - Essential for management
- ✅ **Trust Tailscale interface** - Once configured, trust `tailscale0`
- ❌ **Don't expose services directly** - Use Cloudflare Tunnel or Tailscale
- ⚠️ **Only open ports when needed** - Services behind tunnels don't need exposed ports

**After Tailscale Setup:**
```nix
networking.firewall.trustedInterfaces = [ "tailscale0" ];
```

---

## 2. ZFS Automatic Snapshots

### Overview

ZFS snapshots are point-in-time copies of your filesystem that take up minimal space due to copy-on-write. They're crucial for:
- Quick recovery from mistakes
- Protection against ransomware
- Easy rollback during testing

### Automatic Snapshot Configuration

Add to [`configuration.nix`](configuration.nix:1):

```nix
# ZFS Automatic Snapshots
services.zfs.autoSnapshot = {
  enable = true;
  
  # Snapshot retention policies
  frequent = 4;   # Keep 4 snapshots, taken every 15 minutes (1 hour total)
  hourly = 24;    # Keep 24 hourly snapshots (1 day)
  daily = 7;      # Keep 7 daily snapshots (1 week)
  weekly = 4;     # Keep 4 weekly snapshots (1 month)
  monthly = 12;   # Keep 12 monthly snapshots (1 year)
  
  # Datasets to snapshot (all datasets by default)
  # Exclude datasets by setting com.sun:auto-snapshot=false on the dataset
};
```

### Recommended Retention Policy

| Frequency | Count | Coverage | Use Case |
|-----------|-------|----------|----------|
| Frequent (15min) | 4 | 1 hour | Quick recovery from immediate mistakes |
| Hourly | 24 | 1 day | Recent work recovery |
| Daily | 7 | 1 week | Short-term history |
| Weekly | 4 | 1 month | Monthly patterns |
| Monthly | 12 | 1 year | Long-term archive |

### Excluding Datasets from Auto-Snapshots

For datasets that change frequently or don't need snapshots (e.g., temporary data, cache):

```bash
# Disable auto-snapshots for a specific dataset
sudo zfs set com.sun:auto-snapshot=false storagepool/data/temp
```

### ZFS Health Monitoring

Add monitoring and email alerts for ZFS pool health:

```nix
# ZFS Event Daemon (ZED) for monitoring
services.zfs.zed = {
  enable = true;
  
  # Email notifications (requires mail server configuration)
  settings = {
    ZED_EMAIL_ADDR = "your-email@example.com";
    ZED_EMAIL_PROG = "${pkgs.msmtp}/bin/msmtp";
    ZED_EMAIL_OPTS = "-a default";
    
    # Notify on these events
    ZED_NOTIFY_VERBOSE = true;
    ZED_NOTIFY_DATA = true;
  };
};

# Simple mail transfer agent for sending alerts
programs.msmtp = {
  enable = true;
  accounts.default = {
    host = "smtp.gmail.com";
    port = 587;
    auth = true;
    user = "your-email@gmail.com";
    from = "your-email@gmail.com";
    # Password stored in /etc/msmtp-password (create this file manually)
    passwordeval = "cat /etc/msmtp-password";
    tls = true;
    tls_starttls = true;
  };
};
```

### Manual Snapshot Management

```bash
# Create manual snapshot
sudo zfs snapshot storagepool/data@before-upgrade

# List snapshots
sudo zfs list -t snapshot

# Rollback to snapshot
sudo zfs rollback storagepool/data@before-upgrade

# Delete snapshot
sudo zfs destroy storagepool/data@before-upgrade

# Send snapshot to remote (backup)
sudo zfs send storagepool/data@snapshot | ssh backup-server "zfs receive backuppool/data"
```

### Snapshot Best Practices

- ✅ Test restore procedures regularly
- ✅ Monitor snapshot space usage: `zfs list -o space`
- ✅ Create manual snapshots before major changes
- ✅ Document important snapshots with descriptive names
- ⚠️ Snapshots are not backups - maintain off-site backups
- ❌ Don't delete snapshots arbitrarily - understand dependencies

---

## 3. Network Access Strategy (CGNAT Solution)

Since you're behind CGNAT without a static IP, you need alternative solutions for remote access:

### Solution 1: Cloudflare Tunnels (HTTP/HTTPS Services)

**Use For:** Web-based services (Immich, Jellyfin web UI, etc.)

**Advantages:**
- No exposed ports required
- Free tier available
- Built-in DDoS protection
- Automatic HTTPS with Cloudflare certificates
- Works perfectly behind CGNAT

**Setup Steps:**

1. **Install Cloudflared:**

```nix
# Add to configuration.nix
environment.systemPackages = with pkgs; [
  cloudflared
];

# Enable cloudflared as a service
services.cloudflared = {
  enable = true;
  tunnels = {
    homelab = {
      credentialsFile = "/etc/cloudflared/credentials.json";
      default = "http_status:404";
      ingress = {
        # Example: Immich service
        "immich.yourdomain.com" = "http://localhost:2283";
        
        # Example: Jellyfin service
        "jellyfin.yourdomain.com" = "http://localhost:8096";
        
        # Add more services as you deploy them
      };
    };
  };
};
```

2. **Initial Setup Process:**

```bash
# Login to Cloudflare (one-time)
sudo cloudflared tunnel login

# Create tunnel (one-time)
sudo cloudflared tunnel create homelab

# Copy the credentials file to /etc/cloudflared/
sudo mkdir -p /etc/cloudflared
sudo cp ~/.cloudflared/*.json /etc/cloudflared/credentials.json

# Configure DNS (via Cloudflare dashboard or CLI)
sudo cloudflared tunnel route dns homelab immich.yourdomain.com
sudo cloudflared tunnel route dns homelab jellyfin.yourdomain.com
```

3. **Service-specific Notes:**
   - Configure each service to bind to `localhost` only
   - Cloudflare Tunnel will expose them securely
   - No need to open firewall ports for tunneled services

### Solution 2: Tailscale VPN (General Access)

**Use For:** SSH access, admin panels, full network access, non-HTTP services

**Advantages:**
- Zero-configuration VPN
- Works behind CGNAT
- End-to-end encrypted
- Free for personal use (up to 20 devices)
- Can expose services to other Tailscale devices

**Setup Steps:**

```nix
# Add to configuration.nix
services.tailscale = {
  enable = true;
  useRoutingFeatures = "server"; # Allow subnet routing if needed
};

# Open Tailscale port in firewall (for direct connections)
networking.firewall.allowedUDPPorts = [ 41641 ];

# Trust Tailscale interface completely
networking.firewall.trustedInterfaces = [ "tailscale0" ];
```

**Initial Setup:**

```bash
# After rebuild, authenticate Tailscale
sudo tailscale up

# Enable SSH through Tailscale (recommended)
sudo tailscale up --ssh

# Check status
sudo tailscale status

# Get your Tailscale IP
sudo tailscale ip
```

**Tailscale Features to Enable:**
- ✅ **MagicDNS**: Access server by hostname instead of IP
- ✅ **Tailscale SSH**: Secure SSH access without keys
- ✅ **Subnet Router**: Share homelab network with other devices (optional)

### Integration Strategy: Cloudflare + Tailscale

**Recommended Architecture:**

```
Internet Users (Public)
    ↓
Cloudflare Tunnel → Web Services (Immich, Jellyfin)
    (HTTP/HTTPS only)


You (Admin) + Trusted Devices
    ↓
Tailscale VPN → Full Access (SSH, Admin Panels, Databases)
    (All protocols)
```

**Configuration Example:**

```nix
# Services listen on localhost + Tailscale
services.immich = {
  enable = true;
  # Bind to all interfaces, but firewall protects us
  host = "0.0.0.0";
};

# Firewall blocks direct access
networking.firewall = {
  enable = true;
  
  # Only SSH is exposed to internet
  allowedTCPPorts = [ 22 ];
  
  # Tailscale interface is trusted
  trustedInterfaces = [ "tailscale0" ];
  
  # Cloudflare Tunnel runs as localhost connection (no ports needed)
};
```

### Security Considerations for CGNAT Environment

- ✅ **Least Privilege**: Only expose what's necessary via Cloudflare
- ✅ **Defense in Depth**: Use both Cloudflare (public) and Tailscale (private)
- ✅ **Regular Updates**: Keep NixOS and packages updated
- ✅ **Monitoring**: Set up alerts for unauthorized access attempts
- ✅ **Backup Access**: Configure Tailscale SSH as emergency access method
- ⚠️ **Cloudflare Access**: Consider Cloudflare Access for additional authentication
- ❌ **No Port Forwarding**: Never try to set up port forwarding (won't work with CGNAT)

---

## 4. Service-Specific ZFS Datasets

### Dataset Organization Strategy

Create separate datasets for each service to enable:
- Individual snapshot policies
- Service-specific quotas
- Isolated backup/restore
- Performance tuning per service
- Clean service removal

### Dataset Naming Convention

```
storagepool/
├── data/              # General data (already exists)
├── services/          # Root for all services
│   ├── immich/        # Photo management
│   ├── jellyfin/      # Media server
│   ├── nextcloud/     # File sync (future)
│   └── ...
└── backups/           # Local backups
    ├── immich/
    ├── jellyfin/
    └── ...
```

### Creating Datasets Before Service Deployment

```bash
# Create services root dataset
sudo zfs create storagepool/services

# Set default properties for all service datasets
sudo zfs set compression=lz4 storagepool/services
sudo zfs set atime=off storagepool/services  # Improve performance
sudo zfs set xattr=sa storagepool/services
sudo zfs set acltype=posixacl storagepool/services

# Create backups root dataset
sudo zfs create storagepool/backups
sudo zfs set compression=lz4 storagepool/backups
```

### Example: Immich Datasets

```bash
# Main Immich dataset
sudo zfs create storagepool/services/immich
sudo zfs set mountpoint=/var/lib/immich storagepool/services/immich
sudo zfs set quota=2T storagepool/services/immich  # Adjust based on needs
sudo zfs set recordsize=1M storagepool/services/immich  # Optimize for large files

# Immich upload dataset (can have different snapshot policy)
sudo zfs create storagepool/services/immich/upload
sudo zfs set quota=500G storagepool/services/immich/upload

# Immich thumbs (frequent changes, fewer snapshots)
sudo zfs create storagepool/services/immich/thumbs
sudo zfs set com.sun:auto-snapshot=false storagepool/services/immich/thumbs
sudo zfs set quota=100G storagepool/services/immich/thumbs

# Immich database (critical, more frequent snapshots)
sudo zfs create storagepool/services/immich/database
sudo zfs set quota=50G storagepool/services/immich/database
sudo zfs set recordsize=8K storagepool/services/immich/database  # Optimize for database
```

### Example: Jellyfin Datasets

```bash
# Main Jellyfin dataset
sudo zfs create storagepool/services/jellyfin
sudo zfs set mountpoint=/var/lib/jellyfin storagepool/services/jellyfin
sudo zfs set quota=10T storagepool/services/jellyfin  # Large quota for media

# Jellyfin config (frequent snapshots, small size)
sudo zfs create storagepool/services/jellyfin/config
sudo zfs set quota=10G storagepool/services/jellyfin/config
sudo zfs set recordsize=128K storagepool/services/jellyfin/config

# Jellyfin media (read-mostly, fewer snapshots)
sudo zfs create storagepool/services/jellyfin/media
sudo zfs set quota=9T storagepool/services/jellyfin/media
sudo zfs set recordsize=1M storagepool/services/jellyfin/media
sudo zfs set com.sun:auto-snapshot:frequent=false storagepool/services/jellyfin/media
sudo zfs set com.sun:auto-snapshot:hourly=false storagepool/services/jellyfin/media

# Jellyfin metadata/transcoding (temporary, no snapshots)
sudo zfs create storagepool/services/jellyfin/cache
sudo zfs set quota=100G storagepool/services/jellyfin/cache
sudo zfs set com.sun:auto-snapshot=false storagepool/services/jellyfin/cache
sudo zfs set sync=disabled storagepool/services/jellyfin/cache  # Performance
```

### Quota Recommendations

| Service | Component | Recommended Quota | Notes |
|---------|-----------|-------------------|-------|
| Immich | Total | 2-5TB | Adjust based on photo collection size |
| Immich | Database | 50-100GB | Grows with photo count |
| Immich | Thumbs | 100-200GB | Proportional to photo count |
| Jellyfin | Total | 5-15TB | Depends on media library size |
| Jellyfin | Config | 10GB | Metadata and settings |
| Jellyfin | Cache | 100-200GB | For transcoding |
| Nextcloud | Total | 1-5TB | Per user requirements |
| Database | Per DB | 50-200GB | Application dependent |

### Dataset Configuration in NixOS

Update [`disko-config.nix`](disko-config.nix:1) to include service datasets (for fresh installs) or create them manually (for existing systems):

```nix
# Add to zpool.storagepool.datasets in disko-config.nix
# (Only for reference - modify manually on existing system)

datasets = {
  "data" = {
    type = "zfs_fs";
    mountpoint = "/data";
  };
  
  "services" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/services";
  };
  
  "services/immich" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/immich";
    options = {
      quota = "2T";
      recordsize = "1M";
    };
  };
  
  "services/jellyfin" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/jellyfin";
    options = {
      quota = "10T";
      recordsize = "1M";
    };
  };
  
  "backups" = {
    type = "zfs_fs";
    mountpoint = "/backups";
  };
};
```

### Monitoring Dataset Usage

```bash
# List all datasets with space usage
sudo zfs list -o name,used,avail,refer,quota,mountpoint

# Monitor specific service
sudo zfs list -t all storagepool/services/immich

# Check snapshot space usage
sudo zfs list -t snapshot -o name,used,refer storagepool/services/immich
```

---

## 5. Additional Infrastructure Components

### System Utilities

Essential tools for system administration:

```nix
# Add to configuration.nix
environment.systemPackages = with pkgs; [
  # System monitoring
  htop
  btop
  iotop
  
  # Network tools
  curl
  wget
  dig
  mtr
  iperf3
  
  # ZFS tools
  zfs-prune-snapshots  # Clean old snapshots
  
  # File management
  tree
  ncdu  # Disk usage analyzer
  
  # Text processing
  jq    # JSON processor
  yq    # YAML processor
  
  # Security
  age   # Encryption tool
  
  # Development
  git
  vim
  
  # Container management (for future use)
  docker-compose
];
```

### Monitoring and Alerting

**Option 1: Simple - Node Exporter + Local Monitoring**

```nix
services.prometheus.exporters.node = {
  enable = true;
  enabledCollectors = [ "systemd" "zfs" ];
  port = 9100;
};

# Access metrics via Tailscale
# Visit http://tailscale-ip:9100/metrics
```

**Option 2: Full Stack - Prometheus + Grafana**

```nix
services.prometheus = {
  enable = true;
  port = 9090;
  
  scrapeConfigs = [{
    job_name = "node";
    static_configs = [{
      targets = [ "localhost:9100" ];
    }];
  }];
};

services.grafana = {
  enable = true;
  settings = {
    server = {
      http_addr = "127.0.0.1";
      http_port = 3000;
    };
  };
};

# Access Grafana via Tailscale: http://tailscale-ip:3000
```

### Backup Strategy

**Critical Data to Backup:**
- ✅ Configuration files (`/etc/nixos/`)
- ✅ Service data (Immich photos, Jellyfin media metadata)
- ✅ Databases (PostgreSQL, etc.)
- ✅ User data
- ❌ Media files (too large, can be re-obtained) - optional
- ❌ Temporary/cache data

**Backup Solutions:**

1. **Local Snapshots** (Already configured with ZFS auto-snapshot)
2. **Off-site ZFS Replication:**

```bash
# Send initial snapshot to remote server
sudo zfs snapshot -r storagepool/services@backup-$(date +%Y%m%d)
sudo zfs send -R storagepool/services@backup-$(date +%Y%m%d) | \
  ssh backup-server "zfs receive backuppool/homelab"

# Incremental backup (after initial)
sudo zfs snapshot -r storagepool/services@backup-$(date +%Y%m%d)
sudo zfs send -R -i @previous-backup storagepool/services@backup-$(date +%Y%m%d) | \
  ssh backup-server "zfs receive backuppool/homelab"
```

3. **Automated with Sanoid/Syncoid:**

```nix
services.sanoid = {
  enable = true;
  datasets = {
    "storagepool/services" = {
      recursive = true;
      autosnap = true;
      autoprune = true;
      hourly = 24;
      daily = 7;
      monthly = 12;
    };
  };
};

# Syncoid for replication (configure separately)
```

4. **Configuration Backup (Git):**

```bash
# Already using Git for configuration
cd /etc/nixos
sudo git add .
sudo git commit -m "Update configuration"
sudo git push
```

### Security Hardening Checklist

#### Pre-Deployment Security Tasks

- [ ] Enable and configure firewall
- [ ] Install and configure fail2ban
- [ ] Set up Tailscale for secure access
- [ ] Configure SSH key-based authentication
- [ ] Disable root SSH login
- [ ] Set up automatic security updates
- [ ] Configure system logging
- [ ] Enable ZFS encryption (if not already done)

#### SSH Hardening

```nix
services.openssh = {
  enable = true;
  
  settings = {
    # Disable password authentication
    PasswordAuthentication = false;
    PermitRootLogin = "no";
    
    # Only allow specific users
    AllowUsers = [ "somesh" ];
    
    # Use stronger algorithms
    KexAlgorithms = [
      "curve25519-sha256"
      "curve25519-sha256@libssh.org"
    ];
    
    # Limit authentication attempts
    MaxAuthTries = 3;
  };
  
  # Enable key-only authentication
  hostKeys = [
    {
      path = "/etc/ssh/ssh_host_ed25519_key";
      type = "ed25519";
    }
  ];
};
```

#### Automatic Security Updates

```nix
# Automatic system updates (use with caution in production)
system.autoUpgrade = {
  enable = true;
  allowReboot = false;  # Set to true if you want automatic reboots
  dates = "weekly";     # Or "daily", "02:00", etc.
  flake = "github:yourusername/your-repo#nuc-server";
};

# Or use unattended security patches only
system.autoUpgrade = {
  enable = true;
  channel = "https://nixos.org/channels/nixos-23.11";
};
```

### Documentation Practices

**What to Document:**
- ✅ Network topology and IP addresses
- ✅ Service URLs and access methods
- ✅ Dataset layout and purposes
- ✅ Backup procedures and schedules
- ✅ Recovery procedures
- ✅ Service-specific configurations
- ✅ Maintenance procedures

**Create Service Documentation Template:**

```markdown
# Service Name

## Access Information
- **Public URL**: https://service.yourdomain.com (via Cloudflare)
- **Internal URL**: http://tailscale-ip:port (via Tailscale)
- **Admin Panel**: http://tailscale-ip:admin-port

## Storage
- **Dataset**: storagepool/services/servicename
- **Quota**: XGB
- **Mountpoint**: /var/lib/servicename

## Backup
- **Snapshot Schedule**: hourly/daily/weekly
- **Backup Location**: storagepool/backups/servicename
- **Last Backup**: YYYY-MM-DD

## Maintenance
- **Update Schedule**: Monthly/Weekly
- **Logs Location**: /var/log/servicename
- **Health Check**: curl http://localhost:port/health

## Troubleshooting
- Common issues and solutions
```

---

## 6. Pre-Deployment Checklist

Complete these tasks **before** deploying individual services:

### Infrastructure Setup

- [ ] **Firewall Configuration**
  - [ ] Enable NixOS firewall
  - [ ] Configure allowed ports (SSH only)
  - [ ] Add rate limiting rules
  - [ ] Test firewall rules

- [ ] **fail2ban Setup**
  - [ ] Install fail2ban
  - [ ] Configure SSH jail
  - [ ] Test ban/unban procedures

- [ ] **ZFS Snapshots**
  - [ ] Enable auto-snapshot service
  - [ ] Configure retention policies
  - [ ] Test snapshot creation
  - [ ] Verify snapshot automatic pruning

- [ ] **ZFS Health Monitoring**
  - [ ] Configure ZFS Event Daemon (ZED)
  - [ ] Set up email alerts (optional)
  - [ ] Test alert delivery
  - [ ] Schedule scrub verification

### Network Access Setup

- [ ] **Tailscale Configuration**
  - [ ] Install Tailscale
  - [ ] Authenticate device
  - [ ] Enable MagicDNS
  - [ ] Configure Tailscale SSH
  - [ ] Test Tailscale connectivity
  - [ ] Add Tailscale to trusted interfaces

- [ ] **Cloudflare Tunnel Setup**
  - [ ] Install cloudflared
  - [ ] Create Cloudflare account/tunnel
  - [ ] Configure DNS records
  - [ ] Test tunnel connectivity
  - [ ] Prepare ingress rules template

### Storage Preparation

- [ ] **Create Service Datasets**
  - [ ] Create `storagepool/services` root
  - [ ] Create `storagepool/backups` root
  - [ ] Set default properties
  - [ ] Create Immich dataset (if deploying first)
  - [ ] Create Jellyfin dataset (if deploying)
  - [ ] Set appropriate quotas
  - [ ] Configure recordsize per service

- [ ] **Verify Dataset Configuration**
  - [ ] Check mountpoints
  - [ ] Verify quotas
  - [ ] Test write permissions
  - [ ] Verify snapshot settings

### Security Hardening

- [ ] **SSH Hardening**
  - [ ] Disable password authentication
  - [ ] Set up SSH keys
  - [ ] Disable root login
  - [ ] Configure allowed users
  - [ ] Test SSH access

- [ ] **System Updates**
  - [ ] Update all packages
  - [ ] Configure auto-updates (optional)
  - [ ] Test update process
  - [ ] Document update schedule

### Monitoring and Backup

- [ ] **Basic Monitoring**
  - [ ] Install system monitoring tools
  - [ ] Set up node exporter (optional)
  - [ ] Configure log retention
  - [ ] Test monitoring access

- [ ] **Backup Verification**
  - [ ] Document backup strategy
  - [ ] Test snapshot creation/restore
  - [ ] Set up off-site backup (optional)
  - [ ] Schedule backup tasks

### Documentation

- [ ] **Create Documentation**
  - [ ] Document network topology
  - [ ] Create service template
  - [ ] Document dataset structure
  - [ ] Write recovery procedures
  - [ ] Update Git repository

---

## 7. Service Deployment Workflow

Once the infrastructure is ready, use this workflow for deploying each service:

### Step 1: Pre-Deployment Planning
1. Read service documentation
2. Determine resource requirements (CPU, RAM, storage)
3. Identify dependencies (databases, other services)
4. Plan dataset structure
5. Determine access method (Cloudflare Tunnel, Tailscale, or both)

### Step 2: Dataset Preparation
```bash
# Create service dataset
sudo zfs create storagepool/services/servicename
sudo zfs set mountpoint=/var/lib/servicename storagepool/services/servicename
sudo zfs set quota=XG storagepool/services/servicename

# Create subdatasets if needed
sudo zfs create storagepool/services/servicename/data
sudo zfs create storagepool/services/servicename/config
```

### Step 3: NixOS Configuration
```nix
# Add to configuration.nix
services.servicename = {
  enable = true;
  dataDir = "/var/lib/servicename";
  # ... other options
};

# Add to Cloudflare Tunnel ingress (if web-based)
services.cloudflared.tunnels.homelab.ingress = {
  "servicename.yourdomain.com" = "http://localhost:PORT";
};
```

### Step 4: Deployment
```bash
# Rebuild system
sudo nixos-rebuild switch --flake /etc/nixos#nuc-server

# Verify service status
sudo systemctl status servicename

# Test access via Tailscale
curl http://$(tailscale ip -4):PORT

# Test access via Cloudflare (if configured)
curl https://servicename.yourdomain.com
```

### Step 5: Post-Deployment
1. Create initial snapshot: `sudo zfs snapshot storagepool/services/servicename@initial`
2. Document service configuration
3. Add monitoring/health checks
4. Update documentation
5. Commit configuration to Git

---

## 8. Maintenance Schedule

### Daily (Automated)
- ✅ Automatic snapshots (frequent, hourly)
- ✅ System health checks
- ✅ Log rotation

### Weekly (Automated)
- ✅ ZFS scrub
- ✅ Automatic snapshots (daily, weekly)
- ✅ System updates (if auto-update enabled)

### Monthly (Manual)
- 🔧 
- 🔧 Review ZFS snapshot usage
- 🔧 Check disk space and quotas
- 🔧 Review system logs for issues
- 🔧 Update service configurations
- 🔧 Review and update documentation
- 🔧 Test backup restore procedures
- 🔧 Security audit

### Quarterly (Manual)
- 🔧 Review and update firewall rules
- 🔧 Audit user access and permissions
- 🔧 Review and update backup strategy
- 🔧 Test disaster recovery procedures
- 🔧 Update system documentation
- 🔧 Plan for capacity upgrades

---

## 9. Troubleshooting Guide

### ZFS Issues

**Pool Won't Import:**
```bash
# Check pool status
sudo zpool import

# Force import (if needed)
sudo zpool import -f storagepool

# Check for errors
sudo zpool status -v storagepool
```

**High Memory Usage:**
```bash
# Check ARC (ZFS cache) usage
arc_summary

# Limit ARC size in configuration.nix
boot.kernelParams = [ "zfs.zfs_arc_max=8589934592" ];  # 8GB in bytes
```

**Snapshot Space Issues:**
```bash
# Find largest snapshots
sudo zfs list -t snapshot -o name,used -s used | head -20

# Delete old snapshots
sudo zfs destroy storagepool/services/servicename@snapshot-name

# Prune old snapshots automatically
sudo zfs-prune-snapshots -p daily 7d storagepool/services/servicename
```

### Network Access Issues

**Can't Connect via Tailscale:**
```bash
# Check Tailscale status
sudo tailscale status

# Restart Tailscale
sudo systemctl restart tailscale

# Re-authenticate
sudo tailscale up
```

**Cloudflare Tunnel Not Working:**
```bash
# Check cloudflared status
sudo systemctl status cloudflared

# View logs
sudo journalctl -u cloudflared -f

# Test tunnel connectivity
sudo cloudflared tunnel info homelab
```

**Firewall Blocking Connections:**
```bash
# Check firewall status
sudo iptables -L -n -v

# Temporarily disable firewall (for testing only!)
sudo systemctl stop firewall

# Check what's listening
sudo ss -tulpn
```

### Service Issues

**Service Won't Start:**
```bash
# Check service status
sudo systemctl status servicename

# View full logs
sudo journalctl -u servicename -n 100

# Check configuration syntax
nixos-rebuild dry-build --flake /etc/nixos#nuc-server
```

**Permission Issues:**
```bash
# Check dataset ownership
ls -la /var/lib/servicename

# Fix permissions
sudo chown -R servicename:servicename /var/lib/servicename

# Check ZFS permissions
sudo zfs get all storagepool/services/servicename | grep -i perm
```

---

## 10. Quick Reference Commands

### ZFS Commands
```bash
# List all pools and datasets
sudo zpool list
sudo zfs list

# Create snapshot
sudo zfs snapshot storagepool/services/servicename@snapshot-name

# List snapshots
sudo zfs list -t snapshot

# Check pool health
sudo zpool status

# Scrub pool
sudo zpool scrub storagepool

# Get dataset properties
sudo zfs get all storagepool/services/servicename

# Set quota
sudo zfs set quota=100G storagepool/services/servicename
```

### System Management
```bash
# Rebuild NixOS configuration
sudo nixos-rebuild switch --flake /etc/nixos#nuc-server

# Test configuration without applying
sudo nixos-rebuild dry-build --flake /etc/nixos#nuc-server

# Rollback to previous generation
sudo nixos-rebuild --rollback switch

# List generations
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system

# Garbage collection
sudo nix-collect-garbage -d
```

### Networking
```bash
# Tailscale status
sudo tailscale status
sudo tailscale ip

# Test connectivity
ping -c 4 $(tailscale ip -4)

# Check open ports
sudo ss -tulpn

# Test firewall
sudo iptables -L -n -v
```

### Monitoring
```bash
# System resources
htop
btop

# Disk usage
df -h
sudo zfs list -o space

# Disk I/O
iotop

# Network usage
iftop

# Service logs
sudo journalctl -u servicename -f
```

---

## 11. Next Steps

Once you've completed this pre-deployment checklist, you'll be ready to deploy individual services. Recommended deployment order:

1. **Tailscale VPN** - Establish secure remote access first
2. **Basic Monitoring** - Set up system monitoring before services
3. **Cloudflare Tunnel** - Configure tunnel infrastructure
4. **First Service (e.g., Immich)** - Deploy and test your first service
5. **Additional Services** - Add more services one at a time

### Service-Specific Guides (To be created)

Create separate guides for each service deployment:
- `docs/service-immich.md` - Photo management with Immich
- `docs/service-jellyfin.md` - Media server with Jellyfin
- `docs/service-nextcloud.md` - File sync and collaboration
- `docs/service-homepage.md` - Dashboard for all services

---

## 12. References and Resources

### NixOS Documentation
- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [NixOS Options Search](https://search.nixos.org/options)
- [NixOS Wiki](https://nixos.wiki/)

### ZFS Resources
- [OpenZFS Documentation](https://openzfs.github.io/openzfs-docs/)
- [Oracle ZFS Administration Guide](https://docs.oracle.com/cd/E19253-01/819-5461/index.html)
- [ZFS Best Practices](https://wiki.archlinux.org/title/ZFS)

### Network Tools
- [Tailscale Documentation](https://tailscale.com/kb/)
- [Cloudflare Tunnel Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)

### Homelab Community
- [/r/homelab](https://reddit.com/r/homelab)
- [/r/selfhosted](https://reddit.com/r/selfhosted)
- [Awesome-Selfhosted](https://awesome-selfhosted.net/)

---

## Conclusion

This pre-deployment plan provides a comprehensive foundation for your NixOS homelab. By completing these infrastructure tasks before deploying services, you ensure:

- ✅ **Security**: Firewall, fail2ban, and secure remote access configured
- ✅ **Reliability**: ZFS snapshots and health monitoring in place
- ✅ **Accessibility**: Cloudflare Tunnel and Tailscale ready for service exposure
- ✅ **Organization**: Structured dataset layout for clean service management
- ✅ **Maintainability**: Documentation and monitoring established
- ✅ **Recoverability**: Backup strategy and procedures documented

With this foundation in place, you can deploy services confidently, knowing that the underlying infrastructure is solid, secure, and well-documented.

**Remember:** This is a living document. Update it as you learn, discover issues, or change your setup. Keep your configuration in Git, document your changes, and maintain your homelab with the same care you put into building it.

Good luck with your homelab journey! 🚀