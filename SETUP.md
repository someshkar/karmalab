# NixOS Homelab Setup Guide

This guide covers the one-time setup steps for your NixOS media server homelab.

## Prerequisites

- NixOS installed on NVMe drive (via disko)
- 20TB USB HDD connected
- Surfshark VPN subscription with WireGuard credentials

## Step 1: One-Time ZFS Pool Creation

The USB HDD ZFS pool must be created manually once. This is intentional - disko doesn't handle hot-pluggable USB drives well.

### 1.1 Identify the USB HDD

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

### 1.2 Create the ZFS Pool

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

### 1.3 Create the Root Dataset

```bash
# Create root data dataset with legacy mountpoint
sudo zfs create -o mountpoint=legacy storagepool/data

# Verify
sudo zfs list
```

### 1.4 Verify Pool Import

```bash
# Export and reimport to verify
sudo zpool export storagepool
sudo zpool import storagepool

# Check pool status
sudo zpool status storagepool
```

The remaining datasets (media, services) will be created automatically by the `create-zfs-datasets` systemd service on the next boot.

## Step 2: Configure Surfshark WireGuard VPN

### 2.1 Get WireGuard Configuration from Surfshark

1. Log in to [Surfshark](https://my.surfshark.com/vpn/manual-setup/main/wireguard)
2. Go to VPN → Manual Setup → WireGuard
3. Generate a new key pair
4. Download the configuration file for your preferred server

### 2.2 Create WireGuard Configuration File

```bash
# Create wireguard directory
sudo mkdir -p /etc/wireguard

# Create configuration file
sudo nano /etc/wireguard/surfshark.conf
```

Add the following content (replace with your actual values):

```ini
[Interface]
PrivateKey = YOUR_PRIVATE_KEY_HERE
# Note: Address is configured in the systemd service

[Peer]
PublicKey = SURFSHARK_SERVER_PUBLIC_KEY
AllowedIPs = 0.0.0.0/0
Endpoint = SERVER_HOSTNAME:51820
PersistentKeepalive = 25
```

**Example with typical Surfshark values:**

```ini
[Interface]
PrivateKey = yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=

[Peer]
PublicKey = Ew0ioVK8wYjnRkQrXhPpAy/lYT6lCLvQ3lmKWQ/SDXE=
AllowedIPs = 0.0.0.0/0
Endpoint = us-dal.prod.surfshark.com:51820
PersistentKeepalive = 25
```

### 2.3 Secure the Configuration

```bash
sudo chmod 600 /etc/wireguard/surfshark.conf
sudo chown root:root /etc/wireguard/surfshark.conf
```

## Step 3: Apply NixOS Configuration

```bash
# Update flake.lock
nix flake update

# Build and switch to new configuration
sudo nixos-rebuild switch --flake .#nuc-server
```

## Step 4: Verify Services

### 4.1 Check ZFS Pool Import

```bash
# Check pool status
sudo zpool status storagepool

# Check datasets
sudo zfs list

# Check mounts
mount | grep storagepool
```

### 4.2 Check VPN Namespace

```bash
# List network namespaces
ip netns list

# Check VPN connection
sudo ip netns exec vpn curl -s https://api.ipify.org
# Should show Surfshark VPN IP, not your real IP

# Check WireGuard status
sudo ip netns exec vpn wg show
```

### 4.3 Check Services

```bash
# Check all media services
sudo systemctl status jellyfin prowlarr radarr sonarr bazarr jellyseerr

# Check Deluge (runs in VPN namespace)
sudo systemctl status deluged deluge-web

# Check port forwarding
sudo systemctl status deluge-port-forward
```

## Step 5: Initial Service Configuration

### 5.1 Jellyfin (Port 8096)

1. Access: `http://<server-ip>:8096` or via Tailscale
2. Complete setup wizard
3. Add media libraries:
   - Movies: `/data/media/movies`
   - TV Shows: `/data/media/tv`
4. Enable hardware transcoding:
   - Dashboard → Playback → Transcoding
   - Hardware acceleration: VAAPI
   - VA-API Device: `/dev/dri/renderD128`

### 5.2 Deluge (Port 8112)

1. Access: `http://<server-ip>:8112`
2. Default password: `deluge`
3. **Change password immediately!**
4. Configure download paths:
   - Download to: `/data/media/downloads/incomplete`
   - Move completed to: `/data/media/downloads/complete`
5. Enable remote connections for arr stack

### 5.3 Prowlarr (Port 9696)

1. Access: `http://<server-ip>:9696`
2. Add indexers
3. Generate API key: Settings → General → API Key
4. Configure apps (Radarr, Sonarr connections)

### 5.4 Radarr (Port 7878)

1. Access: `http://<server-ip>:7878`
2. Settings → Media Management:
   - Root folder: `/data/media/movies`
3. Settings → Download Clients:
   - Add Deluge: Host `localhost`, Port `58846`
4. Settings → Indexers:
   - Add from Prowlarr sync

### 5.5 Sonarr (Port 8989)

1. Access: `http://<server-ip>:8989`
2. Settings → Media Management:
   - Root folder: `/data/media/tv`
3. Settings → Download Clients:
   - Add Deluge: Host `localhost`, Port `58846`
4. Settings → Indexers:
   - Add from Prowlarr sync

### 5.6 Bazarr (Port 6767)

1. Access: `http://<server-ip>:6767`
2. Connect to Radarr and Sonarr
3. Configure subtitle providers

### 5.7 Jellyseerr (Port 5055)

1. Access: `http://<server-ip>:5055`
2. Sign in with Jellyfin admin account
3. Connect to Radarr and Sonarr
4. Import Jellyfin users

## Troubleshooting

### ZFS Pool Not Importing

If the pool doesn't import after boot:

```bash
# Check if device is present
ls -la /dev/disk/by-id/ | grep -i seagate

# Manual import
sudo zpool import storagepool

# Check for import errors
dmesg | grep -i zfs
journalctl -u zfs-import-storagepool.service
```

### VPN Not Connecting

```bash
# Check namespace exists
ip netns list

# Check WireGuard interface
sudo ip netns exec vpn ip link show

# Check WireGuard config
sudo ip netns exec vpn wg show

# Check logs
journalctl -u wireguard-vpn.service
```

### Services Not Starting

```bash
# Check systemd dependencies
systemctl list-dependencies jellyfin.service

# Check service logs
journalctl -u jellyfin.service -f

# Check if storage is available
ls -la /data
ls -la /var/lib/jellyfin
```

### Deluge Connection Issues from *arr Stack

```bash
# Verify port forwarding is running
sudo systemctl status deluge-port-forward

# Test connection from host
nc -zv localhost 58846

# Test connection in namespace
sudo ip netns exec vpn nc -zv localhost 58846
```

## Maintenance

### ZFS Scrub (Automatic Weekly)

```bash
# Manual scrub
sudo zpool scrub storagepool

# Check scrub status
sudo zpool status storagepool
```

### Check VPN IP

```bash
# Current VPN IP
sudo ip netns exec vpn curl -s https://api.ipify.org

# Compare with real IP
curl -s https://api.ipify.org
```

### Backup Service Configurations

```bash
# Snapshot service datasets
sudo zfs snapshot -r storagepool/services@backup-$(date +%Y%m%d)

# List snapshots
sudo zfs list -t snapshot
```

## Step 6: Immich Photo Management Setup

Immich is a self-hosted Google Photos alternative that runs via Docker Compose.

### 6.1 Create Immich Environment File

```bash
# Create the Immich working directory
sudo mkdir -p /var/lib/immich

# Copy the example env file
sudo cp /etc/nixos/docker/immich/.env.example /var/lib/immich/.env

# Edit with your settings
sudo nano /var/lib/immich/.env
```

**Required settings in `.env`:**

```bash
# IMPORTANT: Generate a strong random password
DB_PASSWORD=your_secure_database_password_here

# Optional: Change upload location if needed
# UPLOAD_LOCATION=/data/immich/photos

# Optional: Change ML cache location if needed
# MODEL_CACHE_LOCATION=/var/lib/immich/model-cache
```

**Generate a secure password:**

```bash
# Generate a random 32-character password
openssl rand -base64 32
```

### 6.2 Copy Docker Compose File

```bash
# Copy the compose file
sudo cp /etc/nixos/docker/immich/docker-compose.yml /var/lib/immich/

# Set proper permissions
sudo chmod 600 /var/lib/immich/.env
```

### 6.3 Start Immich

```bash
# Start the Immich service
sudo systemctl start immich

# Check status
sudo systemctl status immich

# View logs
journalctl -u immich -f

# Or view Docker logs directly
docker logs immich_server -f
docker logs immich_machine_learning -f
```

### 6.4 Initial Immich Configuration

1. Access: `http://<server-ip>:2283` or via Tailscale
2. Create admin account on first access
3. Configure:
   - **Storage Template**: Settings → Storage Template → Enable
   - **Machine Learning**: Enabled by default (CPU)
   - **Hardware Transcoding**: Uses Intel Quick Sync (VAAPI) automatically

### 6.5 Verify Hardware Transcoding

```bash
# Check if GPU is passed through to container
docker exec immich_server ls -la /dev/dri

# Should show:
# renderD128  (Intel Quick Sync)
# card0
```

### 6.6 Mobile App Setup

1. Download Immich app from App Store / Play Store
2. Server URL: `http://<server-ip>:2283` (or Tailscale IP)
3. Login with admin credentials
4. Enable auto-backup in app settings

## Step 7: Uptime Kuma Monitoring Setup

Uptime Kuma is a self-hosted monitoring tool that watches your services.

### 7.1 Start Uptime Kuma

```bash
# Start the service (should start automatically after nixos-rebuild)
sudo systemctl start uptime-kuma

# Check status
sudo systemctl status uptime-kuma

# View logs
journalctl -u uptime-kuma -f
```

### 7.2 Initial Configuration

1. Access: `http://<server-ip>:3001` (Tailscale only)
2. Create admin account on first access
3. **IMPORTANT**: Save your admin credentials securely!

### 7.3 Add Service Monitors

Add monitors for each service:

| Monitor Name | Type | URL/Host | Interval |
|-------------|------|----------|----------|
| Jellyfin | HTTP(s) | `http://localhost:8096` | 60s |
| Radarr | HTTP(s) | `http://localhost:7878` | 60s |
| Sonarr | HTTP(s) | `http://localhost:8989` | 60s |
| Bazarr | HTTP(s) | `http://localhost:6767` | 60s |
| Prowlarr | HTTP(s) | `http://localhost:9696` | 60s |
| Jellyseerr | HTTP(s) | `http://localhost:5055` | 60s |
| Immich | HTTP(s) | `http://localhost:2283/api/server/ping` | 60s |
| Deluge | TCP Port | `localhost:58846` | 60s |
| VPN Status | HTTP(s) | Custom script (see below) | 300s |

### 7.4 VPN Health Monitor (Optional)

Create a status page for VPN health by adding a "Push" monitor that your VPN health check script can ping.

### 7.5 Configure Notifications (Optional)

Go to Settings → Notifications to add:
- Telegram bot
- Discord webhook
- Email (SMTP)
- Pushover
- And many more...

## Troubleshooting

### Immich Not Starting

```bash
# Check if Docker is running
sudo systemctl status docker

# Check if .env file exists
ls -la /var/lib/immich/.env

# Check Immich service logs
journalctl -u immich -e

# Check Docker container logs
docker ps -a  # See container status
docker logs immich_server
docker logs immich_postgres
```

### Immich Database Issues

```bash
# Check PostgreSQL health
docker exec immich_postgres pg_isready

# View PostgreSQL logs
docker logs immich_postgres

# If database is corrupted, you may need to recreate:
# WARNING: This deletes all Immich data!
docker-compose -f /var/lib/immich/docker-compose.yml down -v
sudo rm -rf /var/lib/immich/postgres/*
sudo systemctl restart immich
```

### Uptime Kuma Not Accessible

```bash
# Check service status
sudo systemctl status uptime-kuma

# Check if port is listening
ss -tlnp | grep 3001

# Check firewall
sudo iptables -L -n | grep 3001
```

## File Structure

```
/
├── boot/                    # EFI partition (NVMe)
├── data/                    # ZFS storage pool root
│   ├── media/
│   │   ├── movies/          # Movie files
│   │   ├── tv/              # TV show files
│   │   └── downloads/
│   │       ├── complete/    # Completed downloads
│   │       └── incomplete/  # In-progress downloads
│   └── immich/
│       ├── photos/          # Photo library (ZFS, 1TB quota)
│       └── upload/          # Temporary uploads (ZFS, 50GB)
├── var/lib/
│   ├── jellyfin/           # Jellyfin config (ZFS)
│   ├── deluge/             # Deluge config (ZFS)
│   ├── radarr/             # Radarr config (ZFS)
│   ├── sonarr/             # Sonarr config (ZFS)
│   ├── bazarr/             # Bazarr config (ZFS)
│   ├── prowlarr/           # Prowlarr config (ZFS)
│   ├── jellyseerr/         # Jellyseerr config (ZFS)
│   ├── private/
│   │   └── uptime-kuma/    # Uptime Kuma data (ZFS)
│   └── immich/             # Immich working directory (NVMe)
│       ├── docker-compose.yml
│       ├── .env
│       ├── postgres/       # Database (NVMe for speed)
│       └── model-cache/    # ML models (NVMe for speed)
├── var/cache/
│   └── jellyfin/           # Jellyfin transcoding cache (ZFS)
└── etc/wireguard/
    └── surfshark.conf      # WireGuard VPN configuration
```
