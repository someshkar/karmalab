# NixOS Homelab - 18-Service Media & Productivity Server

A fully declarative NixOS configuration for an ASUS NUC (Intel N150) homelab server with 18 self-hosted services.

## Architecture Overview

```
                              INTERNET
                                  │
                    ┌─────────────┴─────────────┐
                    │                           │
              Cloudflare Tunnel           Tailscale VPN
              (Public Access)             (Private Admin)
                    │                           │
    ┌───────────────┼───────────────┐           │
    │               │               │           │
    v               v               v           v
┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────────────────────┐
│ Jellyfin│   │ Immich  │   │Jellyseerr│  │ Radarr, Sonarr, Prowlarr│
│  :8096  │   │  :2283  │   │  :5055  │   │ Bazarr, Deluge, etc.    │
└─────────┘   └─────────┘   └─────────┘   └─────────────────────────┘
                    │
                    │ Docker
    ┌───────────────┼───────────────┐
    │               │               │
┌───────┐     ┌─────────┐     ┌──────────┐
│ Redis │     │Postgres │     │ ML Model │
│       │     │pgvector │     │ (CPU)    │
└───────┘     └─────────┘     └──────────┘
```

## Hardware

| Component | Specification |
|-----------|--------------|
| **Device** | ASUS NUC (Intel N150, Alder Lake) |
| **CPU** | Intel N150 with Quick Sync (VAAPI) |
| **RAM** | 16GB DDR5 |
| **Boot/OS** | 500GB NVMe SSD |
| **Storage** | 20TB Seagate Expansion USB HDD (ZFS) |
| **Network** | 2.5GbE Realtek RTL8125 |

## Service Reference

### Media Stack (Ports 5055-9696)

| Service | Port | Type | Access | Purpose |
|---------|------|------|--------|---------|
| **Jellyfin** | 8096 | Native | Public | Media streaming with HW transcoding |
| **Radarr** | 7878 | Native | Tailscale | Movie automation |
| **Sonarr** | 8989 | Native | Tailscale | TV show automation |
| **Bazarr** | 6767 | Native | Tailscale | Subtitle automation |
| **Prowlarr** | 9696 | Native | Tailscale | Indexer management |
| **Jellyseerr** | 5055 | Native | Public | Media request interface |
| **Readarr** | 8787 | Native | Tailscale | Book automation (Phase 2) |
| **Audiobookshelf** | 13378 | Native | Public | Audiobook streaming (Phase 2) |
| **Calibre-Web** | 8083 | Native | Public | Ebook library (Phase 2) |

### Photo Management (Port 2283)

| Service | Port | Type | Access | Purpose |
|---------|------|------|--------|---------|
| **Immich** | 2283 | Docker | Public | Google Photos alternative |
| Postgres | 5432 | Docker | Internal | Immich database (pgvector) |
| Redis | 6379 | Docker | Internal | Immich caching |
| ML Model | 3003 | Docker | Internal | Face/object recognition |

### Infrastructure

| Service | Port | Type | Access | Purpose |
|---------|------|------|--------|---------|
| **Deluge** | 8112 | Native | Tailscale | Torrent client (VPN isolated) |
| **Uptime Kuma** | 3001 | Native | Tailscale | Service monitoring |

### Productivity (Phase 3)

| Service | Port | Type | Access | Purpose |
|---------|------|------|--------|---------|
| **Vaultwarden** | 8222 | Native | Public | Password manager |
| **Nextcloud** | 8080 | Native | Public | File sync & collaboration |

## Network Topology

