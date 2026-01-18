# Karmalab - NixOS Homelab Media & Photo Server

A fully declarative NixOS configuration for an ASUS NUC (Intel N150) homelab server with self-hosted media automation, photo management, and monitoring services.

## Current Status

| Service | Port | VPN | Status | Notes |
|---------|------|-----|--------|-------|
| **Jellyfin** | 8096 | - | Working | Media streaming, Intel Quick Sync HW transcoding |
| **Prowlarr** | 9696 | Gluetun Proxy | Working | Indexer management, searches via Gluetun HTTP proxy |
| **FlareSolverr** | 8191 | - | Working | Cloudflare bypass for Prowlarr |
| **Radarr** | 7878 | - | Working | Movie automation |
| **Sonarr** | 8989 | - | Working | TV show automation |
| **Bazarr** | 6767 | Gluetun Proxy | Working | Subtitle automation via Gluetun HTTP proxy |
| **Jellyseerr** | 5055 | - | Working | Media request interface |
| **Deluge** | 8112 | Singapore | Working | Torrent client (Singapore VPN for speed) |
| **aria2** | 6800/6880 | - | Working | HTTP/FTP download manager with AriaNg web UI |
| **Calibre-Web** | 8083 | - | Working | Ebook library web interface (books.somesh.dev) |
| **Shelfmark** | 8084 | - | Working | Ebook search & download UI (shelfmark.somesh.dev) ⚠️ Enable auth! |
| **Audiobookshelf** | 13378 | - | Working | Audiobook server (abs.somesh.dev) |
| **Immich** | 2283 | Working | Google Photos alternative (enable VAAPI in admin settings) |
| **Uptime Kuma** | 3001 | Running | Needs monitors configured |
| **Time Machine** | 445 | Running | macOS backup server (run `smbpasswd -a somesh` to set password) |
| **Syncthing** | 8384 | Running | File sync (Obsidian + Calibre library) |
| **Forgejo** | 3030 | Running | Self-hosted Git server (complete wizard at first access) |
| **Vaultwarden** | 8222 | Working | Self-hosted password manager (Bitwarden-compatible) |
| **Homepage** | 80 | Working | Service dashboard with system metrics (via Caddy) |
| **Tailscale** | - | Working | VPN for remote access (exit node + subnet routing 192.168.0.0/24) |
| **Cloudflare Tunnel** | - | Working | External access without port forwarding |

## Hardware

| Component | Specification |
|-----------|--------------|
| **Device** | ASUS NUC (Intel N150, Alder Lake) |
| **CPU** | Intel N150 with Quick Sync (VAAPI) |
| **RAM** | 16GB DDR5 |
| **Boot/OS** | 500GB NVMe SSD |
| **Storage** | 20TB Seagate Expansion USB HDD (ZFS) |
| **Network** | Ethernet (enp1s0) - Static IP 192.168.0.200 |

## Architecture

```
                              INTERNET
                                  │
                    ┌─────────────┴─────────────┐
                    │                           │
              Cloudflare Tunnel            Tailscale VPN
              (External Access)            (Remote Admin)
                    │                           │
    ┌───────────────┼───────────────┐           │
    │               │               │           │
    v               v               v           v
┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────────────────────┐
│Jellyfin │   │ Immich  │   │Jellyseerr│  │ Radarr, Sonarr, Prowlarr│
│  :8096  │   │  :2283  │   │  :5055  │   │ Bazarr, Deluge, etc.    │
└─────────┘   └─────────┘   └─────────┘   └─────────────────────────┘
                                │
                    ┌───────────┴───────────┐
                    │                       │
              ┌─────────┐             ┌─────────┐
              │Homepage │             │  Caddy  │
              │  :8082  │◄────────────│   :80   │
              └─────────┘             └─────────┘
                                           │
                              ┌────────────┴────────────┐
                              │    Local Network        │
                              │   http://192.168.0.200  │
                              └─────────────────────────┘

External Access (Cloudflare Tunnel):
  - jellyfin.somesh.dev → Jellyfin
  - immich.somesh.dev   → Immich
  - jellyseer.somesh.dev → Jellyseerr
  - git.somesh.dev      → Forgejo
  - vault.somesh.dev    → Vaultwarden
  - abs.somesh.dev      → Audiobookshelf
  - books.somesh.dev    → Calibre-Web
  - shelfmark.somesh.dev → Shelfmark (⚠️ enable auth!)
  - sync.somesh.dev     → Syncthing (TCP protocol)
```

