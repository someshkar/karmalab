
# NixOS Comprehensive Homelab Architecture

**Version:** 2.0  
**Date:** 2025-10-23  
**System:** Intel NUC N150 with 20TB ZFS Storage  
**NixOS Version:** unstable (23.11+)

---

## Executive Summary

This document outlines the complete architecture for a comprehensive self-hosted homelab on NixOS. The system includes 14 integrated services spanning media management, file storage, password management, authentication, and productivity tools. The architecture prioritizes security through VPN isolation for torrenting, native NixOS service integration, proper ZFS dataset organization, and dual network access paths (Tailscale + Cloudflare Tunnels) to bypass CGNAT.

**Key Architectural Decisions:**
1. **Service Priority Tiers**: Critical services (Immich, Nextcloud, Vaultwarden, Jellyfin) deployed first
2. **Hybrid Network Stack**: Docker for Deluge+VPN, native NixOS for all other services
3. **Dual Access Strategy**: Tailscale for admin/private access, Cloudflare Tunnels for family/public services
4. **ZFS Organization**: Dedicated datasets with service-specific optimization and quotas
5. **Security First**: Firewall rules, service isolation, VPN kill-switch, and SSO via Keycloak (future)

---

## Table of Contents

1. [Service Catalog and Priorities](#1-service-catalog-and-priorities)
2. [System Architecture Overview](#2-system-architecture-overview)
3. [Network Architecture](#3-network-architecture)
4. [VPN Isolation Strategy](#4-vpn-isolation-strategy)
5. [ZFS Dataset Structure](#5-zfs-dataset-structure)
6. [Service Integration Architecture](#6-service-integration-architecture)
7. [Port Allocation Plan](#7-port-allocation-plan)
8. [Security Architecture](#8-security-architecture)
9. [Implementation Phases](#9-implementation-phases)
10. [NixOS Configuration Strategy](#10-nixos-configuration-strategy)
11. [Hardware Considerations](#11-hardware-considerations)
12. [Failure Modes and Recovery](#12-failure-modes-and-recovery)

---

## 1. Service Catalog and Priorities

### 1.1 Priority Tier 1: Essential Services

| Service | Purpose | Storage Needs | Criticality |
|---------|---------|---------------|-------------|
| **Immich** | Photo management and backup | 2-4TB (photos + ML models) | ⭐⭐⭐⭐⭐ |
| **Nextcloud** | File sync, calendar, contacts | 1-2TB (documents + shared files) | ⭐⭐⭐⭐⭐ |
| **Vaultwarden** | Password manager (Bitwarden) | 500MB (encrypted vault) | ⭐⭐⭐⭐⭐ |
| **Jellyfin** | Media streaming server | 200GB (metadata + cache) | ⭐⭐⭐⭐⭐ |

**Deploy First:** These are mission-critical services providing core functionality.

### 1.2 Priority Tier 2: Media Automation Stack

| Service | Purpose | Storage Needs | Criticality |
|---------|---------|---------------|-------------|
| **Deluge** | Torrent client (VPN isolated) | 2TB (downloads buffer) | ⭐⭐⭐⭐ |
| **Radarr** | Movie automation | 20GB (database) | ⭐⭐⭐⭐ |
| **Sonarr** | TV show automation | 20GB (database) | ⭐⭐⭐⭐ |
| **Bazarr** | Subtitle automation | 10GB (database + subtitles) | ⭐⭐⭐ |
| **Prowlarr** | Indexer management | 5GB (database) | ⭐⭐⭐⭐ |
| **Jellyseerr** | Media request interface | 5GB (database) | ⭐⭐⭐⭐ |

**Deploy Second:** Media automation chain, dependent on Jellyfin infrastructure.

### 1.3 Priority Tier 3: Experimental/Optional Services

| Service | Purpose | Storage Needs | Criticality |
|---------|---------|---------------|-------------|
| **Keycloak** | SSO/Authentication provider | 5GB (database + config) | ⭐⭐ |
| **Audiobookshelf** | Audiobook management | 500GB (audiobooks) | ⭐⭐ |
| **Microbin** | Pastebin service | 2GB (pastes) | ⭐ |
| **Navidrome** | Music streaming | 500GB (music library) | ⭐⭐ |
| **Radicale** | CalDAV/CardDAV server | 1GB (calendar data) | ⭐ |

**Deploy Third:** After core services are stable, add these for experimentation.

### 1.4 Media Library Storage

| Category | Quota | Growth Rate |
|----------|-------|-------------|
| Movies | 6TB | ~50GB/month |
| TV Shows | 6TB | ~100GB/month |
| Audiobooks | 500GB | ~10GB/month |
| Music | 500GB | ~5GB/month |

---

## 2. System Architecture Overview

### 2.1 High-Level Component Diagram

```
┌────────────────────────────────────────────────────────────────────────┐
│                   External Access (via CGNAT)                          │
│                                                                        │
│   Tailscale VPN          ┌──────┐          Cloudflare Tunnel         │
│   (Private/Admin)        │      │          (Public/Family)            │
│         │                │ CGNAT│                │                    │
│         │                │      │                │                    │
│         └────────────────┴──────┴────────────────┘                    │
└────────────────────────────────┬───────────────────────────────────────┘
                                 │
                    ┌────────────▼──────────────┐
                    │  Home Router/Firewall     │
                    │  192.168.x.1              │
                    └────────────┬──────────────┘
                                 │
                    ┌────────────▼──────────────┐
                    │    NixOS Homelab Server   │
                    │    Intel NUC N150         │
                    │    192.168.x.x            │
                    │                           │
                    │  ┌─────────────────────┐ │
                    │  │  Access Layer       │ │
                    │  │  ┌───────────────┐  │ │
                    │  │  │  Tailscale    │  │ │  Private IP: 100.x.x.x
                    │  │  │  Interface    │  │ │  (Full system access)
                    │  │  └───────────────┘  │ │
                    │  │  ┌───────────────┐  │ │
                    │  │  │  Cloudflared  │  │ │  Tunnels specific services
                    │  │  │  Daemon       │  │ │  (HTTP/HTTPS only)
                    │  │  └───────────────┘  │ │
                    │  └─────────────────────┘ │
                    │                           │
                    │  ┌─────────────────────┐ │
                    │  │  Core Services      │ │
                    │  │  (Native NixOS)     │ │
                    │  │                     │ │
                    │  │  • Immich :2283     │ │  Photos
                    │  │  • Nextcloud :8080  │ │  Files
                    │  │  • Vaultwarden :8000│ │  Passwords
                    │  │  • Jellyfin :8096   │ │  Media
                    │  │  • Radarr :7878     │ │  Movies
                    │  │  • Sonarr :8989     │ │  TV
                    │  │  • Bazarr :6767     │ │  Subtitles
                    │  │  • Prowlarr :9696   │ │  Indexers
                    │  │  • Jellyseerr :5055 │ │  Requests
                    │  │  • Audiobookshelf   │ │  Audiobooks
                    │  │  • Navidrome :4533  │ │  Music
                    │  │  • Radicale :5232   │ │  Cal/Contacts
                    │  │  • Microbin :8084   │ │  Pastebin
                    │  │  • Keycloak :8180   │ │  SSO (future)
                    │  └─────────────────────┘ │
                    │            ▲              │
                    │            │ API/Files    │
                    │            ▼              │
                    │  ┌─────────────────────┐ │
                    │  │  Isolated VPN Layer │ │
                    │  │  (Docker Containers)│ │
                    │  │  ┌───────────────┐  │ │
                    │  │  │   Gluetun     │  │ │  WireGuard VPN
                    │  │  │  (Surfshark)  │◄─┼─┼─ to Surfshark
                    │  │  └───────┬───────┘  │ │
                    │  │          │          │ │
                    │  │  ┌───────▼───────┐  │ │
                    │  │  │    Deluge     │  │ │  Torrents
                    │  │  │   :8112       │  │ │  (VPN Only)
                    │  │  └───────────────┘  │ │
                    │  └─────────────────────┘ │
                    │            ▲              │
                    │            │              │
                    │  ┌─────────▼────────────┐│
                    │  │   Storage Layer      ││
                    │  │   ZFS Pool           ││
                    │  │   storagepool        ││
                    │  │   20TB USB HDD       ││
                    │  └──────────────────────┘│
                    └───────────────────────────┘
```

### 2.2 Data Flow Examples

#### Example 1: Photo Upload (Immich)

```
Mobile Phone ─► Tailscale VPN ─► Immich ─► /data/immich/upload
     │                                          │
     └─────────► ML Processing ─────────────────┘
                      │
                      ▼
                 /data/immich/library
                      │
                      ▼
             Thumbnails Generated
                      │
                      ▼
                 /data/immich/thumbs
```

#### Example 2: Media Request Flow

```
Family Member ─► Cloudflare Tunnel ─► Jellyseerr :5055
                                           │
                    ┌──────────────────────┴──────────────────────┐
                    │                                             │
                    ▼                                             ▼
              Radarr :7878                                  Sonarr :8989
                    │                                             │
                    └─────────► Prowlarr :9696 ◄─────────────────┘
                                      │
                                      ▼ (search indexers)
                                Torrent Found
                                      │
                                      ▼
                                Deluge :8112 (via VPN)
                                      │
                                      ▼
                            /data/media/downloads/complete
                                      │
                    ┌─────────────────┴──────────────────┐
                    ▼                                    ▼
              /data/media/movies              /data/media/tv
                    │                                    │
                    └────────► Jellyfin :8096 ◄──────────┘
                                      │
                                      ▼
                              Family watches
```

#### Example 3: File Sync (Nextcloud)

```
Desktop Client ─► Tailscale ─► Nextcloud :8080 ─► /data/nextcloud/data
                                    │
Mobile Client ─► Cloudflare ────────┘
```

---

## 3. Network Architecture

### 3.1 Network Access Layers

```
┌─────────────────────────────────────────────────────────────────────┐
│                      Access Layer Design                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Layer 1: Local Network (Direct)                                   │
│  • 192.168.x.x/24                                                   │
│  • All services accessible on LAN                                   │
│  • No firewall restrictions (trusted network)                       │
│  • Use for: Initial setup, debugging, family access at home         │
│                                                                     │
│  Layer 2: Tailscale VPN (Private)                                  │
│  • 100.x.x.x/10 (CGNAT space)                                       │
│  • End-to-end encrypted                                             │
│  • Full access to all services and ports                            │
│  • Use for: Admin access, SSH, service management, databases        │
│  • Users: You (admin) + trusted devices                             │
│                                                                     │
│  Layer 3: Cloudflare Tunnel (Public)                               │
│  • Public DNS names (*.yourdomain.com)                              │
│  • Only HTTP/HTTPS services                                         │
│  • DDoS protection + CDN                                            │
│  • Use for: Family access to Jellyfin, Jellyseerr, Immich          │
│  • Users: Family members accessing from anywhere                    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 3.2 Service Accessibility Matrix

| Service | Local LAN | Tailscale | Cloudflare Tunnel | Public Internet |
|---------|-----------|-----------|-------------------|-----------------|
| **Immich** | ✅ :2283 | ✅ All features | ✅ Photo viewing/upload | ❌ |
| **Nextcloud** | ✅ :8080 | ✅ All features | ✅ File sync/sharing | ❌ |
| **Vaultwarden** | ✅ :8000 | ✅ All features | ✅ Password access | ❌ |
| **Jellyfin** | ✅ :8096 | ✅ All features | ✅ Streaming | ❌ |
| **Jellyseerr** | ✅ :5055 | ✅ Admin | ✅ Request interface | ❌ |
| **Radarr** | ✅ :7878 | ✅ Admin only | ❌ | ❌ |
| **Sonarr** | ✅ :8989 | ✅ Admin only | ❌ | ❌ |
| **Bazarr** | ✅ :6767 | ✅ Admin only | ❌ | ❌ |
| **Prowlarr** | ✅ :9696 | ✅ Admin only | ❌ | ❌ |
| **Deluge** | ✅ :8112 | ✅ Admin only | ❌ | ❌ |
| **Audiobookshelf** | ✅ :13378 | ✅ All features | ✅ Listening | ❌ |
| **Navidrome** | ✅ :4533 | ✅ All features | ✅ Music streaming | ❌ |
| **Radicale** | ✅ :5232 | ✅ Cal/Contact sync | ❌ | ❌ |
| **Microbin** | ✅ :8084 | ✅ Admin only | ⚠️ Optional | ❌ |
| **Keycloak** | ✅ :8180 | ✅ Admin only | ❌ | ❌ |
| **SSH** | ✅ :22 | ✅ All access | ❌ | ❌ |

**Legend:**
- ✅ = Accessible
- ❌ = Not accessible (blocked)
- ⚠️ = Optional (decide based on use case)

### 3.3 Tailscale Configuration

```nix
# Enable Tailscale
services.tailscale = {
  enable = true;
  useRoutingFeatures = "server";
};

# Trust Tailscale interface
networking.firewall.trustedInterfaces = [ "tailscale0" ];

# Optional: Enable Tailscale SSH (recommended)
# This provides SSH access even if regular SSH is blocked
```

**Setup Steps:**
1. Install Tailscale: `sudo tailscale up`
2. Authenticate via browser
3. Enable MagicDNS in Tailscale admin console
4. Access server: `http://nuc-server.tail-xxxx.ts.net:PORT`

### 3.4 Cloudflare Tunnel Configuration

```nix
# Enable Cloudflare Tunnel
services.cloudflared = {
  enable = true;
  tunnels = {
    homelab = {
      credentialsFile = "/var/lib/cloudflared/credentials.json";
      default = "http_status:404";
      
      ingress = {
        # Public-facing services for family
        "photos.yourdomain.com" = "http://localhost:2283";      # Immich
        "files.yourdomain.com" = "http://localhost:8080";       # Nextcloud
        "passwords.yourdomain.com" = "http://localhost:8000";   # Vaultwarden
        "watch.yourdomain.com" = "http://localhost:8096";       # Jellyfin
        "request.yourdomain.com" = "http://localhost:5055";     # Jellyseerr
        "audiobooks.yourdomain.com" = "http://localhost:13378"; # Audiobookshelf
        "music.yourdomain.com" = "http://localhost:4533";       # Navidrome
        
        # Optional: Public paste sharing
        # "paste.yourdomain.com" = "http://localhost:8084";     # Microbin
      };
    };
  };
};
```

**Setup Steps:**
1. Create Cloudflare account + add domain
2. Install cloudflared: `sudo cloudflared tunnel login`
3. Create tunnel: `sudo cloudflared tunnel create homelab`
4. Copy credentials to `/var/lib/cloudflared/credentials.json`
5. Configure DNS in Cloudflare dashboard (CNAME to tunnel ID)

### 3.5 Firewall Rules

```nix
networking.firewall = {
  enable = true;
  
  # Allow SSH from anywhere (protected by fail2ban)
  allowedTCPPorts = [ 22 ];
  
  # Trust local interfaces
  trustedInterfaces = [ 
    "tailscale0"  # Tailscale VPN
    "lo"          # Localhost
  ];
  
  # Allow ping for diagnostics
  allowPing = true;
  
  # Log suspicious connections
  logRefusedConnections = true;
  
  # Rate limit SSH
```nix
# Note: SSH rate limiting removed - was causing connection timeouts
# Security is handled by:
# - SSH key-only authentication (PasswordAuthentication = false)
# - Tailscale for remote access (not exposed to internet)
# - fail2ban for brute force protection
};
```

**Firewall Strategy:**
- ✅ SSH open with key-only authentication + fail2ban protected
- ✅ Tailscale interface fully trusted
- ✅ Services bind to `0.0.0.0` but protected by firewall
- ✅ Cloudflare Tunnel connects outbound (no ports needed)
- ❌ No other ports exposed to internet

> **Note:** SSH rate limiting via iptables was removed because it caused connection timeouts when rules accumulated. Key-only authentication + fail2ban provides sufficient protection.

---

## 4. VPN Isolation Strategy

### 4.1 Architecture: Gluetun + Deluge in Docker

**Why This Approach:**
- ✅ True network isolation via Docker network namespace
- ✅ VPN kill-switch prevents non-VPN traffic
- ✅ All other services remain native NixOS
- ✅ Maintains declarative NixOS configuration for core services
- ✅ Proven solution for VPN isolation

```
┌──────────────────────────────────────────────────────────┐
│                    NixOS Host Network                    │
│                 enp1s0: 192.168.x.x/24                   │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │            Docker Bridge Network                   │ │
│  │               172.17.0.0/16                        │ │
│  │                                                    │ │
│  │  ┌──────────────────────────────────────────────┐ │ │
│  │  │          Gluetun Container                   │ │ │
│  │  │          IP: 172.17.0.2                      │ │ │
│  │  │                                              │ │ │
│  │  │  ┌────────────────────────────────────────┐ │ │ │
│  │  │  │   WireGuard Interface (wg0)            │ │ │ │
│  │  │  │   Connected to Surfshark               │ │ │ │
│  │  │  │   VPN IP: 10.14.x.x                    │ │ │ │
│  │  │  └────────────────────────────────────────┘ │ │ │
│  │  │                                              │ │ │
│  │  │  ┌────────────────────────────────────────┐ │ │ │
│  │  │  │   Kill-Switch (iptables)               │ │ │ │
│  │  │  │   - Allow: tun0 (VPN)                  │ │ │ │
│  │  │  │   - Allow: to VPN server only          │ │ │ │
│  │  │  │   - Drop: all other traffic            │ │ │ │
│  │  │  └────────────────────────────────────────┘ │ │ │
│  │  │                                              │ │ │
│  │  │  Exposed Ports:                              │ │ │
│  │  │  • 8112 → Deluge Web UI                     │ │ │
│  │  │  • 58846 → Deluge Daemon (optional)         │ │ │
│  │  └──────────────────────────────────────────────┘ │ │
│  │                        ▲                          │ │
│  │                        │ shares network            │ │
│  │                        │                          │ │
│  │  ┌──────────────────────────────────────────────┐ │ │
│  │  │          Deluge Container                    │ │ │
│  │  │          network_mode: "container:gluetun"   │ │ │
│  │  │          (No separate IP)                    │ │ │
│  │  │                                              │ │ │
│  │  │  All traffic goes through Gluetun's VPN     │ │ │
│  │  │  Download to: /data/media/downloads         │ │ │
│  │  └──────────────────────────────────────────────┘ │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
│  Port Mapping to Host:                                   │
│  Host :8112 → Gluetun :8112 → Deluge Web UI             │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

### 4.2 NixOS Docker Configuration

```nix
# Enable Docker
virtualisation.docker = {
  enable = true;
  autoPrune = {
    enable = true;
    dates = "weekly";
  };
};

# Docker Compose via NixOS
virtualisation.oci-containers = {
  backend = "docker";
  
  containers = {
    gluetun = {
      image = "qmcgaw/gluetun:latest";
      
      environment = {
        VPN_SERVICE_PROVIDER = "surfshark";
        VPN_TYPE = "wireguard";
        WIREGUARD_PRIVATE_KEY = "YOUR_PRIVATE_KEY_HERE";
        WIREGUARD_ADDRESSES = "10.14.0.2/16";
        SERVER_COUNTRIES = "Netherlands";  # Fast server near India
        FIREWALL_VPN_INPUT_PORTS = "8112,58846";
        FIREWALL_OUTBOUND_SUBNETS = "192.168.0.0/16"; # Allow local subnet
        HEALTH_VPN_DURATION_INITIAL = "20s";
        DOT = "off";  # Disable DNS-over-TLS if causing issues
      };
      
      ports = [
        "8112:8112"   # Deluge Web UI
        "58846:58846" # Deluge Daemon
      ];
      
      volumes = [
        "/var/lib/gluetun:/gluetun"
      ];
      
      extraOptions = [
        "--cap-add=NET_ADMIN"
        "--device=/dev/net/tun"
        "--restart=always"
      ];
    };
    
    deluge = {
      image = "lscr.io/linuxserver/deluge:latest";
      
      dependsOn = [ "gluetun" ];
      
      environment = {
        PUID = "994";  # Will create dedicated user
        PGID = "992";  # Will create dedicated group
        TZ = "Asia/Kolkata";
        DELUGE_LOGLEVEL = "info";
      };
      
      volumes = [
        "/var/lib/media-services/deluge/config:/config"
        "/data/media/downloads:/downloads"
        "/data/media/downloads/complete:/downloads/complete"
        "/data/media/downloads/incomplete:/downloads/incomplete"
      ];
      
      extraOptions = [
        "--network=container:gluetun"  # Share Gluetun's network
        "--restart=always"
      ];
    };
  };
};

# Create deluge user/group
users.users.deluge = {
  uid = 994;
  group = "deluge";
  isSystemUser = true;
};

users.groups.deluge = {
  gid = 992;
};
```

### 4.3 Verification Commands

```bash
# Check VPN connection
docker logs gluetun | grep "Wireguard is up"

# Verify IP (should show VPN IP, NOT your home IP)
docker exec gluetun wget -qO- ifconfig.me

# Test kill-switch (should fail gracefully)
docker exec gluetun killall wireguard
docker logs deluge  # Should show connection errors

# Test Deluge web UI
curl http://localhost:8112  # Should return Deluge web interface

# Monitor VPN health
watch -n 5 'docker exec gluetun wget -qO- http://localhost:9999'
```

---

## 5. ZFS Dataset Structure

### 5.1 Complete Dataset Hierarchy

```
storagepool/ (20TB USB HDD - ~18.5TB usable)
│
├── data/                          # General data (existing)
│   └── mountpoint: /data
│
├── immich/                        # Photo management
│   ├── library/                   # Original photos
│   ├── upload/                    # Upload buffer
│   ├── thumbs/                    # Thumbnails (disable snapshots)
│   ├── profile/                   # Profile pictures
│   ├── encoded-video/             # Transcoded videos
│   └── database/                  # PostgreSQL data
│
├── nextcloud/                     # File sync & collaboration
│   ├── data/                      # User files
│   ├── database/                  # PostgreSQL data
│   └── config/                    # App configuration
│
├── vaultwarden/                   # Password manager
│   └── data/                      # Encrypted vault + attachments
│
├── media/                         # Media server stack
│   ├── movies/                    # Radarr managed
│   ├── tv/                        # Sonarr managed
│   ├── audiobooks/                # Audiobookshelf
│   ├── music/                     # Navidrome
│   ├── downloads/                 # Deluge downloads
│   │   ├── incomplete/            # Active downloads
│   │   └── complete/              # Finished downloads
│   └── jellyfin-cache/            # Transcoding temp
│
├── services/                      # Service configurations
│   ├── jellyfin/
│   │   ├── config/
│   │   └── metadata/
│   ├── radarr/config/
│   ├── sonarr/config/
│   ├── bazarr/config/
│   ├── prowlarr/config/
│   ├── jellyseerr/config/
│   ├── deluge/config/
│   ├── audiobookshelf/config/
│   ├── navidrome/config/
│   ├── radicale/config/
│   ├── microbin/config/
│   └── keycloak/
│       ├── config/
│       └── database/
│
└── backups/                       # Automated backups
    ├── configs/                   # Daily config backups
    ├── databases/                 # Database dumps
    └── immich/                    # Immich backup
```

### 5.2 Dataset Creation Script

```bash
#!/usr/bin/env bash
# Create all ZFS datasets for homelab

set -e  # Exit on error

POOL="storagepool"

echo "Creating ZFS datasets for comprehensive homelab..."

# ===== IMMICH (Photos) =====

echo "Creating Immich datasets..."
zfs create $POOL/immich
zfs set mountpoint=/data/immich $POOL/immich
zfs set compression=lz4 $POOL/immich
zfs set atime=off $POOL/immich

# Immich subdatasets
zfs create $POOL/immich/library
zfs set quota=3T $POOL/immich/library
zfs set recordsize=1M $POOL/immich/library

zfs create $POOL/immich/upload
zfs set quota=500G $POOL/immich/upload
zfs set recordsize=1M $POOL/immich/upload

zfs create $POOL/immich/thumbs
zfs set quota=200G $POOL/immich/thumbs
zfs set recordsize=128K $POOL/immich/thumbs
zfs set com.sun:auto-snapshot=false $POOL/immich/thumbs

zfs create $POOL/immich/encoded-video
zfs set quota=200G $POOL/immich/encoded-video
zfs set recordsize=1M $POOL/immich/encoded-video

zfs create $POOL/immich/database
zfs set quota=50G $POOL/immich/database
zfs set recordsize=8K $POOL/immich/database  # Optimized for PostgreSQL

# ===== NEXTCLOUD =====
echo "Creating Nextcloud datasets..."
zfs create $POOL/nextcloud
zfs set mountpoint=/data/nextcloud $POOL/nextcloud
zfs set compression=lz4 $POOL/nextcloud
zfs set atime=off $POOL/nextcloud

zfs create $POOL/nextcloud/data
zfs set quota=2T $POOL/nextcloud/data
zfs set recordsize=1M $POOL/nextcloud/data

zfs create $POOL/nextcloud/database
zfs set quota=50G $POOL/nextcloud/database
zfs set recordsize=8K $POOL/nextcloud/database

zfs create $POOL/nextcloud/config
zfs set quota=5G $POOL/nextcloud/config
zfs set recordsize=128K $POOL/nextcloud/config

# ===== VAULTWARDEN =====
echo "Creating Vaultwarden dataset..."
zfs create $POOL/vaultwarden
zfs set mountpoint=/data/vaultwarden $POOL/vaultwarden
zfs set quota=2G $POOL/vaultwarden
zfs set recordsize=128K $POOL/vaultwarden
zfs set compression=lz4 $POOL/vaultwarden

# ===== MEDIA =====
echo "Creating media datasets..."
zfs create $POOL/media
zfs set mountpoint=/data/media $POOL/media
zfs set compression=lz4 $POOL/media
zfs set atime=off $POOL/media

# Movies
zfs create $POOL/media/movies
zfs set quota=6T $POOL/media/movies
zfs set recordsize=1M $POOL/media/movies
zfs set com.sun:auto-snapshot:frequent=false $POOL/media/movies
zfs set com.sun:auto-snapshot:hourly=false $POOL/media/movies

# TV Shows
zfs create $POOL/media/tv
zfs set quota=6T $POOL/media/tv
zfs set recordsize=1M $POOL/media/tv
zfs set com.sun:auto-snapshot:frequent=false $POOL/media/tv
zfs set com.sun:auto-snapshot:hourly=false $POOL/media/tv

# Audiobooks
zfs create $POOL/media/audiobooks
zfs set quota=500G $POOL/media/audiobooks
zfs set recordsize=1M $POOL/media/audiobooks

# Music
zfs create $POOL/media/music
zfs set quota=500G $POOL/media/music
zfs set recordsize=1M $POOL/media/music

# Downloads
zfs create $POOL/media/downloads
zfs set quota=2T $POOL/media/downloads
zfs set recordsize=1M $POOL/media/downloads

zfs create $POOL/media/downloads/incomplete
zfs create $POOL/media/downloads/complete

# Jellyfin cache
zfs create $POOL/media/jellyfin-cache
zfs set quota=100G $POOL/media/jellyfin-cache
zfs set sync=disabled $POOL/media/jellyfin-cache
zfs set com.sun:auto-snapshot=false $POOL/media/jellyfin-cache

# ===== SERVICES =====
echo "Creating service config datasets..."
zfs create $POOL/services
zfs set mountpoint=/var/lib/media-services $POOL/services
zfs set compression=lz4 $POOL/services
zfs set atime=off $POOL/services

# Service configs (all 20GB max except Keycloak)
for service in jellyfin radarr sonarr bazarr prowlarr jellyseerr deluge audiobookshelf navidrome radicale microbin; do
  zfs create $POOL/services/$service
  zfs set quota=20G $POOL/services/$service
  zfs set recordsize=128K $POOL/services/$service
done

# Keycloak (needs more for database)
zfs create $POOL/services/keycloak
zfs set quota=50G $POOL/services/keycloak
zfs set recordsize=8K $POOL/services/keycloak

# ===== BACKUPS =====
echo "Creating backup datasets..."
zfs create $POOL/backups
zfs set mountpoint=/backups $POOL/backups
zfs set quota=200G $POOL/backups
zfs set compression=lz4 $POOL/backups

zfs create $POOL/backups/configs
zfs create $POOL/backups/databases
zfs create $POOL/backups/immich

echo "ZFS datasets created successfully!"
echo "Run 'zfs list -o name,used,avail,quota,mountpoint' to verify"
```

### 5.3 Storage Allocation Summary

| Category | Quota | Actual Use Est. | Percentage | Priority |
|----------|-------|-----------------|------------|----------|
| **Immich Photos** | 3.95TB | 2-3TB | 21% | ⭐⭐⭐⭐⭐ |
| **Nextcloud Files** | 2.05TB | 1-1.5TB | 11% | ⭐⭐⭐⭐⭐ |
| **Movies** | 6TB | 4-5TB | 32% | ⭐⭐⭐⭐ |
| **TV Shows** | 6TB | 4-5TB | 32% | ⭐⭐⭐⭐ |
| **Audiobooks** | 500GB | 200-300GB | 3% | ⭐⭐ |
| **Music** | 500GB | 200-300GB | 3% | ⭐⭐ |
| **Downloads Buffer** | 2TB | 500GB-1TB | 11% | ⭐⭐⭐⭐ |
| **Service Configs** | ~0.3TB | 50-100GB | 2% | ⭐⭐⭐⭐⭐ |
| **Vaultwarden** | 2GB | <500MB | <1% | ⭐⭐⭐⭐⭐ |
| **Backups** | 200GB | 50-100GB | 1% | ⭐⭐⭐⭐⭐ |
| **Reserved (ZFS)** | ~2TB | N/A | 11% | Critical |
| **TOTAL** | ~18.5TB | ~13-16TB | 100% | |

**Notes on Quotas:**
- Quotas are **soft limits** - ZFS will warn but not block writes immediately
- Monitor with: `zfs list -o name,used,avail,refer,quota`
- Adjust quotas as needed: `sudo zfs set quota=7T storagepool/media/movies`
- Keep 2TB free for ZFS performance (10-20% recommended)

### 5.4 Snapshot Strategy by Dataset

| Dataset | Frequent (15m) | Hourly | Daily | Weekly | Monthly | Rationale |
|---------|---------------|--------|-------|--------|---------|-----------|
| immich/library | ❌ | ❌ | ✅ (7) | ✅ (4) | ✅ (12) | Photos rarely deleted |
| immich/database | ✅ (4) | ✅ (24) | ✅ (7) | ✅ (4) | ✅ (12) | Critical metadata |
| nextcloud/data | ❌ | ✅ (24) | ✅ (7) | ✅ (4) | ✅ (12) | User file protection |
| nextcloud/database | ✅ (4) | ✅ (24) | ✅ (7) | ✅ (4) | ✅ (12) | Critical data |
| vaultwarden | ✅ (4) | ✅ (24) | ✅ (7) | ✅ (4) | ✅ (12) | Password vault |
| media/* | ❌ | ❌ | ✅ (3) | ✅ (4) | ❌ | Can re-download |
| services/* | ✅ (4) | ✅ (24) | ✅ (7) | ✅ (4) | ✅ (6) | Config protection |
| *-cache | ❌ | ❌ | ❌ | ❌ | ❌ | Temporary data |

---

## 6. Service Integration Architecture

### 6.1 Database Strategy

**PostgreSQL Instances:**
- **Immich**: Dedicated PostgreSQL instance (complex queries, heavy use)
- **Nextcloud**: Dedicated PostgreSQL instance (large database)
- **Keycloak**: Dedicated PostgreSQL instance (identity data)

**SQLite Databases:**
- Radarr, Sonarr, Bazarr, Prowlarr, Jellyseerr (native *arr stack format)
- Jellyfin (native format)
- Vaultwarden (SQLite by default, encrypted)
- Navidrome, Audiobookshelf (embedded)

**NixOS PostgreSQL Configuration:**

```nix
services.postgresql = {
  enable = true;
  package = pkgs.postgresql_15;
  
  ensureDatabases = [
    "immich"
    "nextcloud"
    "keycloak"
  ];
  
  ensureUsers = [
    {
      name = "immich";
      ensureDBOwnership = true;
    }
    {
      name = "nextcloud";
      ensureDBOwnership = true;
    }
    {
      name = "keycloak";
      ensureDBOwnership = true;
    }
  ];
  
  # Performance tuning for NUC N150
  settings = {
    max_connections = 100;
    shared_buffers = "512MB";  # 25% of 2GB RAM allocated to PostgreSQL
    effective_cache_size = "1536MB";
    maintenance_work_mem = "128MB";
    checkpoint_completion_target = 0.9;
    wal_buffers = "16MB";
    default_statistics_target = 100;
    random_page_cost = 1.1;  # For SSD/modern storage
    effective_io_concurrency = 200;
    work_mem = "2621kB";
    min_wal_size = "1GB";
    max_wal_size = "4GB";
  };
};
```

### 6.2 User and Group Management

```nix
# Media group (shared access to media files)
users.groups.media = {
  gid = 990;
};

# Service users
users.users = {
  jellyfin = {
    isSystemUser = true;
    group = "jellyfin";
    extraGroups = [ "media" "video" "render" ];  # Hardware transcoding
  };
  
  radarr = {
    isSystemUser = true;
    group = "radarr";
    extraGroups = [ "media" ];
  };
  
  sonarr = {
    isSystemUser = true;
    group = "sonarr";
    extraGroups = [ "media" ];
  };
  
  bazarr = {
    isSystemUser = true;
    group = "bazarr";
    extraGroups = [ "media" ];
  };
  
  prowlarr = {
    isSystemUser = true;
    group = "prowlarr";
  };
  
  jellyseerr = {
    isSystemUser = true;
    group = "jellyseerr";
  };
  
  deluge = {
    uid = 994;
    isSystemUser = true;
    group = "deluge";
    extraGroups = [ "media" ];
  };
  
  immich = {
    isSystemUser = true;
    group = "immich";
  };
  
  nextcloud = {
    isSystemUser = true;
    group = "nextcloud";
  };
  
  vaultwarden = {
    isSystemUser = true;
    group = "vaultwarden";
  };
};
```

### 6.3 Directory Permissions

```bash
# Media directories (shared)
sudo chown -R root:media /data/media/movies
sudo chown -R root:media /data/media/tv
sudo chmod -R 775 /data/media/movies
sudo chmod -R 775 /data/media/tv

# Downloads (deluge writes, arrs read)
sudo chown -R deluge:media /data/media/downloads
sudo chmod -R 775 /data/media/downloads

# Service configs (service-specific)
sudo chown -R jellyfin:jellyfin /var/lib/media-services/jellyfin
sudo chown -R radarr:radarr /var/lib/media-services/radarr
sudo chown -R sonarr:sonarr /var/lib/media-services/sonarr

# Immich (dedicated)
sudo chown -R immich:immich /data/immich
sudo chmod -R 750 /data/immich

# Nextcloud (dedicated)
sudo chown -R nextcloud:nextcloud /data/nextcloud
sudo chmod -R 750 /data/nextcloud

# Vaultwarden (highly restricted)
sudo chown -R vaultwarden:vaultwarden /data/vaultwarden
sudo chmod -R 700 /data/vaultwarden
```

### 6.4 Service Communication Patterns

**API Authentication Matrix:**

| From → To | Method | Auth | Config Location |
|-----------|--------|------|-----------------|
| Jellyseerr → Radarr | HTTP API | API Key | Jellyseerr settings |
| Jellyseerr → Sonarr | HTTP API | API Key | Jellyseerr settings |
| Radarr → Prowlarr | HTTP API | API Key | Auto-sync from Prowlarr |
| Sonarr → Prowlarr | HTTP API | API Key | Auto-sync from Prowlarr |
| Radarr → Deluge | HTTP API | Password | Radarr settings |
| Sonarr → Deluge | HTTP API | Password | Sonarr settings |
| Bazarr → Radarr | HTTP API | API Key | Bazarr settings |
| Bazarr → Sonarr | HTTP API | API Key | Bazarr settings |
| Radarr → Jellyfin | HTTP API | API Key | Radarr connect settings |
| Sonarr → Jellyfin | HTTP API | API Key | Sonarr connect settings |
| Immich → PostgreSQL | TCP :5432 | Password | immich.env |
| Nextcloud → PostgreSQL | TCP :5432 | Password | config.php |
| Keycloak → PostgreSQL | TCP :5432 | Password | keycloak.conf |

**Webhooks:**
- Deluge → Radarr/Sonarr: Download completion notification
- Radarr/Sonarr → Jellyfin: Library update trigger

### 6.5 Shared Library Structure

```
/data/media/
├── movies/                    # Radarr manages, Jellyfin reads
│   ├── Movie Name (2020)/
│   │   ├── Movie Name (2020) - 1080p.mkv
│   │   └── Movie Name (2020).nfo
│   └── ...
│
├── tv/                        # Sonarr manages, Jellyfin reads
│   ├── Show Name (2020)/
│   │   ├── Season 01/
│   │   │   ├── Show Name - S01E01 - Episode.mkv
│   │   │   └── Show Name - S01E01 - Episode.srt
│   │   └── ...
│   └── ...
│
├── audiobooks/                # Audiobookshelf manages
│   ├── Author Name/
│   │   └── Book Title/
│   │       ├── Chapter 01.m4b
│   │       └── cover.jpg
│   └── ...
│
├── music/                     # Navidrome reads
│   ├── Artist/
│   │   └── Album/
│   │       ├── 01 - Track.flac
│   │       └── cover.jpg
│   └── ...
│
└── downloads/                 # Deluge writes, Arrs move
    ├── incomplete/            # Active downloads
    └── complete/              # Ready for import
        ├── movies/
        └── tv/
```

---

## 7. Port Allocation Plan

### 7.1 Complete Port Map

| Service | Port | Protocol | Bind | Access | Purpose |
|---------|------|----------|------|--------|---------|
| **SSH** | 22 | TCP | 0.0.0.0 | LAN + Tailscale | System access |
| **Immich** | 2283 | TCP | 0.0.0.0 | LAN + Tailscale + CF | Photo web UI |
| **Immich ML** | 3003 | TCP | 127.0.0.1 | Localhost | ML processing |
| **Vaultwarden** | 8000 | TCP | 0.0.0.0 | LAN + Tailscale + CF | Password vault |
| **Vaultwarden WS** | 3012 | TCP | 127.0.0.1 | Localhost | WebSocket |
| **Radicale** | 5232 | TCP | 0.0.0.0 | LAN + Tailscale | CalDAV/CardDAV |
| **Nextcloud** | 8080 | TCP | 0.0.0.0 | LAN + Tailscale + CF | File sync |
| **PostgreSQL** | 5432 | TCP | 127.0.0.1 | Localhost | Database |
| **Radarr** | 7878 | TCP | 0.0.0.0 | LAN + Tailscale | Movie management |
| **Sonarr** | 8989 | TCP | 0.0.0.0 | LAN + Tailscale | TV management |
| **Bazarr** | 6767 | TCP | 0.0.0.0 | LAN + Tailscale | Subtitle management |
| **Prowlarr** | 9696 | TCP | 0.0.0.0 | LAN + Tailscale | Indexer management |
| **Jellyseerr** | 5055 | TCP | 0.0.0.0 | LAN + Tailscale + CF | Media requests |
| **Deluge Web** | 8112 | TCP | 0.0.0.0 | LAN + Tailscale | Torrent web UI |
| **Deluge Daemon** | 58846 | TCP | 127.0.0.1 | Localhost | Torrent daemon |
| **Jellyfin** | 8096 | TCP | 0.0.0.0 | LAN + Tailscale + CF | Media streaming |
| **Jellyfin HTTPS** | 8920 | TCP | 0.0.0.0 | LAN + Tailscale | HTTPS (optional) |
| **Audiobookshelf** | 13378 | TCP | 0.0.0.0 | LAN + Tailscale + CF | Audiobook streaming |
| **Navidrome** | 4533 | TCP | 0.0.0.0 | LAN + Tailscale + CF | Music streaming |
| **Microbin** | 8084 | TCP | 0.0.0.0 | LAN + Tailscale | Pastebin |
| **Keycloak** | 8180 | TCP | 127.0.0.1 | Localhost + Tailscale | SSO/Identity |
| **Keycloak Admin** | 9990 | TCP | 127.0.0.1 | Localhost | Admin console |

**Legend:**
- **0.0.0.0** = Binds to all interfaces (protected by firewall)
- **127.0.0.1** = Localhost only (internal services)
- **LAN** = Accessible on local network
- **Tailscale** = Accessible via VPN
- **CF** = Exposed via Cloudflare Tunnel

### 7.2 Port Conflict Prevention

**Reserved Ranges:**
- 1-1000: System/well-known ports (avoid)
- 2000-3000: Immich stack
- 4000-5000: Music/Calendar services
- 5000-6000: Media request services
- 6000-7000: Subtitle services
- 7000-8000: Movie services  
- 8000-9000: Core services (Vaultwarden, Nextcloud, TV, Jellyfin)
- 9000-10000: Indexer/monitoring
- 13000-14000: Audiobook services

### 7.3 Firewall Configuration

```nix
networking.firewall = {
  enable = true;
  
  # Only SSH exposed to internet
  allowedTCPPorts = [ 22 ];
  
  # Trust local interfaces
  trustedInterfaces = [ 
    "tailscale0"
    "lo"
    "docker0"  # For Docker networking
  ];
  
  # Allow ping
  allowPing = true;
  
  # Log refused connections
  logRefusedConnections = true;
  
  # Note: SSH rate limiting removed - was causing connection timeouts
  # Security is handled by key-only auth + fail2ban
};

# fail2ban for additional protection
services.fail2ban = {
  enable = true;
  maxretry = 5;
  bantime = "1h";
  
  jails = {
    sshd = {
      enabled = true;
      port = "22";
    };
  };
};
```

---

## 8. Security Architecture

### 8.1 Defense in Depth Layers

```
┌─────────────────────────────────────────────────────────────────┐
│ Layer 1: Network Perimeter                                      │
│ • Home router firewall                                          │
│ • CGNAT (no inbound connections possible)                       │
│ • Cloudflare DDoS protection                                    │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Layer 2: NixOS Host Firewall                                    │
│ • Only SSH port 22 open                                         │
│ • Rate limiting on SSH                                          │
│ • fail2ban active                                               │
│ • Tailscale interface trusted                                   │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Layer 3: Service Isolation                                      │
│ • Dedicated users/groups per service                            │
│ • Restricted file permissions                                   │
│ • Services bind to localhost where appropriate                  │
│ • Docker network isolation for VPN                              │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Layer 4: Application Security                                   │
│ • API key authentication between services                       │
│ • User authentication for web UIs                               │
│ • HTTPS via Cloudflare (TLS termination)                        │
│ • Vaultwarden encryption at rest                                │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Layer 5: Data Protection                                        │
│ • ZFS snapshots (recovery from accidents/ransomware)            │
│ • PostgreSQL backups                                            │
│ • Config backups to /backups                                    │
│ • Off-site backup strategy (manual/future automation)           │
└─────────────────────────────────────────────────────────────────┘
```

### 8.2 Secrets Management

**Sensitive Data:**
- Database passwords
- API keys
- Surfshark VPN credentials
- Cloudflare tunnel token

**Storage Strategy:**

```nix
# Option 1: sops-nix (Recommended for production)
# Install: nix-shell -p sops
# Encrypt: sops secrets.yaml
# Use in config: config.sops.secrets.surfshark-key.path

# Option 2: Plain files (Acceptable for homelab)
# Store in: /var/secrets/
# Permissions: 600 (root only)
# Reference in config:
environment.etc."surfshark-key" = {
  source = /var/secrets/surfshark-private-key;
  mode = "0400";
};

# Option 3: Age encryption
age.secrets.surfshark = {
  file = ./secrets/surfshark.age;
  owner = "root";
  mode = "0400";
};
```

### 8.3 Backup Strategy

**Critical Data (Daily):**
- Vaultwarden vault → `/backups/vaultwarden/`
- PostgreSQL databases → `/backups/databases/`
- Service configs → `/backups/configs/`
- Immich database → `/backups/immich/`

**Backup Script:**

```bash
#!/usr/bin/env bash
# /usr/local/bin/backup-critical-data.sh

BACKUP_ROOT="/backups"
DATE=$(date +%Y%m%d)

# PostgreSQL dumps
sudo -u postgres pg_dump immich > "$BACKUP_ROOT/databases/immich-$DATE.sql"
sudo -u postgres pg_dump nextcloud > "$BACKUP_ROOT/databases/nextcloud-$DATE.sql"
sudo -u postgres pg_dump keycloak > "$BACKUP_ROOT/databases/keycloak-$DATE.sql"

# Compress
gzip "$BACKUP_ROOT/databases/"*-$DATE.sql

# Vaultwarden
cp -r /data/vaultwarden/data "$BACKUP_ROOT/vaultwarden/vault-$DATE"

# Service configs (use rsync for incremental)
rsync -av /var/lib/media-services/ "$BACKUP_ROOT/configs/services-$DATE/"

# Keep only last 7 days
find "$BACKUP_ROOT" -name "*-20*" -mtime +7 -delete

echo "Backup completed: $(date)"
```

**Cron Job:**

```nix
services.cron = {
  enable = true;
  systemCronJobs = [
    "0 2 * * * root /usr/local/bin/backup-critical-data.sh >> /var/log/backups.log 2>&1"
  ];
};
```

### 8.4 SSH Hardening

```nix
services.openssh = {
  enable = true;
  settings = {
    PasswordAuthentication = false;
    PermitRootLogin = "no";
    AllowUsers = [ "somesh" ];
    
    # Strong key exchange
    KexAlgorithms = [
      "curve25519-sha256"
      "curve25519-sha256@libssh.org"
    ];
    
    # Modern ciphers
    Ciphers = [
      "chacha20-poly1305@openssh.com"
      "aes256-gcm@openssh.com"
    ];
    
    # Strong MACs
    Macs = [
      "hmac-sha2-512-etm@openssh.com"
      "hmac-sha2-256-etm@openssh.com"
    ];
    
    MaxAuthTries = 3;
    ClientAliveInterval = 300;
    ClientAliveCountMax = 2;
  };
  
  hostKeys = [
    {
      path = "/etc/ssh/ssh_host_ed25519_key";
      type = "ed25519";
    }
  ];
};
```

### 8.5 Security Checklist

**Pre-Deployment:**
- [ ] SSH keys configured (no password auth)
- [ ] Firewall enabled and tested
- [ ] fail2ban configured
- [ ] Tailscale authenticated
- [ ] All secrets stored securely
- [ ] Default passwords changed

**Post-Deployment:**
- [ ] All services have strong passwords/API keys
- [ ] Vaultwarden master password set
- [ ] Immich admin account secured
- [ ] Nextcloud admin account secured  
- [ ] Jellyfin admin account secured
- [ ] Radarr/Sonarr API keys rotated
- [ ] Prowlarr API key set
- [ ] Deluge password changed from default

**Ongoing:**
- [ ] Monthly: Review firewall logs
- [ ] Monthly: Check fail2ban bans
- [ ] Quarterly: Update all services
- [ ] Quarterly: Test backup restoration
- [ ] Annually: Rotate API keys
- [ ] Annually: Review user access

---

## 9. Implementation Phases

### 9.1 Phase 0: Infrastructure Foundation (Week 1)

**Goal:** Prepare system for service deployment

```
Day 1-2: Core Infrastructure
├── Enable and configure firewall
├── Install and configure fail2ban  
├── Set up Tailscale VPN
├── Configure ZFS auto-snapshots
├── Create all ZFS datasets
└── Test dataset permissions

Day 3-4: Network Access
├── Install Cloudflare Tunnel
├── Authenticate tunnel
├── Test Tailscale connectivity
├── Document IP addresses
└── Set up DNS names

Day 5-7: Database & Docker
├── Configure PostgreSQL
├── Enable Docker
├── Set up Gluetun + Deluge
├── Test VPN isolation
└── Create backup scripts
```

**Verification:**
- [ ] Can SSH via Tailscale
- [ ] Firewall blocks unexpected ports
- [ ] ZFS snapshots running
-
[ ] Docker and Gluetun running
- [ ] Deluge accessible on port 8112
- [ ] VPN IP verified (not home IP)

### 9.2 Phase 1: Critical Services (Week 2-3)

**Goal:** Deploy essential services for daily use

**Priority Order:**

```
1. Vaultwarden (Day 1-2)
   ├── Configure service
   ├── Set up backups
   ├── Create admin account
   ├── Add to Cloudflare Tunnel
   └── Test password sync

2. Immich (Day 3-5)
   ├── Deploy PostgreSQL database
   ├── Configure Immich server
   ├── Set up machine learning
   ├── Configure mobile upload
   ├── Add to Cloudflare Tunnel
   └── Import existing photos

3. Nextcloud (Day 6-8)
   ├── Deploy PostgreSQL database
   ├── Configure Nextcloud
   ├── Set up cron jobs
   ├── Configure desktop/mobile clients
   ├── Add to Cloudflare Tunnel
   └── Migrate existing files

4. Jellyfin (Day 9-10)
   ├── Configure service
   ├── Add media libraries
   ├── Configure hardware transcoding
   ├── Add to Cloudflare Tunnel
   ├── Create family accounts
   └── Test streaming
```

**Verification:**
- [ ] Vaultwarden syncing passwords
- [ ] Immich backing up photos
- [ ] Nextcloud syncing files
- [ ] Jellyfin streaming media
- [ ] All accessible via Cloudflare
- [ ] All accessible via Tailscale

### 9.3 Phase 2: Media Automation (Week 4-5)

**Goal:** Complete media automation pipeline

```
1. Prowlarr (Day 1)
   ├── Configure indexers
   ├── Test indexer connections
   └── Generate API keys

2. Radarr (Day 2)
   ├── Connect to Prowlarr
   ├── Configure quality profiles
   ├── Set root folder: /data/media/movies
   ├── Connect to Deluge
   └── Test search and download

3. Sonarr (Day 3)
   ├── Connect to Prowlarr
   ├── Configure quality profiles
   ├── Set root folder: /data/media/tv
   ├── Connect to Deluge
   └── Test search and download

4. Bazarr (Day 4)
   ├── Connect to Radarr
   ├── Connect to Sonarr
   ├── Configure subtitle providers
   └── Test subtitle download

5. Jellyseerr (Day 5-6)
   ├── Connect to Radarr
   ├── Connect to Sonarr
   ├── Connect to Jellyfin (optional)
   ├── Add to Cloudflare Tunnel
   ├── Create family accounts
   └── Test request workflow

6. Integration Testing (Day 7)
   ├── End-to-end: Request → Download → Import → Stream
   ├── Verify VPN isolation
   ├── Check permissions
   └── Test automation
```

**Verification:**
- [ ] Can request media via Jellyseerr
- [ ] Prowlarr finds content
- [ ] Radarr/Sonarr send to Deluge
- [ ] Deluge downloads via VPN only
- [ ] Media auto-imports to libraries
- [ ] Jellyfin detects new content
- [ ] Subtitles auto-download

### 9.4 Phase 3: Additional Services (Week 6-7)

**Goal:** Deploy experimental/optional services

```
1. Audiobookshelf (Day 1-2)
   ├── Configure service
   ├── Import audiobook library
   ├── Add to Cloudflare Tunnel
   └── Test playback

2. Navidrome (Day 3)
   ├── Configure service
   ├── Scan music library
   ├── Add to Cloudflare Tunnel
   └── Test with Subsonic client

3. Radicale (Day 4)
   ├── Configure CalDAV/CardDAV
   ├── Set up authentication
   ├── Test calendar sync
   └── Test contact sync

4. Microbin (Day 5)
   ├── Configure service
   ├── Test paste creation
   └── (Optional) Add to Cloudflare

5. Keycloak (Day 6-7) [Future]
   ├── Deploy PostgreSQL database
   ├── Configure Keycloak
   ├── Create realm
   ├── Test authentication
   └── Plan service integration
```

**Verification:**
- [ ] Audiobooks playing
- [ ] Music streaming working
- [ ] Calendar syncing
- [ ] Pastebin functional
- [ ] Keycloak authenticating (if deployed)

### 9.5 Service Deployment Dependencies

```
graph TD
    A[Infrastructure: Firewall, Tailscale, ZFS] --> B[PostgreSQL]
    A --> C[Docker + Gluetun]
    C --> D[Deluge]
    B --> E[Immich]
    B --> F[Nextcloud]
    A --> G[Vaultwarden]
    A --> H[Jellyfin]
    D --> I[Prowlarr]
    I --> J[Radarr]
    I --> K[Sonarr]
    J --> L[Jellyseerr]
    K --> L
    J --> M[Bazarr]
    K --> M
    H --> L
    A --> N[Audiobookshelf]
    A --> O[Navidrome]
    A --> P[Radicale]
    A --> Q[Microbin]
    B --> R[Keycloak]
```

---

## 10. NixOS Configuration Strategy

### 10.1 Configuration File Organization

```
/etc/nixos/
├── flake.nix                    # Flake entry point
├── flake.lock                   # Locked dependencies
├── configuration.nix            # Main config (imports modules)
├── hardware-configuration.nix   # Auto-generated hardware config
├── disko-config.nix            # Disk partitioning
│
├── modules/                     # Reusable modules
│   ├── networking.nix           # Firewall, Tailscale, Cloudflare
│   ├── zfs.nix                  # ZFS configuration
│   ├── docker.nix               # Docker + VPN stack
│   ├── databases.nix            # PostgreSQL configuration
│   └── users.nix                # User/group management
│
├── services/                    # Service-specific configs
│   ├── tier1-critical/
│   │   ├── immich.nix
│   │   ├── nextcloud.nix
│   │   ├── vaultwarden.nix
│   │   └── jellyfin.nix
│   ├── tier2-media/
│   │   ├── radarr.nix
│   │   ├── sonarr.nix
│   │   ├── bazarr.nix
│   │   ├── prowlarr.nix
│   │   └── jellyseerr.nix
│   └── tier3-optional/
│       ├── audiobookshelf.nix
│       ├── navidrome.nix
│       ├── radicale.nix
│       ├── microbin.nix
│       └── keycloak.nix
│
└── secrets/                     # Encrypted secrets (gitignored)
    ├── surfshark-key.age
    ├── cloudflare-token.age
    └── database-passwords.age
```

### 10.2 Main Configuration Structure

**[`configuration.nix`](configuration.nix:1):**

```nix
{ config, pkgs, inputs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disko-config.nix
    
    # Core modules
    ./modules/networking.nix
    ./modules/zfs.nix
    ./modules/docker.nix
    ./modules/databases.nix
    ./modules/users.nix
    
    # Phase 1: Critical services
    ./services/tier1-critical/immich.nix
    ./services/tier1-critical/nextcloud.nix
    ./services/tier1-critical/vaultwarden.nix
    ./services/tier1-critical/jellyfin.nix
    
    # Phase 2: Media automation (comment out until ready)
    # ./services/tier2-media/prowlarr.nix
    # ./services/tier2-media/radarr.nix
    # ./services/tier2-media/sonarr.nix
    # ./services/tier2-media/bazarr.nix
    # ./services/tier2-media/jellyseerr.nix
    
    # Phase 3: Optional services (comment out until ready)
    # ./services/tier3-optional/audiobookshelf.nix
    # ./services/tier3-optional/navidrome.nix
    # ./services/tier3-optional/radicale.nix
  ];

  # System configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  
  networking.hostName = "nuc-server";
  networking.hostId = "b291ad23";  # Required for ZFS
  
  time.timeZone = "Asia/Kolkata";
  
  # Allow unfree packages (for some services)
  nixpkgs.config.allowUnfree = true;
  
  # Enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  
  # System packages
  environment.systemPackages = with pkgs; [
    # System tools
    htop
    btop
    iotop
    ncdu
    tree
    
    # Network tools
    curl
    wget
    dig
    mtr
    
    # Development
    git
    vim
    
    # ZFS tools
    zfs-prune-snapshots
    
    # Docker tools
    docker-compose
  ];
  
  # State version
  system.stateVersion = "23.11";
}
```

### 10.3 Module Example: Networking

**`modules/networking.nix`:**

```nix
{ config, pkgs, ... }:

{
  # Firewall
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];  # SSH only
    trustedInterfaces = [ "tailscale0" "lo" "docker0" ];
    allowPing = true;
    logRefusedConnections = true;
    
    # Note: SSH rate limiting removed - was causing connection timeouts
    # Security is handled by key-only auth + fail2ban
  };

  # fail2ban
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";
    jails.sshd = {
      enabled = true;
      port = "22";
    };
  };

  # Tailscale
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "server";
  };

  # Cloudflare Tunnel
  services.cloudflared = {
    enable = true;
    tunnels = {
      homelab = {
        credentialsFile = "/var/lib/cloudflared/credentials.json";
        default = "http_status:404";
        ingress = {
          # Populated per service
          "photos.yourdomain.com" = "http://localhost:2283";
          "files.yourdomain.com" = "http://localhost:8080";
          "passwords.yourdomain.com" = "http://localhost:8000";
          "watch.yourdomain.com" = "http://localhost:8096";
          "request.yourdomain.com" = "http://localhost:5055";
        };
      };
    };
  };
}
```

### 10.4 Service Example: Immich

**`services/tier1-critical/immich.nix`:**

```nix
{ config, pkgs, ... }:

{
  # Immich service (native NixOS module if available, or custom)
  services.immich = {
    enable = true;
    host = "0.0.0.0";
    port = 2283;
    
    # PostgreSQL connection
    database = {
      host = "localhost";
      port = 5432;
      name = "immich";
      user = "immich";
      # Password in environment or secrets
      passwordFile = "/var/secrets/immich-db-password";
    };
    
    # Storage paths
    mediaLocation = "/data/immich/library";
    uploadLocation = "/data/immich/upload";
    
    # Machine learning
    machineLearning = {
      enable = true;
      port = 3003;
    };
  };
  
  # Ensure PostgreSQL database exists
  services.postgresql.ensureDatabases = [ "immich" ];
  services.postgresql.ensureUsers = [{
    name = "immich";
    ensureDBOwnership = true;
  }];
}
```

### 10.5 Deployment Workflow

```bash
# 1. Edit configuration
cd /etc/nixos
sudo vim services/tier1-critical/immich.nix

# 2. Test build (doesn't activate)
sudo nixos-rebuild dry-build --flake .#nuc-server

# 3. Build and switch
sudo nixos-rebuild switch --flake .#nuc-server

# 4. Check service status
sudo systemctl status immich

# 5. View logs
sudo journalctl -u immich -f

# 6. Commit changes
sudo git add .
sudo git commit -m "Add Immich service"
sudo git push
```

### 10.6 Rollback Strategy

```bash
# List generations
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system

# Rollback to previous
sudo nixos-rebuild --rollback switch

# Rollback to specific generation
sudo nixos-rebuild switch --rollback-to 42

# Boot into previous generation (one-time)
# Select generation in GRUB bootloader menu
```

---

## 11. Hardware Considerations

### 11.1 Intel NUC N150 Specifications

**CPU:** Intel N150 (Alder Lake-N)
- 4 cores, 4 threads (E-cores only)
- Base: 0.9 GHz, Boost: 3.6 GHz
- 6W TDP (low power)
- ✅ **Intel Quick Sync Video** (UHD Graphics)
  - H.264 encode/decode (AVC)
  - H.265/HEVC encode/decode (10-bit)
  - VP9 decode
  - AV1 decode

**RAM:** 16GB DDR5
- More than sufficient for all services
- Fast DDR5 bandwidth improves performance

**Storage:**
- NVMe SSD: OS and configs (~256GB typical)
- USB HDD: 20TB ZFS pool for data

**Network:**
- Ethernet: 1Gbps (enp1s0)
- WiFi: 802.11ac (wlo1)

### 11.2 Performance Expectations

**Jellyfin Transcoding:**
- ✅ **Hardware acceleration via Quick Sync**
- ✅ Direct play: Excellent (no transcoding needed)
- ✅ Hardware transcoding: 3-5 concurrent 1080p streams
- ✅ 4K → 1080p transcode: 2-3 concurrent streams
- ✅ Tone mapping (HDR → SDR): Supported
- **Capability:** Excellent for family streaming needs

**Service Concurrency:**
- ✅ All services can run simultaneously without issues
- ✅ Multiple concurrent downloads (5-10)
- ✅ Immich ML processing (good performance with 16GB RAM)
- ✅ Database queries: Excellent with available RAM
- ✅ 16GB RAM provides comfortable headroom for all services

**Storage Performance:**
- ✅ NVMe OS disk: Fast
- ⚠️ USB 3.0 HDD: ~120 MB/s sequential
- ⚠️ Random I/O: Typical HDD limitations
- **Impact:** Acceptable for media, may be slow for database-heavy operations

### 11.3 Optimization Strategies

**1. Jellyfin Configuration with Hardware Acceleration:**

```nix
services.jellyfin = {
  enable = true;
  
  # Enable hardware transcoding (Intel Quick Sync)
  hardwareAcceleration = "vaapi";  # Video Acceleration API
  
  # Ensure jellyfin user has access to GPU
  group = "video";
  extraGroups = [ "render" ];
};

# Enable required kernel modules for hardware acceleration
boot.kernelModules = [ "i915" ];  # Intel graphics driver

# Add jellyfin user to video group (already in user config section)
# This enables access to /dev/dri for hardware transcoding
```

**2. PostgreSQL Tuning for 16GB RAM:**

```nix
services.postgresql.settings = {
  # Optimized for 16GB RAM
  shared_buffers = "4GB";              # 25% of RAM
  effective_cache_size = "12GB";       # 75% of RAM
  work_mem = "16MB";                   # Per operation
  maintenance_work_mem = "1GB";        # For maintenance tasks
  
  # Optimize for HDD (USB storage)
  random_page_cost = 4.0;              # Default for HDD
  effective_io_concurrency = 2;        # For HDD
  
  # Performance tuning
  max_connections = 100;
  checkpoint_completion_target = 0.9;
  wal_buffers = "16MB";
  default_statistics_target = 100;
  min_wal_size = "2GB";
  max_wal_size = "8GB";
};
```

**3. Immich ML Configuration:**

```nix
# With 16GB RAM, can run multiple ML workers
services.immich.machineLearning = {
  workers = 2;  # Two workers for faster processing
  modelCache = "/data/immich/ml-cache";
};
```

**4. Deluge Rate Limiting:**

```yaml
# In Deluge settings
max_connections_global: 200
max_upload_slots_global: 4
max_active_downloading: 3
max_active_seeding: 5
```

### 11.4 Resource Allocation

**Expected RAM Usage with 16GB:**

| Service | RAM Usage | Priority |
|---------|-----------|----------|
| NixOS System | ~800MB | Critical |
| PostgreSQL | ~4GB (allocated) | High |
| Immich (with ML) | ~2GB | High |
| Nextcloud | ~500MB | High |
| Jellyfin | ~600MB | High |
| Radarr/Sonarr/Bazarr | ~200MB each | Medium |
| Prowlarr/Jellyseerr | ~150MB each | Medium |
| Deluge | ~300MB | Medium |
| Docker/Gluetun | ~150MB | Medium |
| Others (combined) | ~500MB | Low |
| **TOTAL** | ~10-11GB | |
| **Available** | ~5-6GB | Buffer/Cache |

**With 16GB RAM:** 
- ✅ Excellent performance with comfortable headroom
- ✅ PostgreSQL can use 4GB shared buffers
- ✅ Multiple ML workers for Immich
- ✅ Room for file system cache (improves I/O)
- ✅ No swap needed for normal operation

**Optional Swap Configuration (for safety):**

```nix
# Small swap for emergency situations only
swapDevices = [{
  device = "/swap/swapfile";
  size = 4096;  # 4GB swap on NVMe
}];

# Very low swappiness (almost never use swap)
boot.kernel.sysctl = {
  "vm.swappiness" = 1;  # Only swap on extreme memory pressure
};
```

### 11.5 Thermal Management

**NUC Cooling:**
- Fanless or low-power fan design
- Monitor temperatures: `sensors`
- Keep NUC in ventilated area
- Consider USB fan if temps > 70°C

**Monitoring:**

```nix
# Install lm_sensors
environment.systemPackages = [ pkgs.lm_sensors ];

# Auto-detect sensors
# Run: sudo sensors-detect
```

---

## 12. Failure Modes and Recovery

### 12.1 Common Failure Scenarios

#### Scenario 1: ZFS Pool Won't Import

**Symptoms:**
- System boots but `/data` not mounted
- `zpool import` shows pool as "UNAVAIL"

**Causes:**
- USB drive not detected at boot
- ZFS kernel module not loaded
- Pool cache corruption

**Recovery:**

```bash
# Check if drive is detected
lsblk | grep sd

# Try force import
sudo zpool import -f storagepool

# If still fails, check for errors
sudo zpool status -v storagepool

# Clear errors (if drive is healthy)
sudo zpool clear storagepool

# Rebuild system to fix mounting
sudo nixos-rebuild switch --flake /etc/nixos#nuc-server
```

**Prevention:**
- Use `/dev/disk/by-id` for consistent device naming ✅
- Add mount timeout options in `configuration.nix` ✅
- Monitor ZFS health: `zpool status` weekly

#### Scenario 2: VPN Connection Failed (Deluge Exposed)

**Symptoms:**
- Deluge shows "connected" but not downloading
- IP check shows home IP instead of VPN

**Causes:**
- Gluetun container crashed
- WireGuard authentication failed
- Surfshark server down

**Recovery:**

```bash
# Check Gluetun status
docker ps | grep gluetun
docker logs gluetun

# Restart Gluetun
docker restart gluetun

# Verify VPN IP
docker exec gluetun wget -qO- ifconfig.me

# Check kill-switch is active
docker exec gluetun iptables -L -n

# If needed, restart Deluge too
docker restart deluge
```

**Prevention:**
- Gluetun auto-restart enabled ✅
- Health checks configured ✅
- Kill-switch prevents leaks ✅
- Monitor regularly

#### Scenario 3: Service Won't Start After Rebuild

**Symptoms:**
- `nixos-rebuild switch` succeeds but service inactive
- `systemctl status <service>` shows "failed"

**Causes:**
- Configuration syntax error
- Missing dependency
- Port conflict
- Permission issue

**Recovery:**

```bash
# Check service status
sudo systemctl status immich

# View detailed logs
sudo journalctl -u immich -n 100 --no-pager

# Check for port conflicts
sudo ss -tulpn | grep :2283

# Verify file permissions
ls -la /data/immich

# Try dry-build to catch errors
sudo nixos-rebuild dry-build --flake /etc/nixos#nuc-server

# Rollback if needed
sudo nixos-rebuild --rollback switch
```

**Prevention:**
- Test with `dry-build` first ✅
- Check logs after every rebuild ✅
- Verify permissions in module configs ✅

#### Scenario 4: PostgreSQL Database Corruption

**Symptoms:**
- Service logs show database connection errors
- PostgreSQL won't start
- Data inconsistency errors

**Causes:**
- Power loss during write
- Disk full
- Hardware failure

**Recovery:**

```bash
# Check PostgreSQL logs
sudo journalctl -u postgresql -n 200

# Try starting PostgreSQL manually
sudo systemctl start postgresql

# If corrupted, restore from backup
sudo systemctl stop immich
sudo -u postgres psql -c "DROP DATABASE immich;"
sudo -u postgres psql -c "CREATE DATABASE immich OWNER immich;"
gunzip -c /backups/databases/immich-<date>.sql.gz | \
  sudo -u postgres psql immich

# Restart service
sudo systemctl start immich
```

**Prevention:**
- Daily database backups ✅
- ZFS snapshots (hourly for DB datasets) ✅
- UPS for power protection (recommended)

#### Scenario 5: Ran Out of Storage Space

**Symptoms:**
- Services can't write files
- ZFS quota exceeded
- System logs show "No space left"

**Recovery:**

```bash
# Check usage by dataset
sudo zfs list -o name,used,avail,quota,mountpoint

# Find large files
sudo ncdu /data

# Free up space:
# 1. Delete old downloads
rm -rf /data/media/downloads/complete/*

# 2. Prune old snapshots
sudo zfs list -t snapshot | grep frequent
sudo zfs destroy storagepool/media@auto-2024...

# 3. Increase quota if needed
sudo zfs set quota=7T storagepool/media/movies

# 4. Clean up Docker
docker system prune -a
```

**Prevention:**
- Monitor disk usage weekly ✅
- Set up alerts (future: Prometheus) ✅
- Automatic snapshot pruning ✅
- Regular cleanup of downloads ✅

### 12.2 Disaster Recovery Procedures

#### Complete System Failure

**If NixOS won't boot:**

1. **Boot from USB installer**
2. **Import ZFS pool:**
   ```bash
   sudo zpool import -f storagepool
   ```
3. **Mount root filesystem:**
   ```bash
   sudo mount /dev/nvme0n1p2 /mnt
   sudo mount /dev/nvme0n1p1 /mnt/boot
   ```
4. **Restore configuration from Git:**
   ```bash
   git clone https://github.com/yourusername/nixos-config /mnt/etc/nixos
   ```
5. **Reinstall bootloader:**
   ```bash
   nixos-install --root /mnt --flake /mnt/etc/nixos#nuc-server
   ```
6. **Reboot**

#### Data Loss Recovery

**Priority Data Recovery Order:**

1. **Vaultwarden vault** (from `/backups/vaultwarden/`)
2. **PostgreSQL databases** (from `/backups/databases/`)
3. **Service configs** (from `/backups/configs/` or Git)
4. **ZFS snapshots** (if available): `zfs rollback`
5. **Media files** (re-download if needed)

### 12.3 Health Monitoring Checklist

**Daily (Automated):**
- [ ] ZFS scrub errors: `zpool status`
- [ ] Service status: `systemctl --failed`
- [ ] Disk space: `df -h` / `zfs list`
- [ ] VPN status: Check Gluetun health

**Weekly (Manual):**
- [ ] Review system logs: `journalctl -p err -b`
- [ ] Check backups exist
- [ ] Test service access (all tiers)
- [ ] Review fail2ban bans
- [ ] Check snapshot space usage

**Monthly (Manual):**
- [ ] Test backup restoration
- [ ] Update all services
- [ ] Review and prune old snapshots
- [ ] Check for NixOS updates
- [ ] Security audit

**Quarterly (Manual):**
- [ ] Full disaster recovery drill
- [ ] Review and update documentation
- [ ] Rotate API keys
- [ ] Review storage allocation
- [ ] Plan capacity upgrades

---

## Conclusion

This architecture document provides a complete blueprint for deploying a comprehensive NixOS homelab with 14 integrated services. The design prioritizes:

1. **Security:** VPN isolation, firewall rules, defense in depth
2. **Reliability:** ZFS snapshots, backups, failure recovery
3. **Performance:** Optimized for Intel N150 hardware
4. **Accessibility:** Dual network paths (Tailscale + Cloudflare)
5. **Maintainability:** Declarative NixOS, modular configuration

### Key Architectural Highlights

✅ **VPN Isolation:** Deluge traffic 100% through Surfshark via Gluetun  
✅ **Native Services:** 13 of 14 services use NixOS modules (only Deluge containerized)  
✅ **Smart Storage:** 18.5TB ZFS with service-specific datasets and quotas  
✅ **Phased Deployment:** 3 phases over 7 weeks for stable rollout  
✅ **Network Flexibility:** Local, Tailscale VPN, and Cloudflare Tunnel access  
✅ **Hardware Optimized:** Configuration tuned for low-power Intel N150

### Next Steps

1. ✅ Review this architecture document thoroughly
2. ✅ Prepare questions or adjustments
3. ⏭️ Switch to **Code mode** to implement Phase 0 (Infrastructure)
4. ⏭️ Follow deployment phases sequentially
5. ⏭️ Document actual deployment experiences

### Resources for Implementation

- **NixOS Search:** https://search.nixos.org/options
- **NixOS Manual:** https://nixos.org/manual/nixos/stable/
- **Gluetun Docs:** https://github.com/qdm12/gluetun
- **Service Wikis:** Check each service's documentation
- **Homelab Community:** r/selfhosted, r/homelab

**Ready to proceed with implementation when you are!** 🚀

---

**Document Version:** 2.0  
**Last Updated:** 2025-10-23  
**Next Review:** After Phase 1 completion
