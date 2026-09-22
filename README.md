# Karmalab - NixOS Homelab Media & Photo Server

A fully declarative NixOS configuration for an ASUS NUC (Intel N150) homelab server with self-hosted media automation, photo management, and monitoring services.

## Current Status

| Service | Port | Network | Status | Notes |
|---------|------|---------|--------|-------|
| **Jellyfin** | 8096 | Host | Working | Media streaming, Intel Quick Sync HW transcoding |
| **Prowlarr** | 9696 | Host + Gluetun proxy | Working | Indexer management, searches via Gluetun HTTP proxy |
| **FlareSolverr** | 8191 | Host (Docker) | Working | Cloudflare bypass for Prowlarr |
| **Radarr** | 7878 | Host | Working | Movie automation |
| **Sonarr** | 8989 | Host | Working | TV show automation |
| **Bazarr** | 6767 | Host + Gluetun proxy | Working | Subtitle automation via Gluetun HTTP proxy |
| **Seerr** | 5055 | Host (Docker) | Working | Media request interface (Jellyseerr + Overseerr merged) |
| **Deluge** | 8112 | VPN namespace | Working | Torrent client (Surfshark Singapore, namespace-isolated) |
| **aria2 / AriaNg** | 6800 / 6880 | Host | Working | HTTP/FTP download manager with AriaNg web UI |
| **FileBrowser** | 8085 | Host | Working | Web file manager (files.somesh.dev, local/Tailscale only) |
| **Firefox (KasmVNC)** | 3010/3011 | Host (Docker) | Working | Web browser for authenticated downloads |
| **Calibre-Web** | 8083 | Host | Working | Ebook library web interface (books.somesh.dev) |
| **LazyLibrarian** | 5299 | Host + Gluetun proxy | Working | Ebook/audiobook automation (Docker) |
| **Shelfmark** | 8084 | Host + Gluetun proxy | Working | Book search & download UI (shelfmark.somesh.dev) ⚠️ Enable auth! |
| **Audiobookshelf** | 13378 | Host | Working | Audiobook server (abs.somesh.dev) |
| **Immich** | 2283 | Host (Docker) | Working | Google Photos alternative (VAAPI transcoding) |
| **OpenCloud** | 9200 | Host (Docker) | Working | File sync & share (cloud.somesh.dev) |
| **Beszel** | 8090 | Host (Docker) | Working | System monitoring hub + agent (status.somesh.dev) |
| **Homepage** | 8082 | Host (via Caddy :80) | Working | Service dashboard with Glances metrics |
| **Glances** | 61208 | Host | Working | System metrics backend for Homepage |
| **Caddy** | 80 | Host | Working | Reverse proxy → Homepage; serves AriaNg and `/updates.json` |
| **Time Machine** | 445 | Host (Samba) | Working | macOS backup server (run `smbpasswd -a somesh` to set password) |
| **Syncthing** | 8384 / 22000 | Host | Working | File sync (Obsidian + Calibre library) |
| **Forgejo** | 3030 / 2222 | Host | Working | Self-hosted Git server + container registry + LFS |
| **Vaultwarden** | 8222 | Host | Working | Self-hosted password manager (Bitwarden-compatible) |
| **Karmes (Hermes)** | 18789 | Host | Configured | Native Hermes assistant + Camoufox browser (needs `/srv/karmes` secrets/config) |
| **Tailscale** | - | Host | Working | Remote access (exit node + subnet route 192.168.68.0/22) |
| **Cloudflare Tunnel** | - | Host | Working | External access without port forwarding |

## Hardware

| Component | Specification |
|-----------|--------------|
| **Device** | ASUS NUC (Intel N150, Alder Lake) |
| **CPU** | Intel N150 with Quick Sync (VAAPI) |
| **RAM** | 16GB DDR5 |
| **Boot/OS** | 500GB NVMe SSD |
| **Storage** | 20TB Seagate Expansion USB HDD (ZFS) |
| **Network** | Ethernet (enp1s0) - Static IP 192.168.68.59 |

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
│Jellyfin │   │ Immich  │   │  Seerr  │  │ Radarr, Sonarr, Prowlarr│
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
                              │   http://192.168.68.59  │
                              └─────────────────────────┘