### VPN Architecture (Hybrid VPN + HTTP Proxy)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           NETWORK ARCHITECTURE                               │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────────────────────────┐    │
│  │ DEFAULT NAMESPACE (Host: 192.168.0.200)                            │    │
│  │                                                                    │    │
│  │  Services: Jellyfin, Radarr, Sonarr, Prowlarr, Bazarr, Immich,    │    │
│  │            Calibre-Web, Shelfmark, Audiobookshelf, etc.           │    │
│  │  - Prowlarr/Bazarr/Shelfmark use Gluetun HTTP proxy for searches  │    │
│  └────────────────────────────────────────────────────────────────────┘    │
│                         │                           │                       │
│  ┌──────────────────────▼───────────┐   ┌───────────▼──────────────────┐   │
│  │ VPN NAMESPACE: vpn (Singapore)   │   │ GLUETUN CONTAINER (Docker)   │   │
│  │                                  │   │                              │   │
│  │  wg-surfshark → Singapore       │   │  WireGuard → Iceland          │   │
│  │                                  │   │  HTTP Proxy: :8888            │   │
│  │  Services:                       │   │                              │   │
│  │  - Deluge (torrents)             │   │  Used by (via proxy config): │   │
│  │                                  │   │  - Prowlarr (indexers)       │   │
│  │  Kill Switch: Enabled            │   │  - Bazarr (subtitles)        │   │
│  │                                  │   │  - Shelfmark (book sources)  │   │
│  └──────────────────────────────────┘   └──────────────────────────────┘   │
│           │                                       │                         │
│           ▼                                       ▼                         │
│    Surfshark Singapore                    Surfshark Iceland                │
│           │                                       │                         │
└───────────┼───────────────────────────────────────┼─────────────────────────┘
            │                                       │
            ▼                                       ▼
    INTERNET (Torrents)                   INTERNET (Searches/Metadata)
```

**Traffic Flow:**
- **Singapore VPN (Speed):** Torrent downloads via Deluge (network namespace isolation)
- **Gluetun HTTP Proxy (Access):** Indexer/subtitle/book searches via Iceland VPN
- **Local Network:** All WebUIs, inter-service communication, media streaming

**Gluetun HTTP Proxy Setup:**
Services that need to bypass geo-blocks configure Gluetun as their HTTP proxy:
- **Prowlarr:** Settings → General → Proxy → `http://192.168.0.200:8888`
- **Bazarr:** Settings → General → Proxy URL → `http://192.168.0.200:8888`
- **Shelfmark:** Settings → Proxy → `http://192.168.0.200:8888`

**Why Iceland?**
- 1337x, OpenSubtitles blocked in India/Singapore → Iceland unrestricted
- Anna's Archive, Z-Library may get blocked → Iceland provides reliable access
- Most "free" internet in world → best for search/metadata services


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
│  /var/lib/nextcloud/         Nextcloud database/config (future)             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│              USB HDD ZFS Pool (20TB) - storagepool                          │
│              Total Allocated: ~13.8TB | Unallocated: ~6.2TB                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  MEDIA (7.1TB total):                                                       │
│  ├── storagepool/media/movies       /data/media/movies (2TB quota)          │
│  ├── storagepool/media/tv           /data/media/tv (2TB quota)              │
│  ├── storagepool/media/downloads    /data/media/downloads (1TB)             │
│  │   ├── complete                   (800GB)                                 │
│  │   └── incomplete                 (400GB, no snapshots)                   │
│  ├── storagepool/media/ebooks       /data/media/ebooks (100GB)              │
│  └── storagepool/media/audiobooks   /data/media/audiobooks (1TB)            │
│                                                                             │
│  IMMICH (4TB total):                                                        │
│  ├── storagepool/immich/photos      /data/immich/photos (4TB quota)         │
│  └── storagepool/immich/upload      /data/immich/upload (50GB)              │
│                                                                             │
│  CLOUD & BACKUP (2.5TB total):                                              │
│  ├── storagepool/opencloud          /data/opencloud (1TB quota)             │
│  └── storagepool/timemachine        /data/timemachine (1.5TB quota)         │
│                                                                             │
│  SERVICES (~150GB):                                                         │
│  └── storagepool/services           Service configurations                  │
│      ├── jellyfin/config            /var/lib/jellyfin (10GB)                │
│      ├── jellyfin/cache             /var/cache/jellyfin (100GB)             │
│      ├── deluge/config              /var/lib/deluge (5GB)                   │
│      ├── radarr                     /var/lib/radarr (5GB)                   │
│      ├── sonarr                     /var/lib/sonarr (5GB)                   │
│      └── bazarr                     /var/lib/bazarr (5GB)                   │
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

