# Karmalab - NixOS Homelab Media & Photo Server

A fully declarative NixOS configuration for an ASUS NUC (Intel N150) homelab server with self-hosted media automation, photo management, and monitoring services.

## Current Status

| Service | Port | Status | Notes |
|---------|------|--------|-------|
| **Jellyfin** | 8096 | Working | Media streaming, Intel Quick Sync HW transcoding |
| **Prowlarr** | 9696 | Working | Indexer management with FlareSolverr |
| **FlareSolverr** | 8191 | Working | Cloudflare bypass for Prowlarr |
| **Radarr** | 7878 | Working | Movie automation |
| **Sonarr** | 8989 | Working | TV show automation |
| **Bazarr** | 6767 | Working | Subtitle automation (needs providers configured) |
| **Jellyseerr** | 5055 | Working | Media request interface |
| **Deluge** | 8112 | Working | Torrent client with VPN isolation (verified Singapore IP) |
| **Immich** | 2283 | Working | Google Photos alternative |
| **Uptime Kuma** | 3001 | Running | Needs monitors configured |

## Hardware

| Component | Specification |
|-----------|--------------|
| **Device** | ASUS NUC (Intel N150, Alder Lake) |
| **CPU** | Intel N150 with Quick Sync (VAAPI) |
| **RAM** | 16GB DDR5 |
| **Boot/OS** | 500GB NVMe SSD |
| **Storage** | 20TB Seagate Expansion USB HDD (ZFS) |
| **Network** | WiFi (wlo1) - will move to 2.5GbE Ethernet |

## Architecture

```
                              INTERNET
                                  │
                    ┌─────────────┴─────────────┐
                    │                           │
              Cloudflare Tunnel           Tailscale VPN
              (Phase 3 - Future)          (Phase 3 - Future)
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
│(Valkey)│    │pgvector │     │  (CPU)   │
└───────┘     └─────────┘     └──────────┘
```

### VPN Isolation (Deluge)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           NETWORK NAMESPACES                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌────────────────────────────────────────────────────────────────────┐    │
│  │ DEFAULT NAMESPACE (Host)                                           │    │
│  │                                                                    │    │
│  │  wlo1 (WiFi) ────────────► LAN (192.168.0.x)                      │    │
│  │  lo ─────────────────────► Localhost                               │    │
│  │                                                                    │    │
│  │  Services: Jellyfin, *arr stack, Immich, Uptime Kuma              │    │
│  └────────────────────────────────────────────────────────────────────┘    │
│                                      │                                      │
│                                      │ veth pair                            │
│                                      ▼                                      │
│  ┌────────────────────────────────────────────────────────────────────┐    │
│  │ VPN NAMESPACE (wg-vpn) - Isolated                                  │    │
│  │                                                                    │    │
│  │  wg-vpn ────────────────► Surfshark WireGuard (Singapore IP)      │    │
│  │  veth-vpn ──────────────► Connection to host namespace            │    │
│  │                                                                    │    │
│  │  Services: Deluge (ALL torrent traffic via VPN)                   │    │
│  │                                                                    │    │
│  │  Kill Switch: All traffic blocked if VPN disconnects              │    │
│  └────────────────────────────────────────────────────────────────────┘    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
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
│  /var/lib/immich/postgres/   Immich database - UID 999:999                  │
│  /var/lib/immich/model-cache/ML models - UID 999:999                        │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                  USB HDD ZFS Pool (20TB) - storagepool                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  storagepool/data                    /data (root mount)                     │
│  │                                                                          │
│  ├── storagepool/media               /data/media (root:media, 775)          │
│  │   ├── movies                      /data/media/movies (6TB quota)         │
│  │   ├── tv                          /data/media/tv (6TB quota)             │
│  │   └── downloads                   /data/media/downloads                  │
│  │       ├── complete                (1TB quota)                            │
│  │       └── incomplete              (500GB, no snapshots)                  │
│  │                                                                          │
│  ├── storagepool/immich              Photo storage (999:999)                │
│  │   ├── photos                      /data/immich/photos (1TB quota)        │
│  │   └── upload                      /data/immich/upload (50GB)             │
│  │                                                                          │
│  └── storagepool/services            Service configurations                 │
│      ├── jellyfin/config             /var/lib/jellyfin (10GB)               │
│      ├── jellyfin/cache              /var/cache/jellyfin (100GB)            │
│      ├── deluge/config               /var/lib/deluge (5GB)                  │
│      ├── radarr                      /var/lib/radarr (5GB)                  │
│      ├── sonarr                      /var/lib/sonarr (5GB)                  │
│      └── bazarr                      /var/lib/bazarr (5GB)                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Quick Start

See [SETUP.md](./SETUP.md) for complete setup instructions. Summary:

```bash
# 1. Clone the repository
git clone https://github.com/someshkar/karmalab ~/karmalab

# 2. One-time setup (see SETUP.md for details):
#    - Create ZFS pool on USB HDD
#    - Configure Surfshark WireGuard VPN
#    - Create Immich .env file

# 3. Deploy
sudo nixos-rebuild switch --flake /etc/nixos#karmalab

# 4. Manual service configuration (see SETUP.md):
#    - Jellyfin: Add libraries, enable HW transcoding
#    - Prowlarr: Add indexers, configure FlareSolverr proxy
#    - Radarr/Sonarr: Connect to Prowlarr and Deluge
#    - Jellyseerr: Connect to Jellyfin, Radarr, Sonarr
#    - Immich: Create admin account
```

## File Structure