External Access (Cloudflare Tunnel):
  - jellyfin.somesh.dev → Jellyfin
  - immich.somesh.dev   → Immich
  - cloud.somesh.dev    → OpenCloud
  - seer.somesh.dev     → Seerr
  - git.somesh.dev      → Forgejo
  - vault.somesh.dev    → Vaultwarden
  - abs.somesh.dev      → Audiobookshelf
  - books.somesh.dev    → Calibre-Web
  - lib.somesh.dev      → LazyLibrarian
  - shelfmark.somesh.dev → Shelfmark (⚠️ enable auth!)
  - sync.somesh.dev     → Syncthing (TCP protocol)
  - home.somesh.dev     → Homepage
  - status.somesh.dev   → Beszel
  - files.somesh.dev    → FileBrowser (local/Tailscale only)
```

### VPN Architecture (Hybrid VPN + HTTP Proxy)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           NETWORK ARCHITECTURE                               │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────────────────────────┐    │
│  │ DEFAULT NAMESPACE (Host: 192.168.68.59)                            │    │
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
│  │  - mam-dynamic-seedbox           │   │  - Prowlarr (indexers)       │   │
│  │                                  │   │  - Bazarr (subtitles)        │   │
│  │  Kill Switch: Enabled            │   │  - Shelfmark (book sources)  │   │
│  │                                  │   │  - LazyLibrarian             │   │
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
- **Prowlarr:** Settings → General → Proxy → `http://192.168.68.59:8888`
- **Bazarr:** Settings → General → Proxy URL → `http://192.168.68.59:8888`
- **Shelfmark:** Settings → Proxy → `http://192.168.68.59:8888`
- **LazyLibrarian:** `HTTP_PROXY`/`HTTPS_PROXY` env → `http://127.0.0.1:8888`

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
│  /var/lib/opencloud/         OpenCloud config/data (UID 1000)               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│              USB HDD ZFS Pool (20TB) - storagepool                          │
│              Total Allocated: ~19.5TB | Physical usable: ~18.2TB            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  MEDIA (7.1TB total):                                                       │
│  ├── storagepool/media/movies       /data/media/movies (2TB quota)          │
│  ├── storagepool/media/tv           /data/media/tv (2TB quota)              │
│  ├── storagepool/media/downloads    /data/media/downloads (2TB)             │
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
│  └── storagepool/services           Service configurations (mount: /var/lib/media-services)
│      ├── jellyfin/config            /var/lib/jellyfin (10GB)                │
│      ├── jellyfin/cache             /var/cache/jellyfin (100GB)             │
│      ├── deluge/config              /var/lib/deluge (5GB)                   │
│      ├── radarr                     /var/lib/radarr (5GB)                   │
│      ├── sonarr                     /var/lib/sonarr (5GB)                   │
│      └── bazarr                     /var/lib/bazarr (5GB)                   │
│                                                                             │
│  NOTE: storagepool/ai (6TB, /data/ai) is an unmanaged dataset created       │
│  out-of-band and is NOT part of this NixOS config.                          │
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
#    - Configure Surfshark WireGuard VPN (Singapore + Iceland/Gluetun)
#    - Create Immich and OpenCloud .env files
#    - Add secrets under /etc/nixos/secrets/ and /etc/gluetun/

# 3. Deploy
sudo nixos-rebuild switch --flake /etc/nixos#karmalab