```
┌────────────────────────────────────────────────────────────────────────────┐
│                           NETWORK NAMESPACES                               │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │ DEFAULT NAMESPACE (Host)                                            │  │
│  │                                                                     │  │
│  │  enp1s0 (2.5GbE) ──────► LAN (192.168.x.x)                         │  │
│  │  tailscale0 ───────────► Tailscale VPN (100.x.x.x)                 │  │
│  │  lo ───────────────────► Localhost                                  │  │
│  │                                                                     │  │
│  │  Services: Jellyfin, *arr stack, Immich, Uptime Kuma               │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                      │                                     │
│                                      │ veth pair                           │
│                                      ▼                                     │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │ VPN NAMESPACE (Isolated)                                           │  │
│  │                                                                     │  │
│  │  wg-vpn ──────────────► Surfshark WireGuard (VPN IP)               │  │
│  │  veth-vpn ────────────► Connection to host namespace               │  │
│  │                                                                     │  │
│  │  Services: Deluge (torrent traffic ONLY)                           │  │
│  │                                                                     │  │
│  │  Kill Switch: All traffic blocked if VPN disconnects               │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

## Storage Layout

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        NVMe SSD (500GB) - Fast Storage                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  /                           Root filesystem (EXT4 via disko)               │
│  /boot                       EFI partition                                  │
│  /nix                        Nix store                                      │
│  /var/lib/immich/postgres/   Immich database (10GB) - FAST QUERIES          │
│  /var/lib/immich/model-cache/ML models (20GB) - FAST LOADING                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                  USB HDD ZFS Pool (20TB) - storagepool                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  storagepool/data                    /data (root mount)                     │
│  │                                                                          │
│  ├── storagepool/media               /data/media                            │
│  │   ├── movies                      /data/media/movies (6TB quota)         │
│  │   ├── tv                          /data/media/tv (6TB quota)             │
│  │   └── downloads                   /data/media/downloads                  │
│  │       ├── complete                (1TB quota)                            │
│  │       └── incomplete              (500GB, no snapshots)                  │
│  │                                                                          │
│  ├── storagepool/immich              Photo storage                          │
│  │   ├── photos                      /data/immich/photos (1TB quota)        │
│  │   └── upload                      /data/immich/upload (50GB)             │
│  │                                                                          │
│  └── storagepool/services            Service configurations                 │
│      ├── jellyfin/config             /var/lib/jellyfin (10GB)               │
│      ├── jellyfin/cache              /var/cache/jellyfin (100GB)            │
│      ├── deluge/config               /var/lib/deluge (5GB)                  │
│      ├── radarr                      /var/lib/radarr (5GB)                  │
│      ├── sonarr                      /var/lib/sonarr (5GB)                  │
│      ├── bazarr                      /var/lib/bazarr (5GB)                  │
│      ├── prowlarr                    /var/lib/prowlarr (5GB)                │
│      ├── jellyseerr                  /var/lib/jellyseerr (5GB)              │
│      └── uptime-kuma                 /var/lib/private/uptime-kuma (1GB)     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Data Flow Diagrams

### Media Request Flow

```
User Request ──► Jellyseerr ──► Radarr/Sonarr
                                     │
                                     ▼
                               ┌──────────┐
                               │ Prowlarr │ ◄── Indexers (NZB/Torrent)
                               └──────────┘
                                     │
                                     ▼
                               ┌──────────┐
                               │  Deluge  │ ◄── VPN Namespace (Surfshark)
                               └──────────┘
                                     │
                                     ▼
                        /data/media/downloads/complete
                                     │
                                     ▼
                          Radarr/Sonarr (Import)
                                     │
                         ┌───────────┴───────────┐
                         ▼                       ▼
              /data/media/movies      /data/media/tv
                         │                       │
                         └───────────┬───────────┘
                                     ▼
                                ┌──────────┐
                                │ Jellyfin │ ◄── Intel Quick Sync (VAAPI)
                                └──────────┘
                                     │
                                     ▼
                              User Streaming
```

### Photo Upload Flow

```
Mobile App / Web ──► Immich Server (:2283)
                          │
              ┌───────────┼───────────┐
              ▼           ▼           ▼
         ┌────────┐  ┌────────┐  ┌────────────┐
         │ Redis  │  │Postgres│  │ ML Service │
         │(cache) │  │(pgvec) │  │  (CPU)     │
         └────────┘  └────────┘  └────────────┘
                          │           │
              NVMe SSD ◄──┘           │
              (fast DB)               ▼
                              Face Detection
                              Object Recognition
                              Smart Search
                                     │
                                     ▼
                        /data/immich/photos (ZFS)
                              │
                              ▼
                     ZFS Snapshots (automatic)