```
karmalab/
├── flake.nix                      # Nix flake entry point
├── flake.lock                     # Pinned dependencies
├── configuration.nix              # Main NixOS configuration
├── hardware-configuration.nix     # Hardware-specific config
├── disko-config.nix              # NVMe disk partitioning
├── modules/
│   ├── storage.nix               # ZFS pool and dataset management
│   ├── wireguard-vpn.nix         # VPN namespace for torrents
│   └── services/
│       ├── deluge.nix            # Native Deluge in VPN namespace
│       ├── flaresolverr.nix      # Cloudflare bypass (Docker)
│       ├── immich.nix            # Immich Docker Compose service
│       └── uptime-kuma.nix       # Service monitoring
├── docker/
│   └── immich/
│       ├── docker-compose.yml    # Immich container stack
│       └── .env.example          # Environment template
├── docs/                         # Additional documentation
├── SETUP.md                      # Complete setup guide
└── README.md                     # This file
```

## Implementation Phases

### Phase 1: Core Infrastructure - COMPLETE

- [x] NixOS base system on NVMe with disko
- [x] ZFS storage pool on USB HDD with graceful degradation
- [x] WireGuard VPN namespace for torrent isolation
- [x] Intel Quick Sync (VAAPI) hardware acceleration
- [x] **Jellyfin** - Media streaming with HW transcoding
- [x] **Prowlarr** - Indexer management
- [x] **FlareSolverr** - Cloudflare bypass
- [x] **Radarr** - Movie automation
- [x] **Sonarr** - TV show automation
- [x] **Bazarr** - Subtitle automation
- [x] **Jellyseerr** - Media request interface
- [x] **Deluge** - Torrent client in VPN namespace
- [x] **Immich** - Photo management (Docker)
- [x] **Uptime Kuma** - Service monitoring

### Phase 2: Polish & Configuration - IN PROGRESS

- [x] Quality profiles for Radarr/Sonarr (size-optimized)
- [x] Minimum seeders configuration in Prowlarr
- [ ] Uptime Kuma monitors for all services
- [ ] Bazarr subtitle provider configuration
- [ ] Homepage dashboard (single pane of glass)

### Phase 3: External Access - PLANNED

- [ ] Tailscale VPN for remote access
- [ ] Cloudflare Tunnel for public services
- [ ] SSL/HTTPS for all services
- [ ] Subdomain routing (jellyfin.somesh.xyz, etc.)

### Phase 4: Book Stack - PLANNED

- [ ] Readarr (ebook automation)
- [ ] Audiobookshelf (audiobook streaming)
- [ ] Calibre-Web (ebook library)

### Phase 5: Productivity - PLANNED

- [ ] Vaultwarden (password manager)
- [ ] Nextcloud (file sync) - maybe

### Phase 6: Hardening & Backups - PLANNED

- [ ] ZFS snapshot verification
- [ ] Off-site backup (Backblaze B2)
- [ ] Monitoring alerts (Telegram/Discord)
- [ ] Security hardening
- [ ] Complete documentation

## Key Configuration Notes

### Media Group Permissions

All *arr services run with `group = "media"` (GID 2000). The `/data/media` directory is owned by `root:media` with permissions `775` and setgid bit, so all files inherit the media group.

### Immich Permissions

Immich containers run as UID/GID 999. The directories `/var/lib/immich/postgres`, `/var/lib/immich/model-cache`, `/data/immich/photos`, and `/data/immich/upload` must be owned by `999:999`.

### VPN Verification

To verify torrent traffic is going through the VPN:

```bash
# Check VPN namespace IP (should be Surfshark, not your ISP)
sudo ip netns exec wg-vpn curl -s https://api.ipify.org

# Compare to real IP
curl -s https://api.ipify.org
```

### Quality Profiles (Radarr/Sonarr)

Recommended profile for bandwidth-conscious setups:
- Name: `1080p-Small`
- Allowed: WEB-DL 1080p, WEBRip 1080p (NO REMUX)
- Max size: ~17-35 MB/min (2-4GB per movie)

### Prowlarr Indexer Settings

For public trackers, set minimum seeders to 20+ to avoid dead torrents.

## Maintenance Commands

```bash
# Check ZFS pool health
sudo zpool status storagepool

# Manual ZFS scrub
sudo zpool scrub storagepool

# Check VPN connection
sudo ip netns exec wg-vpn curl -s https://api.ipify.org

# Service logs
journalctl -u jellyfin -f
journalctl -u radarr -f
docker logs immich_server -f

# Restart all *arr services
sudo systemctl restart jellyfin radarr sonarr bazarr prowlarr jellyseerr

# Restart Immich
cd /var/lib/immich && docker compose restart
```

## Troubleshooting

See [SETUP.md](./SETUP.md) for detailed troubleshooting steps.

### Common Issues

| Issue | Solution |
|-------|----------|
| Radarr/Sonarr can't write to /data/media | Run `sudo chown -R root:media /data/media && sudo chmod -R 775 /data/media` |
| Immich 500 error | Fix permissions: `sudo chown -R 999:999 /var/lib/immich/postgres /data/immich` |
| Jellyseerr "Failed to create tag" | Disable "Tag Requests" in Jellyseerr → Settings → Radarr |
| Deluge not downloading | Check VPN: `sudo ip netns exec wg-vpn wg show` |
| FlareSolverr not working | Check container: `docker logs flaresolverr` |

## Access URLs (Local Network)

| Service | URL |
|---------|-----|
| Jellyfin | http://192.168.0.171:8096 |
| Jellyseerr | http://192.168.0.171:5055 |
| Radarr | http://192.168.0.171:7878 |
| Sonarr | http://192.168.0.171:8989 |
| Bazarr | http://192.168.0.171:6767 |
| Prowlarr | http://192.168.0.171:9696 |
| Deluge | http://192.168.0.171:8112 |
| Immich | http://192.168.0.171:2283 |
| Uptime Kuma | http://192.168.0.171:3001 |

## License

MIT