# 4. Manual service configuration (see SETUP.md):
#    - Jellyfin: Add libraries, enable HW transcoding
#    - Prowlarr: Add indexers, configure FlareSolverr proxy, set Gluetun proxy
#    - Radarr/Sonarr: Connect to Prowlarr and Deluge
#    - Seerr: Connect to Jellyfin, Radarr, Sonarr
#    - Immich: Create admin account
#    - Enable ZFS auto-snapshots (see "Known Issues / TODO" below)
```

## Ebook Management Workflow

**Simple Mac-Centric Workflow:** Shelfmark (search) → Mac (organize) → Syncthing (sync) → Calibre-Web (display)

### 📚 Step-by-Step Process

#### 1. Search & Download (Shelfmark)
- **Access:** http://192.168.68.59:8084 or https://shelfmark.somesh.dev
- **Search** for ebooks from Anna's Archive, Libgen, Z-Library
- **Download Options:**
  - **Option A (Recommended):** Download directly to your Mac browser via Shelfmark web UI
  - **Option B:** Download to NUC temp storage `/tmp/shelfmark-downloads/`, then transfer via `scp`

```bash
# Option B: Transfer from NUC to Mac
scp somesh@192.168.68.59:/tmp/shelfmark-downloads/*.epub ~/Downloads/
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
- **Access:** http://192.168.68.59:8083 or https://books.somesh.dev
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
- Local: http://192.168.68.59:8384
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
ssh somesh@192.168.68.59
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
ssh somesh@192.168.68.59 "sudo rm -rf /tmp/shelfmark-downloads/*"

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
│     │  http://192.168.68.59:8084           │                │
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
│     │  http://192.168.68.59:8083           │                │
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
ssh somesh@192.168.68.59
systemctl status syncthing
journalctl -u syncthing -f
```

**Book not appearing in Calibre-Web?**
- Check Syncthing shows "Up to Date" on both devices
- Verify file exists: `ls -la /data/media/ebooks/calibre-library/Author/Book*/`
- Check Calibre-Web can read library: Visit http://192.168.68.59:8083
- Check file permissions: Should be readable by calibre-web user (group media)

**Shelfmark downloads not working?**
- Check `/tmp/shelfmark-downloads/` exists: `ssh somesh@192.168.68.59 'ls -la /tmp/shelfmark-downloads/'`
- Try downloading directly to Mac browser instead (Option A)
- Check Shelfmark logs: `ssh somesh@192.168.68.59 'journalctl -u docker-shelfmark -f'`

**Metadata not syncing from Mac?**
- Ensure you edited metadata in Calibre Desktop (not Calibre-Web)
- Check Syncthing shows the metadata.db file is syncing
- Force sync: In Syncthing web UI, click folder → "Rescan"

## File Structure

```
karmalab/
├── flake.nix                      # Nix flake entry point (nixos-25.11 + vaultwarden 26.05)
├── flake.lock                     # Pinned dependencies
├── configuration.nix              # Main NixOS configuration (imports all modules)
├── hardware-configuration.nix     # Hardware-specific config
├── disko-config.nix               # NVMe disk partitioning
├── modules/
│   ├── storage.nix               # ZFS pool/dataset management + graceful degradation
│   ├── wireguard-vpn.nix         # "vpn" netns for Deluge torrents (Surfshark Singapore)
│   ├── gluetun.nix               # Gluetun Docker container (Iceland VPN + HTTP proxy)
│   ├── immich-go.nix             # immich-go tool for Google Photos Takeout migration
│   └── services/
│       ├── aria2.nix             # HTTP/FTP download manager
│       ├── audiobookshelf.nix    # Audiobook server
│       ├── beszel.nix            # Server monitoring hub + agent (Docker)
│       ├── caddy.nix             # Reverse proxy (port 80 → Homepage, AriaNg, /updates.json)
│       ├── calibre-web.nix       # Ebook library web interface
│       ├── cloudflared.nix       # Cloudflare Tunnel for external access
│       ├── container-updates.nix # Daily container version checker
│       ├── deluge.nix            # Native Deluge in VPN namespace
│       ├── filebrowser.nix       # Web file manager
│       ├── firefox-browser.nix   # KasmVNC Firefox for authenticated downloads
│       ├── flaresolverr.nix      # Cloudflare bypass (Docker)
│       ├── forgejo.nix           # Self-hosted Git server (+ registry, LFS)
│       ├── homepage.nix          # Service dashboard with Glances
│       ├── immich.nix            # Immich Docker Compose service
│       ├── karmes.nix            # Hermes assistant + Camoufox browser (native)
│       ├── lazylibrarian.nix     # Ebook/audiobook automation (Docker)
│       ├── mam-dynamic-seedbox.nix # MAM seedbox IP updater (in VPN netns)
│       ├── opencloud.nix         # OpenCloud file sync (Docker Compose)
│       ├── shelfmark.nix         # Book & audiobook downloader (Docker)
│       ├── syncthing.nix         # File synchronization
│       ├── tailscale.nix         # Tailscale VPN (remote access + exit node)
│       ├── timemachine.nix       # macOS Time Machine backup server (Samba)
│       └── vaultwarden.nix       # Password manager
├── docker/
│   ├── immich/
│   │   ├── docker-compose.yml    # Immich container stack
│   │   └── .env.example          # Environment template
│   └── opencloud/
│       └── docker-compose.yml    # OpenCloud container stack
├── docs/                         # Additional documentation
├── scripts/                      # Diagnostic scripts
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
- [x] **Seerr** - Media request interface (replaced Jellyseerr)
- [x] **Deluge** - Torrent client in VPN namespace
- [x] **Immich** - Photo management (Docker)
- [x] **Beszel** - Service monitoring (replaced Uptime Kuma)

