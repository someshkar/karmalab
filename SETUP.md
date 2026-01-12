# Karmalab Setup Guide

Complete guide to reproduce this NixOS homelab from scratch. This covers both the Nix configuration AND all manual steps required.

## Prerequisites

- ASUS NUC with Intel N150 (or similar x86_64 hardware)
- 500GB+ NVMe SSD for OS
- 20TB USB HDD for storage (or adjust quotas)
- Surfshark VPN subscription with WireGuard credentials
- Another machine to perform initial NixOS installation

## Part 1: Initial NixOS Installation

### 1.1 Boot NixOS Installer

Download NixOS minimal ISO and boot from USB.

### 1.2 Partition NVMe with Disko

The `disko-config.nix` handles NVMe partitioning automatically during install.

```bash
# From installer, clone the repo
nix-shell -p git
git clone https://github.com/someshkar/karmalab /tmp/karmalab

# Run disko to partition the NVMe
sudo nix --experimental-features "nix-command flakes" run github:nix-community/disko -- --mode disko /tmp/karmalab/disko-config.nix
```

### 1.3 Install NixOS

```bash
# Generate hardware config
sudo nixos-generate-config --root /mnt

# Copy hardware-configuration.nix to the repo
cp /mnt/etc/nixos/hardware-configuration.nix /tmp/karmalab/

# Install
sudo nixos-install --flake /tmp/karmalab#karmalab

# Reboot
reboot
```

## Part 2: ZFS Pool Creation (One-Time)

The USB HDD ZFS pool must be created manually. This is intentional - disko doesn't handle hot-pluggable USB drives well.

### 2.1 Identify the USB HDD

```bash
# List all block devices
lsblk

# Find the disk ID (more reliable than /dev/sdX)
ls -la /dev/disk/by-id/ | grep -i seagate
```

You should see something like:
```
usb-Seagate_Expansion_HDD_00000000NT17VP0M-0:0 -> ../../sda
```

### 2.2 Create the ZFS Pool

**WARNING: This will erase all data on the disk!**

```bash
# Create the pool (replace with your actual disk ID)
sudo zpool create \
  -o ashift=12 \
  -O compression=lz4 \
  -O acltype=posixacl \
  -O xattr=sa \
  -O dnodesize=auto \
  -O normalization=formD \
  -O relatime=on \
  -O canmount=off \
  storagepool \
  /dev/disk/by-id/usb-Seagate_Expansion_HDD_00000000NT17VP0M-0:0
```

### 2.3 Create Root Dataset

```bash
# Create root data dataset with legacy mountpoint
sudo zfs create -o mountpoint=legacy storagepool/data

# Mount it
sudo mkdir -p /data
sudo mount -t zfs storagepool/data /data
```

### 2.4 Verify Pool

```bash
sudo zpool status storagepool
sudo zfs list
```

The remaining datasets (media, services, immich) will be created automatically by the `create-zfs-datasets` systemd service on the next rebuild.

## Part 3: Surfshark WireGuard VPN Setup

### 3.1 Get WireGuard Config from Surfshark