## Ebook Management Workflow

**Simple Mac-Centric Workflow:** Shelfmark (search) → Mac (organize) → Syncthing (sync) → Calibre-Web (display)

### 📚 Step-by-Step Process

#### 1. Search & Download (Shelfmark)
- **Access:** http://192.168.0.200:8084 or https://shelfmark.somesh.dev
- **Search** for ebooks from Anna's Archive, Libgen, Z-Library
- **Download Options:**
  - **Option A (Recommended):** Download directly to your Mac browser via Shelfmark web UI
  - **Option B:** Download to NUC temp storage `/tmp/shelfmark-downloads/`, then transfer via `scp`

```bash
# Option B: Transfer from NUC to Mac
scp nixos@192.168.0.200:/tmp/shelfmark-downloads/*.epub ~/Downloads/
```

#### 2. Organize with Calibre Desktop (Mac)
- **Open** Calibre Desktop on your Mac
- **Add books** (⌘+A or drag & drop) to your Calibre library
- **Calibre automatically:**
  - Fetches metadata (title, author, cover, description) from Google Books, Goodreads, etc.
  - Organizes into proper `Author/Book Title (ID)/` structure
  - Generates `metadata.opf` files
  - Extracts/embeds cover images
- **Manual editing:** Right-click → "Edit metadata" for corrections
- **Batch metadata:** Select multiple books → "Download metadata" → Choose best matches

**💡 Pro Tips:**
- Use Calibre's "Polish books" feature to embed metadata directly into EPUB files
- Enable "Add books from directories" to auto-watch Downloads folder
- Use "Check library" to find duplicates and fix metadata issues
- Useful plugins: Goodreads Sync, Quality Check, Reading List

#### 3. Sync to NUC (Syncthing - Bidirectional)
- **Syncthing** automatically syncs your Calibre library between Mac and NUC
- **Mac path:** `~/Calibre Library/` (or your configured library path)
- **NUC path:** `/data/media/ebooks/calibre-library/`
- **Sync direction:** Bidirectional (changes sync both ways)
  - Mac → NUC: New books, metadata updates, cover changes
  - NUC → Mac: Any books added directly to NUC (rare)
- **Speed:** Near-instant sync over local network

#### 4. Access via Calibre-Web (NUC)
- **Calibre-Web** automatically detects updated `metadata.db`
- **Books appear immediately** in web interface (no manual refresh needed)
- **Access:** http://192.168.0.200:8083 or https://books.somesh.dev
- **Features:** Read in browser, download formats, send to Kindle, OPDS feed

### 🔧 Syncthing Setup (Required for Sync)

#### On Mac:

**1. Install Syncthing:**
```bash
brew install syncthing
brew services start syncthing
```