### Phase 2: Polish & Configuration - IN PROGRESS

- [x] Quality profiles for Radarr/Sonarr (size-optimized)
- [x] Minimum seeders configuration in Prowlarr
- [x] Homepage dashboard (single pane of glass)
- [ ] Bazarr subtitle provider configuration
- [ ] Configure Beszel monitors/alerts for all services

### Phase 3: External Access - COMPLETE

- [x] Tailscale VPN for remote access (exit node enabled)
- [x] Cloudflare Tunnel for public services
- [x] Homepage dashboard (single pane of glass)
- [x] aria2 download manager with AriaNg web UI
- [x] Caddy reverse proxy (port 80 → Homepage)

### Phase 4: Book Stack - IN PROGRESS

- [x] **Audiobookshelf** (audiobook streaming)
- [x] **Calibre-Web** (ebook library)
- [x] **Shelfmark** (search & download)
- [x] **LazyLibrarian** (ebook/audiobook automation, Docker)
- [ ] Readarr (not used — replaced by LazyLibrarian)

### Phase 5: Productivity & Backup - IN PROGRESS

- [x] **Vaultwarden** (password manager)
- [x] **OpenCloud** (file sync - 1TB allocated; replaced planned Nextcloud)
- [x] **Time Machine** (macOS network backup - 1.5TB allocated)
- [x] **Syncthing** (file sync for Obsidian vault + Calibre library)
- [x] **Forgejo** (self-hosted Git server)
- [x] **FileBrowser** (web file manager)
- [x] **Firefox (KasmVNC)** (authenticated downloads)
- [x] **Karmes / Hermes** (native AI assistant + Camoufox browser)

### Phase 6: Hardening & Backups - PLANNED

- [ ] **ZFS auto-snapshots are currently NOT working** — `com.sun:auto-snapshot` is not set, so `zfs-auto-snapshot` skips every dataset (see Known Issues)
- [ ] Off-site backup (Backblaze B2 / rclone)
- [ ] Monitoring alerts (Telegram/Discord via Beszel)
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
sudo ip netns exec vpn curl -s https://api.ipify.org

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

# Check Deluge/Singapore VPN namespace (torrents)
sudo ip netns exec vpn curl -s https://api.ipify.org
sudo ip netns exec vpn wg show

# Check Gluetun (Iceland) HTTP proxy egress
curl -s --proxy http://127.0.0.1:8888 https://api.ipify.org
docker logs gluetun --tail 50

# Service logs
journalctl -u jellyfin -f
journalctl -u radarr -f
docker logs immich_server -f

# Restart all *arr services
sudo systemctl restart jellyfin radarr sonarr bazarr prowlarr

# Restart Immich
cd /var/lib/immich && docker compose restart

# Verify the running system matches /etc/nixos (should print identical paths)
readlink -f /run/current-system
nix eval --raw /etc/nixos#nixosConfigurations.karmalab.config.system.build.toplevel.outPath
```

## Troubleshooting

See [SETUP.md](./SETUP.md) for detailed troubleshooting steps.

### Common Issues

| Issue | Solution |
|-------|----------|
| Radarr/Sonarr can't write to /data/media | Run `sudo chown -R root:media /data/media && sudo chmod -R 775 /data/media` |
| Immich 500 error | Fix permissions: `sudo chown -R 999:999 /var/lib/immich/postgres /data/immich` |
| Deluge not downloading | Check VPN namespace: `sudo ip netns exec vpn wg show` |
| Prowlarr/Bazarr searches blocked | Verify Gluetun proxy: `curl --proxy http://127.0.0.1:8888 https://api.ipify.org` should show Iceland |
| FlareSolverr not working | Check container: `docker logs flaresolverr` |
| Syncthing permission denied | Run `sudo chown -R somesh:users /var/lib/syncthing` |
| Git pull permission error | Run `sudo chown -R somesh:users ~/karmalab` |
| nixos-rebuild stuck/failed | Run `sudo systemctl stop nixos-rebuild-switch-to-configuration.service` then retry |
| `vpn-health-check.service` fails | It curls `api.ipify.org` from the `vpn` netns; if the WireGuard tunnel is down (Surfshark rotating endpoints) the curl times out. Deluge stays up (already-established sessions), so this is cosmetic — see Known Issues |
| No ZFS snapshots exist | Expected — `com.sun:auto-snapshot` is unset. See Known Issues |