1. Log in to [Surfshark](https://my.surfshark.com/vpn/manual-setup/main/wireguard)
2. Go to VPN → Manual Setup → WireGuard
3. Generate a new key pair
4. Download configuration for your preferred server (e.g., Singapore)

### 3.2 Create WireGuard Config File

```bash
sudo mkdir -p /etc/wireguard
sudo nano /etc/wireguard/surfshark.conf
```

Add (replace with your actual values):

```ini
[Interface]
PrivateKey = YOUR_PRIVATE_KEY_HERE

[Peer]
PublicKey = SURFSHARK_SERVER_PUBLIC_KEY
AllowedIPs = 0.0.0.0/0
Endpoint = sg-sng.prod.surfshark.com:51820
PersistentKeepalive = 25
```

### 3.3 Secure the Config

```bash
sudo chmod 600 /etc/wireguard/surfshark.conf
sudo chown root:root /etc/wireguard/surfshark.conf
```

## Part 4: Immich Setup

### 4.1 Create Immich Environment File

```bash
# Generate a secure database password
openssl rand -base64 32
# Save this password!

# Create .env file
sudo nano /var/lib/immich/.env
```

Add:

```bash
IMMICH_VERSION=v2.4.1
UPLOAD_LOCATION=/data/immich/photos
DB_DATA_LOCATION=/var/lib/immich/postgres
MODEL_CACHE_LOCATION=/var/lib/immich/model-cache
DB_USERNAME=postgres
DB_DATABASE_NAME=immich
DB_PASSWORD=YOUR_GENERATED_PASSWORD_HERE
DB_STORAGE_TYPE=SSD
TZ=Asia/Kolkata
```

### 4.2 Copy Docker Compose File

```bash
sudo cp /etc/nixos/docker/immich/docker-compose.yml /var/lib/immich/
sudo chmod 600 /var/lib/immich/.env
```

### 4.3 Fix Permissions (Critical!)

```bash
# Immich containers run as UID 999
sudo chown -R 999:999 /var/lib/immich/postgres
sudo chown -R 999:999 /var/lib/immich/model-cache
sudo chown -R 999:999 /data/immich/photos
sudo chown -R 999:999 /data/immich/upload
```

## Part 5: Apply NixOS Configuration

```bash
# Clone repo to the server
git clone https://github.com/someshkar/karmalab ~/karmalab

# Link to /etc/nixos (optional, for convenience)
sudo ln -sf ~/karmalab /etc/nixos

# Build and switch
sudo nixos-rebuild switch --flake /etc/nixos#karmalab
```

## Part 6: Verify Core Services

### 6.1 Check ZFS

```bash
sudo zpool status storagepool
sudo zfs list
mount | grep storagepool
```

### 6.2 Check VPN Namespace

```bash
# List namespaces
ip netns list
# Should show: wg-vpn

# Check VPN IP (should be Surfshark, not your ISP)
sudo ip netns exec wg-vpn curl -s https://api.ipify.org
echo ""
curl -s https://api.ipify.org
# These should be DIFFERENT IPs
```

### 6.3 Check Services

```bash
sudo systemctl status jellyfin radarr sonarr bazarr prowlarr jellyseerr
sudo systemctl status deluged deluge-web
sudo systemctl status immich uptime-kuma
docker ps  # Should show immich containers
```

## Part 7: Service Configuration (Web UI)

This is the manual configuration required in each service's web interface.

### 7.1 Jellyfin (http://IP:8096)

1. Complete setup wizard, create admin account
2. Add libraries:
   - Movies: `/data/media/movies`
   - TV Shows: `/data/media/tv`
3. Enable hardware transcoding:
   - Dashboard → Playback → Transcoding
   - Hardware acceleration: **VAAPI**
   - VA-API Device: `/dev/dri/renderD128`
   - Enable hardware decoding for all formats
   - Enable hardware encoding

### 7.2 Deluge (http://IP:8112)

1. Default password: `deluge`
2. **Change password immediately** in Preferences → Interface
3. Configure download paths in Preferences → Downloads:
   - Download to: `/data/media/downloads/incomplete`
   - Move completed to: `/data/media/downloads/complete`
4. Enable remote connections:
   - Preferences → Daemon → Allow Remote Connections
   - Note the daemon port (default: 58846)

### 7.3 Prowlarr (http://IP:9696)

1. Complete setup, create auth if prompted
2. **Add FlareSolverr proxy:**
   - Settings → Indexers → Add Indexer Proxy → FlareSolverr
   - Host: `http://localhost:8191`
   - Request Timeout: `60`
   - Test → Save
3. **Add indexers** (e.g., 1337x):
   - Indexers → Add Indexer → Select indexer
   - Enable FlareSolverr for Cloudflare-protected sites
   - Set **Minimum Seeders: 20** (for public trackers)
4. **Get API Key:**
   - Settings → General → Security → API Key (copy this)
5. **Add Apps (Radarr/Sonarr):**
   - Settings → Apps → Add Application → Radarr
   - Prowlarr Server: `http://localhost:9696`
   - Radarr Server: `http://localhost:7878`
   - API Key: (Radarr's API key - get from Radarr first)
   - Sync Level: Full Sync
   - Test → Save
   - Repeat for Sonarr (`http://localhost:8989`)
6. Click **Sync App Indexers** to push indexers

### 7.4 Radarr (http://IP:7878)

1. Complete setup
2. **Get API Key:** Settings → General → Security → API Key
3. **Add Root Folder:**
   - Settings → Media Management → Root Folders → Add Root Folder
   - Path: `/data/media/movies`
4. **Add Download Client:**
   - Settings → Download Clients → + → Deluge
   - Host: `localhost`
   - Port: `58846` (daemon port, NOT 8112)
   - Password: (your Deluge daemon password)
   - Category: `radarr`
   - Test → Save
5. **Create Quality Profile (recommended):**
   - Settings → Profiles → + (Add)
   - Name: `1080p-Small`
   - Enable ONLY: HDTV-1080p, WEBRip-1080p, WEB-DL 1080p
   - **Uncheck** Remux-1080p, Bluray-1080p Raw
   - Upgrade Until: WEB-DL 1080p
   - Save
6. **Set Size Limits:**
   - Settings → Quality
   - WEB-DL 1080p: Max ~35 MB/min (about 4GB for 2hr movie)

### 7.5 Sonarr (http://IP:8989)

Same as Radarr:
1. Get API Key
2. Add Root Folder: `/data/media/tv`
3. Add Deluge download client (same settings, category: `sonarr`)
4. Create quality profile `1080p-Small`

### 7.6 Bazarr (http://IP:6767)

1. **Connect to Radarr:**
   - Settings → Radarr → Enable
   - Host: `localhost`, Port: `7878`
   - API Key: (Radarr's API key)
   - Test → Save
2. **Connect to Sonarr:**
   - Settings → Sonarr → Enable
   - Host: `localhost`, Port: `8989`
   - API Key: (Sonarr's API key)
   - Test → Save
3. **Add Subtitle Providers:**
   - Settings → Providers → +
   - Recommended: Podnapisi, OpenSubtitles.com (needs free account)
4. **Configure Languages:**
   - Settings → Languages → Add preferred languages

### 7.7 Jellyseerr (http://IP:5055)

1. Select **Jellyfin** as media server
2. Sign in with Jellyfin admin credentials
3. **Configure Radarr:**
   - Add Radarr Server
   - URL: `http://localhost:7878`
   - API Key: (Radarr's API key)
   - Quality Profile: `1080p-Small` (or your profile)
   - Root Folder: `/data/media/movies`
   - **Disable "Tag Requests"** (causes 400 errors)
   - Test → Save
4. **Configure Sonarr:**
   - Add Sonarr Server
   - URL: `http://localhost:8989`
   - API Key: (Sonarr's API key)
   - Quality Profile: `1080p-Small`
   - Root Folder: `/data/media/tv`
   - **Disable "Tag Requests"**
   - Test → Save
5. Import Jellyfin users if desired

### 7.8 Immich (http://IP:2283)

1. Create admin account on first access
2. Configure settings as desired:
   - Storage Template: Enable for organized folder structure
   - Machine Learning: Enabled by default
3. **Mobile App:**
   - Download "Immich" app
   - Server URL: `http://IP:2283`
   - Login with admin credentials
   - Enable Background Backup

### 7.9 Uptime Kuma (http://IP:3001)

1. Create admin account
2. Add monitors for each service:

| Monitor | Type | URL/Host | Interval |
|---------|------|----------|----------|
| Jellyfin | HTTP(s) | `http://localhost:8096` | 60s |
| Radarr | HTTP(s) | `http://localhost:7878` | 60s |
| Sonarr | HTTP(s) | `http://localhost:8989` | 60s |
| Prowlarr | HTTP(s) | `http://localhost:9696` | 60s |
| Bazarr | HTTP(s) | `http://localhost:6767` | 60s |
| Jellyseerr | HTTP(s) | `http://localhost:5055` | 60s |
| Immich | HTTP(s) | `http://localhost:2283/api/server/ping` | 60s |
| Deluge | TCP Port | `localhost:58846` | 60s |
| FlareSolverr | HTTP(s) | `http://localhost:8191/health` | 60s |

## Part 8: Test the Full Flow

1. **Request a movie in Jellyseerr**
2. **Check Radarr** → Movies → Should show the movie searching
3. **Check Deluge** → Should see download starting
4. **Verify VPN:** `sudo ip netns exec wg-vpn curl -s https://api.ipify.org`
5. **After download:** Radarr imports to `/data/media/movies`
6. **Check Jellyfin** → Movie appears in library
7. **Bazarr** → Should fetch subtitles automatically

## Troubleshooting

### Radarr/Sonarr: "Folder not writable by user"

```bash
sudo chown -R root:media /data/media
sudo chmod -R 775 /data/media
sudo chmod g+s /data/media /data/media/movies /data/media/tv /data/media/downloads
```

### Immich: 500 Error

PostgreSQL permissions issue:

```bash
cd /var/lib/immich && docker compose down
sudo chown -R 999:999 /var/lib/immich/postgres
sudo chown -R 999:999 /var/lib/immich/model-cache
sudo chown -R 999:999 /data/immich/photos
sudo chown -R 999:999 /data/immich/upload
docker compose up -d
```

If database is corrupted:
```bash
cd /var/lib/immich && docker compose down
sudo rm -rf /var/lib/immich/postgres/*
docker compose up -d
# Re-create admin account
```

### Jellyseerr: "Failed to create tag" Error

Disable "Tag Requests" in Jellyseerr → Settings → Radarr/Sonarr.

### VPN Not Working

```bash
# Check namespace exists
ip netns list

# Check WireGuard status
sudo ip netns exec wg-vpn wg show

# Check logs
journalctl -u wireguard-vpn-namespace.service
journalctl -u wireguard-vpn.service
```

### Deluge Not Downloading

1. Check VPN is connected: `sudo ip netns exec wg-vpn curl -s https://api.ipify.org`
2. Check port forwarding: `sudo systemctl status deluge-port-forward`
3. Check Deluge daemon: `sudo systemctl status deluged`

### ZFS Pool Not Importing

```bash
# Check if device is present
ls -la /dev/disk/by-id/ | grep -i seagate

# Manual import
sudo zpool import storagepool

# Check logs
journalctl -u zfs-import-storagepool.service
```

### NixOS Rebuild Fails

```bash
# Check for syntax errors
nix flake check

# Build without switching to see errors
nixos-rebuild build --flake /etc/nixos#karmalab

# Check specific service config
nix eval .#nixosConfigurations.karmalab.config.services.radarr
```

## Maintenance

### Daily/Automatic

- ZFS auto-snapshots (configured in storage.nix)
- ZFS weekly scrub

### Manual Checks

```bash
# Pool health
sudo zpool status storagepool

# Dataset usage
sudo zfs list -o name,used,avail,quota

# Service status
sudo systemctl status jellyfin radarr sonarr

# Docker containers
docker ps

# VPN status
sudo ip netns exec wg-vpn wg show
```

### Backup Service Configs

```bash
# Manual snapshot
sudo zfs snapshot -r storagepool/services@backup-$(date +%Y%m%d)

# List snapshots
sudo zfs list -t snapshot
```

## SSH Access

```bash
# From your Mac (after adding SSH key)
ssh somesh@192.168.0.171
# Or if configured in ~/.ssh/config:
ssh karmalab
```

SSH config (`~/.ssh/config`):
```
Host karmalab
    HostName 192.168.0.171
    User somesh
    IdentityFile ~/.ssh/id_ed25519
```

## Updating

```bash
# On the server
cd ~/karmalab
git pull
sudo nixos-rebuild switch --flake /etc/nixos#karmalab
```

## File Locations Summary

| Path | Purpose | Permissions |
|------|---------|-------------|
| `/etc/wireguard/surfshark.conf` | VPN config | root:root 600 |
| `/var/lib/immich/.env` | Immich secrets | root:root 600 |
| `/var/lib/immich/docker-compose.yml` | Immich compose | root:root 644 |
| `/var/lib/immich/postgres/` | Immich DB | 999:999 |
| `/var/lib/immich/model-cache/` | ML models | 999:999 |
| `/data/media/` | Media files | root:media 775 |
| `/data/immich/` | Photos | 999:999 755 |
| `/data/timemachine/` | Time Machine backups | root:root 770 |
| `/data/nextcloud/` | Nextcloud files (future) | root:root 750 |

## Part 9: Time Machine Backup Server Setup

The NixOS configuration includes a Samba-based Time Machine server with Apple's `vfs_fruit` extensions for native macOS support.

### 9.1 Create Samba User (One-Time)

After deploying the NixOS configuration, create a Samba user:

```bash
# Create Samba password for your user
sudo smbpasswd -a somesh
# Enter a password (can be different from your login password)
```

### 9.2 Verify Samba Service

```bash
# Check Samba status
sudo systemctl status samba-smbd

# Check Time Machine share is advertised
avahi-browse -at | grep -i time
# Should show: _adisk._tcp
```

### 9.3 Connect from macOS

1. **Open System Settings** → **General** → **Time Machine**
2. Click **Add Backup Disk...** (or **Select Backup Disk...** on older macOS)
3. You should see **"karmalab Time Machine"** in the list (auto-discovered via Bonjour)
4. Select it and click **Use Disk**
5. Enter credentials:
   - Username: `somesh`
   - Password: (the password you set with `smbpasswd`)
6. Click **Connect**

### 9.4 First Backup

The first backup will take a long time depending on:
- Size of your Mac's data
- Network speed (WiFi vs Ethernet)

For a 512GB Mac over WiFi, expect 12-24 hours for the initial backup.

### 9.5 Verify Backup is Working

On the NUC:
```bash
# Check Time Machine directory
ls -la /data/timemachine/

# You should see a sparse bundle file like:
# YourMacName.sparsebundle/

# Check ZFS usage
zfs list storagepool/timemachine
```

On macOS:
- System Settings → Time Machine should show "Last backup: [timestamp]"
- The backup disk should show available space

### 9.6 Time Machine Tips

1. **Wired is better**: First backup over Ethernet is much faster than WiFi
2. **Don't disconnect during backup**: Let backups complete naturally
3. **Quota is enforced**: The 1.5TB quota means Time Machine will auto-prune old backups when full
4. **Power Nap**: Enable Power Nap on your Mac for backups while sleeping (System Settings → Battery → Options)

### 9.7 Troubleshooting Time Machine

**Share not appearing on Mac:**
```bash
# Check Avahi is running
sudo systemctl status avahi-daemon

# Check Samba is running
sudo systemctl status samba-smbd

# Check firewall
sudo iptables -L -n | grep 445
```

**"The network backup disk could not be accessed":**
```bash
# Check Samba logs
sudo tail -f /var/log/samba/log.smbd

# Verify Samba user exists
sudo pdbedit -L | grep somesh
```

**Backup stuck or failing:**
```bash
# Check disk space
zfs list storagepool/timemachine

# Check for sparse bundle lock files
ls -la /data/timemachine/*.sparsebundle/

# If stuck, you may need to remove lock files (only when not backing up!)
# rm /data/timemachine/*.sparsebundle/token
```

**Reset Time Machine on Mac (last resort):**
1. System Settings → Time Machine → Remove backup disk
2. Delete the sparse bundle on the server: `sudo rm -rf /data/timemachine/*.sparsebundle`
3. Re-add the backup disk in Time Machine settings