**2. Configure Syncthing:**
- Open web UI: http://localhost:8384
- Click "Actions" → "Show ID" (copy your Mac's device ID)
- You'll add the NUC as a device in the next step

**3. Add folder:**
- Click "+ Add Folder"
- **Folder Label:** `Calibre Library`
- **Folder ID:** `calibre-library`
- **Folder Path:** Browse to your Calibre library (e.g., `/Users/somesh/Calibre Library`)
- **Sharing tab:** Check the box to share with `karmalab` (NUC device)
- **File Versioning (Recommended):** "Simple File Versioning" → Keep last 5 versions
- **Ignore Patterns:** Add `.stfolder` and `*.tmp`
- Click "Save"

#### On NUC:

**1. Open Syncthing web UI:**
- Local: http://192.168.0.200:8384
- External: https://sync.somesh.dev

**2. Add Mac as device:**
- A notification appears: "New Device" (from your Mac)
- Click "Add Device"
- **Device ID:** (auto-filled from Mac)
- **Device Name:** `Mac` or your MacBook name
- Click "Save"

**3. Accept shared folder:**
- Notification: "Mac wants to share folder 'Calibre Library'"
- Click "Add"
- **Folder Path:** `/data/media/ebooks/calibre-library`
- **Folder Type:** "Send & Receive" (bidirectional sync)
- **Advanced → Ignore Patterns:** Add `.stfolder`
- Click "Save"

**4. Wait for initial sync:**
```bash
# Monitor sync progress on NUC
ssh nixos@192.168.0.200
journalctl -u syncthing -f

# Check folder size to verify sync
du -sh /data/media/ebooks/calibre-library/
```

**5. Verify bidirectional sync:**
- Add a test book in Calibre on Mac
- Check NUC: Book appears in `/data/media/ebooks/calibre-library/`
- Open Calibre-Web: Book visible in web UI
- Success! ✅

### 🧹 Cleanup Temporary Downloads

Since Shelfmark downloads to `/tmp/shelfmark-downloads/` on the NUC, periodically clean up:

```bash
# Manual cleanup (on NUC)
ssh nixos@192.168.0.200 "sudo rm -rf /tmp/shelfmark-downloads/*"

# Or set up auto-cleanup (files older than 7 days deleted weekly)
# Already configured in shelfmark.nix - no action needed
```

### 📊 Workflow Diagram

```
┌──────────────────────────────────────────────────────────────┐
│                     EBOOK WORKFLOW                           │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  1. SEARCH & DOWNLOAD (Shelfmark)                           │
│     ┌──────────────────────────────────────┐                │
│     │  🔍 Shelfmark Web UI                 │                │
│     │  http://192.168.0.200:8084           │                │
│     │                                       │                │
│     │  Search: Anna's Archive, Libgen,     │                │
│     │          Z-Library                   │                │
│     └──────────────────────────────────────┘                │
│                    │                                         │
│                    ▼                                         │
│     ┌──────────────────────────────────────┐                │
│     │  💾 Download Options:                │                │
│     │  A) Direct to Mac browser            │                │
│     │  B) NUC temp → scp to Mac            │                │
│     └──────────────────────────────────────┘                │
│                    │                                         │
│                    ▼                                         │
│  2. ORGANIZE (Calibre Desktop on Mac)                       │
│     ┌──────────────────────────────────────┐                │
│     │  📚 Calibre Desktop (Mac)            │                │
│     │  ~/Calibre Library/                  │                │
│     │                                       │                │
│     │  • Add books (⌘+A)                   │                │
│     │  • Auto-fetch metadata               │                │
│     │  • Edit/curate metadata              │                │
│     │  • Organize into Author/Book (ID)/   │                │
│     └──────────────────────────────────────┘                │
│                    │                                         │
│                    ▼                                         │
│  3. SYNC (Syncthing - Bidirectional)                        │
│     ┌──────────────────────────────────────┐                │
│     │  🔄 Syncthing                        │                │
│     │  Mac ↔ NUC (instant sync)            │                │
│     │                                       │                │
│     │  ~/Calibre Library/                  │                │
│     │         ↕                             │                │
│     │  /data/media/ebooks/calibre-library/ │                │
│     └──────────────────────────────────────┘                │
│                    │                                         │
│                    ▼                                         │
│  4. DISPLAY (Calibre-Web on NUC)                            │
│     ┌──────────────────────────────────────┐                │
│     │  🌐 Calibre-Web                      │                │
│     │  http://192.168.0.200:8083           │                │
│     │  https://books.somesh.dev            │                │
│     │                                       │                │
│     │  • Browse/search library             │                │
│     │  • Read in browser                   │                │
│     │  • Download formats                  │                │
│     │  • Send to Kindle                    │                │
│     │  • OPDS feed                         │                │
│     └──────────────────────────────────────┘                │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### ❓ Troubleshooting

**Syncthing not syncing?**
```bash
# On Mac - check Syncthing status
brew services list | grep syncthing
open http://localhost:8384

# On NUC - check Syncthing logs
ssh nixos@192.168.0.200
systemctl status syncthing
journalctl -u syncthing -f
```

**Book not appearing in Calibre-Web?**
- Check Syncthing shows "Up to Date" on both devices
- Verify file exists: `ls -la /data/media/ebooks/calibre-library/Author/Book*/`
- Check Calibre-Web can read library: Visit http://192.168.0.200:8083
- Check file permissions: Should be readable by calibre-web user (group media)

**Shelfmark downloads not working?**
- Check `/tmp/shelfmark-downloads/` exists: `ssh nixos@192.168.0.200 'ls -la /tmp/shelfmark-downloads/'`
- Try downloading directly to Mac browser instead (Option A)
- Check Shelfmark logs: `ssh nixos@192.168.0.200 'journalctl -u docker-shelfmark -f'`

**Metadata not syncing from Mac?**
- Ensure you edited metadata in Calibre Desktop (not Calibre-Web)
- Check Syncthing shows the metadata.db file is syncing
- Force sync: In Syncthing web UI, click folder → "Rescan"

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
│   ├── wireguard-vpn.nix         # VPN namespace for Deluge torrents
│   ├── gluetun.nix               # Gluetun Docker container (Iceland VPN + HTTP proxy)
│   ├── immich-go.nix             # immich-go tool for Google Photos Takeout migration
│   └── services/
│       ├── aria2.nix             # HTTP/FTP download manager
│       ├── audiobookshelf.nix    # Audiobook & ebook server
│       ├── caddy.nix             # Reverse proxy (port 80 → Homepage)
│       ├── cloudflared.nix       # Cloudflare Tunnel for external access
│       ├── deluge.nix            # Native Deluge in VPN namespace
│       ├── flaresolverr.nix      # Cloudflare bypass (Docker)
│       ├── forgejo.nix           # Self-hosted Git server
│       ├── homepage.nix          # Service dashboard with Glances
│       ├── immich.nix            # Immich Docker Compose service
│       ├── syncthing.nix         # File synchronization
│       ├── tailscale.nix         # Tailscale VPN (remote access)
│       ├── timemachine.nix       # macOS Time Machine backup server
│       ├── uptime-kuma.nix       # Service monitoring
│       └── vaultwarden.nix       # Password manager
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
- [x] Homepage dashboard (single pane of glass)

### Phase 3: External Access - COMPLETE

- [x] Tailscale VPN for remote access (exit node enabled)
- [x] Cloudflare Tunnel for public services
- [x] Homepage dashboard (single pane of glass)
- [x] aria2 download manager with AriaNg web UI
- [x] Caddy reverse proxy (port 80 → Homepage)

### Phase 4: Book Stack - IN PROGRESS

- [ ] Readarr (ebook/audiobook automation)
- [x] **Audiobookshelf** (audiobook & ebook streaming) - New
- [ ] Calibre-Web (ebook library - optional)

### Phase 5: Productivity & Backup - IN PROGRESS

- [x] **Vaultwarden** (password manager) - New
- [ ] Nextcloud (file sync - 1TB allocated)
- [x] **Time Machine** (macOS network backup - 1.5TB allocated) - Running
- [x] **Syncthing** (file sync for Obsidian vault) - Running
- [x] **Forgejo** (self-hosted Git server) - Running

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
| Syncthing permission denied | Run `sudo chown -R somesh:users /var/lib/syncthing` |
| Git pull permission error | Run `sudo chown -R somesh:users ~/karmalab` |
| nixos-rebuild stuck/failed | Run `sudo systemctl stop nixos-rebuild-switch-to-configuration.service` then retry |

## Access URLs (Local Network)

| Service | URL |
|---------|-----|
| Jellyfin | http://192.168.0.200:8096 |
| Jellyseerr | http://192.168.0.200:5055 |
| Radarr | http://192.168.0.200:7878 |
| Sonarr | http://192.168.0.200:8989 |
| Bazarr | http://192.168.0.200:6767 |
| Prowlarr | http://192.168.0.200:9696 |
| Deluge | http://192.168.0.200:8112 |
| Immich | http://192.168.0.200:2283 |
| Uptime Kuma | http://192.168.0.200:3001 |
| Syncthing | http://192.168.0.200:8384 |
| Forgejo | http://192.168.0.200:3030 |
| Forgejo SSH | ssh://git@192.168.0.200:2222 |
| Vaultwarden | http://192.168.0.200:8222 |
| Audiobookshelf | http://192.168.0.200:13378 |

## License

MIT