## Known Issues / TODO

These are real, verified gaps between the declarative config and runtime state (as of commit `c368f16`):

1. **ZFS auto-snapshots never run.** `services.zfs.autoSnapshot` enables `zfs-auto-snapshot-{frequent,hourly,daily,weekly,monthly}.timer`, but the `com.sun:auto-snapshot` ZFS property is never set on any dataset. `zfs-auto-snapshot` treats an unset (`-`) value as "not selected", so every run snapshots nothing. Fix: set `com.sun:auto-snapshot=true` on the datasets you want backed up (e.g. `services`, `immich/photos`, `media/ebooks`, `media/audiobooks`) and `false` on caches/downloads/incomplete. `storage.nix` already sets `false` on a few; add an explicit `true` set for the rest.
2. **`vpn-health-check.service` fails every 5 minutes.** It curls `https://api.ipify.org` inside the `vpn` netns with a 10s timeout. When the Surfshark Singapore tunnel is not passing traffic, the probe times out (`status=28`) and the unit goes red. Consider probing the WireGuard handshake instead of an HTTP endpoint, or gating Deluge on it.
3. **`storagepool/ai` (`/data/ai`, 6TB) is unmanaged.** It exists on the pool (models/runtimes, created out-of-band) but is not created or mounted by `modules/storage.nix`. It was not touched by this doc update.
4. **Dead dataset definitions.** `storage.nix` creates `services/{prowlarr,jellyseerr,uptime-kuma}` datasets but no `fileSystems` entry mounts them, and Prowlarr/jellyseerr/Uptime-Kuma data actually lives on NVMe. These three datasets are empty (~96K each).
5. **`scripts/diagnose-vpn-prowlarr.sh` is obsolete.** It targets `vpn-iceland`/`wg-iceland`, which were removed when Prowlarr moved to the Gluetun HTTP proxy. It's not referenced anywhere.
6. **`docs/media-server-architecture.md` is aspirational** (v2.0 dream doc: Nextcloud, Navidrome, Keycloak, Microbin, Radicale, native PostgreSQL tuning). None of it is implemented; OpenCloud replaced Nextcloud, Beszel replaced Uptime Kuma. Kept for history but not authoritative.

## Access URLs (Local Network)

| Service | URL |
|---------|-----|
| Homepage | http://192.168.68.59 |
| Jellyfin | http://192.168.68.59:8096 |
| Seerr | http://192.168.68.59:5055 |
| Radarr | http://192.168.68.59:7878 |
| Sonarr | http://192.168.68.59:8989 |
| Bazarr | http://192.168.68.59:6767 |
| Prowlarr | http://192.168.68.59:9696 |
| FlareSolverr | http://192.168.68.59:8191 |
| Deluge | http://192.168.68.59:8112 |
| aria2 RPC | http://192.168.68.59:6800/jsonrpc |
| AriaNg | http://192.168.68.59:6880 |
| FileBrowser | http://192.168.68.59:8085 |
| Firefox (KasmVNC) | https://192.168.68.59:3011 |
| Immich | http://192.168.68.59:2283 |
| OpenCloud | http://192.168.68.59:9200 |
| Calibre-Web | http://192.168.68.59:8083 |
| LazyLibrarian | http://192.168.68.59:5299 |
| Shelfmark | http://192.168.68.59:8084 |
| Audiobookshelf | http://192.168.68.59:13378 |
| Beszel | http://192.168.68.59:8090 |
| Glances | http://192.168.68.59:61208 |
| Syncthing | http://192.168.68.59:8384 |
| Forgejo | http://192.168.68.59:3030 |
| Forgejo SSH | ssh://git@192.168.68.59:2222 |
| Vaultwarden | http://192.168.68.59:8222 |
| Time Machine | smb://192.168.68.59/timemachine |

## License

MIT