```

## Access Model

### Public Access (Cloudflare Tunnel - Phase 4)

Services exposed to the internet via Cloudflare Tunnel:

| Subdomain | Service | Notes |
|-----------|---------|-------|
| `jellyfin.somesh.xyz` | Jellyfin | Media streaming |
| `immich.somesh.xyz` | Immich | Photo management |
| `requests.somesh.xyz` | Jellyseerr | Media requests |
| `vault.somesh.xyz` | Vaultwarden | Password manager |
| `cloud.somesh.xyz` | Nextcloud | File sync |
| `books.somesh.xyz` | Audiobookshelf | Audiobooks |
| `library.somesh.xyz` | Calibre-Web | Ebooks |

### Private Access (Tailscale Only)

Admin interfaces accessible only via Tailscale VPN:

- Radarr, Sonarr, Bazarr, Prowlarr, Readarr
- Deluge (torrent management)
- Uptime Kuma (monitoring)
- SSH

## Implementation Phases

### Phase 1: Core Infrastructure (Current)
- [x] Boot/storage configuration with graceful degradation
- [x] WireGuard VPN namespace for torrent isolation
- [x] Native Deluge in VPN namespace
- [x] Immich photo management (Docker)
- [x] Uptime Kuma monitoring
- [ ] Testing and validation

### Phase 2: Book Stack
- [ ] Readarr (book automation)
- [ ] Audiobookshelf (audiobook streaming)
- [ ] Calibre-Web (ebook library)

### Phase 3: Productivity
- [ ] Vaultwarden (password manager)
- [ ] Nextcloud (file sync)

### Phase 4: Public Access
- [ ] Cloudflare Tunnel configuration
- [ ] Subdomain routing
- [ ] SSL certificates (automatic via Cloudflare)

### Phase 5: Documentation & Hardening
- [ ] Complete documentation
- [ ] Security hardening
- [ ] Backup automation

## Quick Start

```bash
# Clone the repository
git clone <repo-url> ~/repos/nixos-homelab
cd ~/repos/nixos-homelab

# One-time: Create ZFS pool (see SETUP.md)
# One-time: Configure WireGuard VPN (see SETUP.md)
# One-time: Create Immich .env file (see SETUP.md)

# Build and deploy
sudo nixos-rebuild switch --flake .#nuc-server

# Verify services
sudo systemctl status jellyfin radarr sonarr immich uptime-kuma
```

## File Structure

```
nixos-homelab-v2/
├── flake.nix                      # Nix flake entry point
├── configuration.nix              # Main NixOS configuration
├── hardware-configuration.nix     # Hardware-specific config
├── disko-config.nix              # NVMe disk partitioning
├── modules/
│   ├── storage.nix               # ZFS pool and dataset management
│   ├── wireguard-vpn.nix         # VPN namespace for torrents
│   └── services/
│       ├── deluge.nix            # Native Deluge in VPN namespace
│       ├── immich.nix            # Immich Docker Compose service
│       └── uptime-kuma.nix       # Service monitoring
├── docker/
│   └── immich/
│       ├── docker-compose.yml    # Immich container stack
│       └── .env.example          # Environment template
├── docs/
│   ├── deployment-guide.md
│   ├── arr-stack-setup.md
│   ├── jellyfin-setup.md
│   └── ...
├── SETUP.md                      # One-time setup instructions
└── README.md                     # This file
```

## Hardware Transcoding

Both Jellyfin and Immich use Intel Quick Sync (VAAPI) for hardware-accelerated video transcoding:

```nix
# Intel Quick Sync configuration
hardware.opengl = {
  enable = true;
  extraPackages = with pkgs; [
    intel-media-driver      # VAAPI for Alder Lake N150
    vaapiIntel             # Legacy VAAPI
    intel-compute-runtime  # OpenCL for tone mapping
  ];
};
```

**Jellyfin**: Uses `/dev/dri/renderD128` for transcoding
**Immich**: Docker containers get `/dev/dri` passed through

## Graceful Degradation

The system is designed to boot and run core services even if the USB HDD is disconnected:

1. **ZFS import uses extended timeouts** (2 minutes) for slow USB enumeration
2. **All mounts use `nofail`** - boot continues if mount fails
3. **Services use `wants` not `requires`** for storage dependency
4. **`storage-online.target`** provides a soft dependency point

## Maintenance

```bash
# Check ZFS pool health
sudo zpool status storagepool

# Manual ZFS scrub
sudo zpool scrub storagepool

# Check VPN connection
sudo ip netns exec vpn curl -s https://api.ipify.org

# Service logs
journalctl -u immich -f
journalctl -u jellyfin -f

# Docker logs (Immich)
docker logs immich_server -f
```

## Troubleshooting

See [SETUP.md](./SETUP.md) for detailed troubleshooting steps.

## License

MIT
