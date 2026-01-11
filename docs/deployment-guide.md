
# Complete Media Server Stack - Deployment & Testing Guide

**Version:** 1.0  
**Date:** 2025-10-23  
**System:** Intel NUC N150 with NixOS  
**Total Deployment Time:** 4-6 hours (all phases)

---

## Overview

This guide provides step-by-step instructions for deploying and testing your complete media server stack. All implementation phases are complete and ready for deployment:

✅ **Phase 0**: Infrastructure (ZFS, Docker, Firewall)  
✅ **Phase 1**: Deluge with VPN Isolation (Gluetun + Surfshark)  
✅ **Phase 2**: Jellyfin Media Server (Hardware Transcoding)  
✅ **Phase 3**: *arr Stack (Radarr, Sonarr, Bazarr, Prowlarr)  
✅ **Phase 4**: Jellyseerr (Media Request Interface)

### What This Guide Covers

- Complete deployment from configuration files to working system
- Verification steps for each component
- End-to-end workflow testing
- Troubleshooting common issues
- Maintenance and monitoring procedures
- Family member onboarding

---

## Table of Contents

1. [Pre-Deployment Checklist](#1-pre-deployment-checklist)
2. [Phase 0: Apply Infrastructure](#2-phase-0-apply-infrastructure)
3. [Phase 1: Configure and Start Deluge VPN](#3-phase-1-configure-and-start-deluge-vpn)
4. [Phase 2: Setup Jellyfin](#4-phase-2-setup-jellyfin)
5. [Phase 3: Configure *arr Stack](#5-phase-3-configure-arr-stack)
6. [Phase 4: Setup Jellyseerr](#6-phase-4-setup-jellyseerr)
7. [Complete Workflow Testing](#7-complete-workflow-testing)
8. [Service Access Reference](#8-service-access-reference)
9. [Common Issues and Troubleshooting](#9-common-issues-and-troubleshooting)
10. [Verification Commands](#10-verification-commands)
11. [Maintenance Tasks](#11-maintenance-tasks)
12. [Performance Monitoring](#12-performance-monitoring)
13. [Family Member Onboarding](#13-family-member-onboarding)
14. [Next Steps and Future Enhancements](#14-next-steps-and-future-enhancements)

---

## 1. Pre-Deployment Checklist

### System State Verification

Before starting deployment, verify your system is ready:

```bash
# Check NixOS is properly installed
nixos-version

# Verify configuration files are in place
ls -la /etc/nixos/configuration.nix
ls -la /etc/nixos/disko-config.nix
ls -la /etc/nixos/hardware-configuration.nix

# Check Docker compose files
ls -la ~/nixos-homelab-v2/docker/deluge-vpn/docker-compose.yml

# Verify network connectivity
ping -c 3 google.com

# Check available disk space
df -h
```

### Required Information

Gather this information before deployment:

#### 1. Surfshark VPN Credentials

- [ ] **Username**: Your Surfshark service username
- [ ] **Password**: Your Surfshark service password
- [ ] **Preferred Server**: Choose a server location (e.g., Netherlands, India)

**Where to get credentials:**
1. Go to https://my.surfshark.com/
2. Navigate to VPN → Manual Setup → WireGuard
3. Copy username and password

#### 2. System Access

- [ ] **Root Password**: Set and documented
- [ ] **User Password**: For your admin user (somesh)
- [ ] **SSH Access**: Verified from another machine

#### 3. Network Information

- [ ] **Server IP**: Note your NUC's IP address (`ip addr show enp1s0`)
- [ ] **Router IP**: Your home router IP (e.g., 192.168.1.1)
- [ ] **Tailscale Account**: Created at tailscale.com (optional but recommended)

### Backup Recommendations

⚠️ **CRITICAL**: Take backups before deployment:

```bash
# Backup current configuration (if upgrading existing system)
sudo tar -czf /tmp/nixos-config-backup-$(date +%Y%m%d).tar.gz /etc/nixos/

# Backup any existing data
sudo tar -czf /tmp/data-backup-$(date +%Y%m%d).tar.gz /data/ 2>/dev/null || true

# Copy backups to external storage if available
# cp /tmp/*-backup-*.tar.gz /path/to/external/drive/
```

### Expected Disk Space Usage

**After Full Deployment:**

| Component | Space Required | Location |
|-----------|---------------|----------|
| NixOS System | ~15GB | NVMe SSD |
| Docker Images | ~2GB | NVMe SSD |
| Service Configs | ~500MB | ZFS datasets |
| ZFS Reserved | ~2TB | 20TB HDD |
| **Available for Media** | ~17.5TB | 20TB HDD |

### Time Estimates

**Total Deployment Time:** 4-6 hours

| Phase | Duration | Activity |
|-------|----------|----------|
| Phase 0 | 30-45 min | System rebuild, ZFS creation |
| Phase 1 | 15-20 min | VPN configuration, testing |
| Phase 2 | 30-45 min | Jellyfin setup, transcoding config |
| Phase 3 | 90-120 min | *arr stack integration |
| Phase 4 | 30-45 min | Jellyseerr setup |
| Testing | 60-90 min | End-to-end workflow test |

---

## 2. Phase 0: Apply Infrastructure

**Goal:** Deploy core infrastructure (ZFS, Docker, Firewall)

### Step 1: Review Configuration

```bash
# Navigate to configuration directory
cd /etc/nixos

# Review the configuration
less configuration.nix

# Look for Phase 0 section (lines 59-321)
# Verify:
# - ZFS pool name: storagepool
# - Hostname: nuc-server
# - User: somesh
# - Media group GID: 2000
```

### Step 2: Test Build (Dry Run)

```bash
# Test configuration without applying
sudo nixos-rebuild dry-build

# Check for any errors in output
# Fix any syntax errors before proceeding
```

### Step 3: Apply Configuration

```bash
# Apply the NixOS configuration
sudo nixos-rebuild switch

# This will:
# - Enable ZFS support
# - Create ZFS datasets
# - Enable Docker
# - Configure firewall
# - Create media group
# - Install system packages
```

**Expected output:**
```
building the system configuration...
activating the configuration...
setting up /etc...
reloading systemd...
```

### Step 4: Verify ZFS Datasets

```bash
# List all ZFS datasets
zfs list -o name,used,avail,quota,mountpoint

# Expected output should show:
# storagepool/media
# storagepool/media/movies
# storagepool/media/tv
# storagepool/media/downloads
# storagepool/services/jellyfin
# storagepool/services/radarr
# storagepool/services/sonarr
# storagepool/services/bazarr
# storagepool/services/prowlarr
# storagepool/services/jellyseerr
# storagepool/services/deluge

# Verify datasets are mounted
df -h | grep storagepool
```

### Step 5: Verify Docker

```bash
# Check Docker service status
sudo systemctl status docker

# Expected: Active: active (running)

# Test Docker
sudo docker run --rm hello-world

# Expected: "Hello from Docker!" message
```

### Step 6: Verify Firewall

```bash
# Check firewall status
sudo systemctl status firewall

# View firewall rules
sudo iptables -L -n

# Verify trusted interfaces
sudo iptables -L -n | grep -E "tailscale0|lo|docker0"

# Check SSH is allowed
sudo iptables -L -n | grep 22
```

### Step 7: Verify Media Group

```bash
# Check media group exists
getent group media

# Expected output: media:x:2000:somesh,jellyfin

# Verify your user is in media group
groups somesh
```

### Phase 0 Verification Checklist

- [ ] `nixos-rebuild switch` completed successfully
- [ ] All ZFS datasets created and mounted
- [ ] Docker service running
- [ ] Firewall enabled with correct rules
- [ ] Media group created with GID 2000
- [ ] Essential packages installed (htop, curl, docker-compose, etc.)

---

## 3. Phase 1: Configure and Start Deluge VPN

**Goal:** Deploy VPN-isolated torrent client

### Step 1: Navigate to Deluge VPN Directory

```bash
# Change to Docker Compose directory
cd ~/nixos-homelab-v2/docker/deluge-vpn

# Verify files exist
ls -la
# Should show:
# - docker-compose.yml
# - surfshark-config-template.env
# - README.md
```

### Step 2: Configure VPN Credentials

```bash
# Copy template to .env file
cp surfshark-config-template.env .env

# Edit .env file with your credentials
nano .env
```

**Edit these values in `.env`:**

```bash
# Surfshark VPN Configuration
VPN_USERNAME=your-surfshark-username-here
VPN_PASSWORD=your-surfshark-password-here

# Server Selection (choose one near you)
SERVER_COUNTRIES=Netherlands  # or India, United States, etc.

# Leave these defaults:
VPN_SERVICE_PROVIDER=surfshark
VPN_TYPE=wireguard
FIREWALL=on
FIREWALL_OUTBOUND_SUBNETS=192.168.0.0/16,172.17.0.0/16
DOT=off
HEALTH_VPN_DURATION_INITIAL=20s
```

**Save and exit** (Ctrl+X, Y, Enter)

### Step 3: Start the VPN Stack

```bash
# Start Gluetun and Deluge
docker-compose up -d

# Expected output:
# Creating gluetun ... done
# Creating deluge ... done
```

### Step 4: Verify VPN Connection

```bash
# Check containers are running
docker ps

# Expected: Both gluetun and deluge with status "Up"

# Check Gluetun logs for VPN connection
docker logs gluetun | grep -i "wireguard is up"

# Expected: "Wireguard is up"
```

### Step 5: Verify VPN IP (Kill-Switch Test)

```bash
# Get VPN IP (should NOT be your home IP)
docker exec gluetun curl -s ifconfig.me

# Note this IP and verify it's different from your home IP
# Check your home IP: curl ifconfig.me

# Test kill-switch (Deluge should only work through VPN)
docker logs deluge | tail -20
# Should show successful connection through Gluetun network
```

### Step 6: Access Deluge Web UI

**Open in browser:**
```
http://localhost:8112
```

**Or via Tailscale:**
```
http://nuc-server:5055
```

**Default password:** `deluge`

⚠️ **CRITICAL**: Change the default password immediately!

1. Click on **Preferences** icon (gear)
2. Go to **Interface** → **Password**
3. Set a strong password
4. Click **OK**

### Step 7: Configure Deluge Settings

**In Deluge Web UI:**

1. **Preferences** → **Downloads**
   - Download to: `/downloads/incomplete`
   - Move completed to: `/downloads/complete`
   - Automatically add torrents from: (leave unchecked)

2. **Preferences** → **Network**
   - Incoming Port: Use default (58846-58950)
   - Outgoing Ports: Random
   - Enable UPnP: Off (not needed with VPN)

3. **Preferences** → **Bandwidth**
   - Maximum Download Speed: -1 (unlimited)
   - Maximum Upload Speed: 1000 KiB/s (adjust as needed)
   - Maximum Connections: 200
   - Maximum Upload Slots: 4

4. **Click Apply** → **OK**

### Phase 1 Verification Checklist

- [ ] VPN containers running (`docker ps` shows both containers)
- [ ] VPN connected (logs show "Wireguard is up")
- [ ] VPN IP verified (different from home IP)
- [ ] Deluge Web UI accessible
- [ ] Default password changed
- [ ] Kill-switch working (no leaks possible)

**Test VPN isolation:**
```bash
# Stop Gluetun
docker stop gluetun

# Check Deluge logs - should show connection errors (this is correct!)
docker logs deluge --tail 10

# Restart Gluetun
docker start gluetun

# Deluge should reconnect automatically
```

---

## 4. Phase 2: Setup Jellyfin

**Goal:** Configure media streaming server with hardware transcoding

### Step 1: Verify Jellyfin Service

```bash
# Check Jellyfin is running
sudo systemctl status jellyfin

# Expected: Active: active (running)

# Check logs for errors
sudo journalctl -u jellyfin -n 50
```

### Step 2: Verify Hardware Access

```bash
# Check GPU device exists
ls -la /dev/dri/
# Should show: renderD128, card0

# Verify jellyfin user groups
groups jellyfin
# Should include: media, render, video

# Test VAAPI support
vainfo --display drm --device /dev/dri/renderD128
# Should list H.264, HEVC, VP9 support
```

### Step 3: Access Jellyfin Web UI

**Open in browser:**
```
http://localhost:8096
```

**Or via Tailscale:**
```
http://nuc-server:8096
```

### Step 4: Complete Setup Wizard

**Welcome Screen:**
1. Select language: English
2. Click **Next**

**Create Admin Account:**
1. Username: `admin` (or your preference)
2. Password: Strong password (store in password manager!)
3. Click **Next**

**Add Media Libraries:**
- Skip for now - we'll add these next
- Click **Next**

**Metadata Language:**
1. Language: English
2. Country: India
3. Click **Next**

**Remote Access:**
- Leave defaults
- Click **Next**

**Finish:**
- Click **Finish**
- Log in with your admin credentials

### Step 5: Add Media Libraries

**For Movies:**

1. Dashboard → Libraries → **+ Add Media Library**
2. Content type: **Movies**
3. Display name: `Movies`
4. Folders: Click **+** → Browse to `/data/media/movies` → **OK**
5. ✅ Enable real-time monitoring
6. ✅ Automatically refresh metadata
7. Metadata downloaders: ✅ TheMovieDb, ✅ The Open Movie Database
8. Image fetchers: ✅ TheMovieDb
9. Click **OK**

**For TV Shows:**

1. Dashboard → Libraries → **+ Add Media Library**
2. Content type: **Shows**
3. Display name: `TV Shows`
4. Folders: Click **+** → Browse to `/data/media/tv` → **OK**
5. ✅ Enable real-time monitoring
6. ✅ Automatically refresh metadata
7. Metadata downloaders: ✅ TheTVDB, ✅ TheMovieDb
8. Click **OK**

### Step 6: Configure Hardware Transcoding

⚠️ **CRITICAL for Performance**: This enables 3-5 concurrent 1080p streams

1. Dashboard → **Playback** → **Transcoding**

2. **Hardware Acceleration:**
   - Type: `Video Acceleration API (VAAPI)`
   - VA-API Device: `/dev/dri/renderD128`

3. **Hardware Encoding:**
   - ✅ Enable hardware encoding
   - ✅ Enable hardware decoding for:
     - H264
     - HEVC
     - VP8
     - VP9

4. **Tone Mapping:**
   - ✅ Enable tone mapping
   - Mode: Use hardware tone mapping when available
   - ✅ Enable VPP Tone mapping

5. **Other Settings:**
   - ✅ Allow encoding in HEVC format
   - Transcoding thread count: 0 (auto)
   - Maximum transcoding jobs: 5

6. Click **Save**

### Step 7: Test Hardware Transcoding

```bash
# Start playing a video in Jellyfin
# Force transcoding by changing quality to 720p

# Check Dashboard → Activity
# Should show: "Transcode (hw)" or "Transcode (Video: hw)"

# Monitor CPU usage (should be <20%)
htop

# Check Jellyfin logs for VAAPI
sudo journalctl -u jellyfin | grep -i vaapi
# Should show: "Using VAAPI device /dev/dri/renderD128"
```

### Step 8: Create User Accounts

**For each family member:**

1. Dashboard → **Users** → **+ New User**
2. Name: Enter user's name
3. Password: Set a password (optional)
4. User Policy:
   - ✅ Enable media playback
   - ✅ Allow audio playback that requires transcoding
   - ✅ Allow video playback that requires transcoding
   - ✅ Allow media download (optional)
   - ❌ Is Administrator
5. Library Access: ✅ Movies, ✅ TV Shows
6. Click **Save**

### Phase 2 Verification Checklist

- [ ] Jellyfin service running
- [ ] Admin account created
- [ ] Movies library added (`/data/media/movies`)
- [ ] TV Shows library added (`/data/media/tv`)
- [ ] Hardware transcoding configured (VAAPI)
- [ ] Transcoding tested and working (CPU < 20%)
- [ ] Family user accounts created

**Test media playback:**
```bash
# If you have sample media files, test:
# 1. Direct play (no transcoding)
# 2. Transcoding (change quality)
# 3. Check Dashboard → Activity shows "hw" for hardware transcoding
```

For detailed Jellyfin setup, see: [`docs/jellyfin-setup.md`](jellyfin-setup.md)

---

## 5. Phase 3: Configure *arr Stack

**Goal:** Setup automated media acquisition

**⏱ Estimated Time:** 90-120 minutes

**Setup Order:** Prowlarr → Radarr → Sonarr → Bazarr

### Step 1: Verify Services Running

```bash
# Check all *arr services
sudo systemctl status prowlarr radarr sonarr bazarr

# All should show: Active: active (running)

# Check ZFS datasets mounted
zfs list | grep services
```

### Step 2: Setup Prowlarr (Indexer Management)

**Access:** `http://nuc-server:9696`

**Initial Setup:**
1. Complete authentication wizard
2. Create admin account

**Add Indexers:**
1. Click **Indexers** → **Add Indexer**
2. Add these public indexers:
   - **1337x** (General)
   - **The Pirate Bay** (General)
   - **RARBG** (Quality releases)
   - **EZTV** (TV shows)
   - **YTS** (Movies, smaller files)

3. For each indexer:
   - Click indexer name
   - Leave defaults
   - Click **Test** → **Save**

**Generate API Key:**
1. Settings → General → Security
2. Copy **API Key** (save for later)

**Configure Applications (Skip for now - we'll come back):**
- Settings → Apps
- We'll add Radarr and Sonarr after configuring them

### Step 3: Setup Radarr (Movie Automation)

**Access:** `http://nuc-server:7878`

**Initial Setup:**
1. Complete authentication wizard
2. Create admin account

**Add Deluge Download Client:**
1. Settings → Download Clients → **Add** → **Deluge**
2. Configure:
   ```
   Name: Deluge
   Enable: ✅
   Host: localhost
   Port: 58846  ⚠️ CRITICAL: Use daemon port, NOT 8112
   Password: [your Deluge password]
   Category: radarr-movies
   Add Paused: ❌
   Priority: Normal
   ```
3. Click **Test** → **Save**

**Configure Root Folder:**
1. Settings → Media Management
2. Root Folders → **Add Root Folder**
3. Enter: `/data/media/movies`
4. Click checkmark

**Configure Quality Profile:**
1. Settings → Profiles → Quality Profiles
2. Edit default or create new:
   ```
   Name: HD-1080p/720p
   Allowed Qualities:
     ✅ Bluray-1080p
     ✅ WEB-DL 1080p
     ✅ WEBDL-720p
     ✅ Bluray-720p
   Quality Cutoff: Bluray-1080p
   ```
3. Click **Save**

**Configure File Naming:**
1. Settings → Media Management
2. ✅ Rename Movies
3. Standard Movie Format: `{Movie Title} ({Release Year}) - {Quality Full}`
4. Movie Folder Format: `{Movie Title} ({Release Year})`
5. Permissions:
   - File chmod mask: `0775`
6. Click **Save Changes**

**Get Radarr API Key:**
1. Settings → General → Security
2. Copy **API Key**

**Connect to Prowlarr:**
1. Go back to Prowlarr
2. Settings → Apps → **Add Application** → **Radarr**
3. Configure:
   ```
   Name: Radarr
   Sync Level: Full Sync
   Prowlarr Server: http://localhost:9696
   Radarr Server: http://localhost:7878
   API Key: [Paste Radarr API key]
   ```
4. Click **Test** → **Save**

**Verify Indexers:**
1. Back in Radarr: Settings → Indexers
2. Should see indexers automatically added from Prowlarr

### Step 4: Setup Sonarr (TV Show Automation)

**Access:** `http://nuc-server:8989`

**Initial Setup:**
1. Complete authentication wizard
2. Create admin account

**Add Deluge Download Client:**
1. Settings → Download Clients → **Add** → **Deluge**
2. Configure:
   ```
   Name: Deluge
   Enable: ✅
   Host: localhost
   Port: 58846
   Password: [your Deluge password]
   Category: sonarr-tv
   Add Paused: ❌
   Priority: Normal
   ```
3. Click **Test** → **Save**

**Configure Root Folder:**
1. Settings → Media Management
2. Root Folders → **Add Root Folder**
3. Enter: `/data/media/tv`
4. Click checkmark

**Configure Quality Profile:**
1. Settings → Profiles → Quality Profiles
2. Edit or create:
   ```
   Name: HD-1080p/720p
   Allowed Qualities:
     ✅ WEBDL-1080p
     ✅ WEBRip-1080p
     ✅ WEBDL-720p
     ✅ Bluray-1080p
   Quality Cutoff: WEBDL-1080p
   ```

**Configure File Naming:**
1. Settings → Media Management
2. ✅ Rename Episodes
3. Standard Episode Format: `{Series Title} - S{season:00}E{episode:00} - {Episode Title} [{Quality Full}]`
4. Season Folder Format: `Season {season:00}`
5. Series Folder Format: `{Series Title} ({Series Year})`
6. Permissions:
   - File chmod mask: `0775`
7. Click **Save Changes**

**Get Sonarr API Key:**
1. Settings → General → Security
2. Copy **API Key**

**Connect to Prowlarr:**
1. Go back to Prowlarr
2. Settings → Apps → **Add Application** → **Sonarr**
3. Configure:
   ```
   Name: Sonarr
   Sync Level: Full Sync
   Prowlarr Server: http://localhost:9696
   Sonarr Server: http://localhost:8989
   API Key: [Paste Sonarr API key]
   ```
4. Click **Test** → **Save**

### Step 5: Setup Bazarr (Subtitle Automation)

**Access:** `http://nuc-server:6767`

**Initial Setup:**
1. Complete language configuration
2. Select: English (and others if needed)
3. Create admin account

**Connect to Radarr:**
1. Settings → Radarr
2. Configure:
   ```
   Use Radarr: ✅
   Hostname or IP: localhost
   Port: 7878
   API Key: [Radarr API key]
   SSL: ❌
   Download Only Monitored: ✅
   ```
3. Click **Test** → **Save**

**Connect to Sonarr:**
1. Settings → Sonarr
2. Configure:
   ```
   Use Sonarr: ✅
   Hostname or IP: localhost
   Port: 8989
   API Key: [Sonarr API key]
   SSL: ❌
   Download Only Monitored: ✅
   ```
3. Click **Test** → **Save**

**Add Subtitle Providers:**
1. Settings → Providers
2. Add providers:
   - **OpenSubtitles.com** (requires free account at opensubtitles.com)
   - **Subscene** (no account needed)
   - **YIFY Subtitles** (no account needed)

**Configure Language Profile:**
1. Settings → Languages
2. Create profile:
   ```
   Name: English
   Languages: ✅ English
   Cutoff: English
   ```

**Enable Automatic Search:**
1. Settings → Scheduler
2. ✅ Search for Subtitles
3. Interval: 6 hours
4. ✅ Upgrade Subtitles

### Step 6: Test *arr Stack Integration

**Test Movie Search:**
1. In Radarr, click **Add Movie**
2. Search for "The Matrix"
3. Select movie → Configure:
   ```
   Root Folder: /data/media/movies
   Quality Profile: HD-1080p/720p
   Monitor: Yes
   Search on Add: ✅
   ```
4. Click **Add Movie**

**Verify:**
```bash
# Check Deluge has torrent
# Open: http://nuc-server:8112
# Should see movie downloading with category "radarr-movies"

# Monitor Radarr logs
sudo journalctl -u radarr -f

# Check download progress
docker logs deluge -f
```

### Phase 3 Verification Checklist

- [ ] Prowlarr: 3-5 indexers added and working
- [ ] Radarr: Connected to Deluge and Prowlarr
- [ ] Sonarr: Connected to Deluge and Prowlarr
- [ ] Bazarr: Connected to Radarr and Sonarr
- [ ] All API keys configured correctly
- [ ] Root folders configured (`/data/media/movies`, `/data/media/tv`)
- [ ] Quality profiles set
- [ ] File naming configured
- [ ] Permissions set to 0775
- [ ] Test movie search successful

For detailed *arr setup, see: [`docs/arr-stack-setup.md`](arr-stack-setup.md)

---

## 6. Phase 4: Setup Jellyseerr

**Goal:** Create user-friendly media request interface

**⏱ Estimated Time:** 30-45 minutes

### Step 1: Verify Jellyseerr Service

```bash
# Check service status
sudo systemctl status jellyseerr

# Expected: Active: active (running)

# Check ZFS dataset mounted
df -h | grep jellyseerr
```

### Step 2: Access Jellyseerr

**Open in browser:**
```
http://localhost:5055
```

**Or via Tailscale:**
```
http://nuc-server:5055
```

### Step 3: Initial Setup

**Sign In with Jellyfin:**
1. Click **"Sign in"**
2. Click **"Use your Jellyfin account"**
3. Enter Jellyfin server URL: `http://localhost:8096`
4. Click **"Continue"**
5. Sign in with **Jellyfin admin credentials**

### Step 4: Configure Jellyfin Integration

**Settings → Jellyfin:**
1. Server Settings:
   ```
   Server Name: Jellyfin
   Server URL: http://localhost:8096
   Server Type: Jellyfin
   ```
2. Library Sync:
   - ✅ Scan Libraries
   - ✅ Import Jellyfin Users ⚠️ IMPORTANT
3. Click **"Save Changes"**
4. Click **"Sync Libraries"** to import users

### Step 5: Configure Radarr Integration

**Settings → Radarr:**
1. Click **"Add Radarr Server"**
2. Configure:
   ```
   Default Server: ✅
   4K Server: ❌
   Server Name: Radarr
   Hostname or IP: localhost
   Port: 7878
   Use SSL: ❌
   API Key: [Radarr API key]
   Base URL: [leave empty]
   Quality Profile: HD-1080p/720p
   Root Folder: /data/media/movies
   Minimum Availability: Released
   ✅ Enable Automatic Search
   ✅ Enable RSS Sync
   Enable Scan: ✅
   ```
3. Click **"Test"** → **"Save Changes"**

### Step 6: Configure Sonarr Integration

**Settings → Sonarr:**
1. Click **"Add Sonarr Server"**
2. Configure:
   ```
   Default Server: ✅
   4K Server: ❌
   Server Name: Sonarr
   Hostname or IP: localhost
   Port: 8989
   Use SSL: ❌
   API Key: [Sonarr API key]
   Base URL: [leave empty]
   Quality Profile: HD-1080p/720p
   Root Folder: /data/media/tv
   Language Profile: English
   Series Type: Standard
   ✅ Enable Automatic Search
   ✅ Enable Season Folders
   Enable Scan: ✅
   ```
3. Click **"Test"** → **"Save Changes"**

### Step 7: Configure User Permissions

**Settings → Users → [Select User]:**

For each family member:
```
Display Name: [User's name]
User Type: User (not Admin)

Request Limits:
  Movie Request Limit: 10 (per week)
  Series Request Limit: 5 (
per week)
  Request Limit Period: Weekly

Permissions:
  ✅ Auto-Approve Requests
  ✅ Auto-Approve TV Shows
  ✅ Auto-Approve Movies
  ❌ Request 4K Content
```

Click **"Save Changes"**

### Step 8: Configure General Settings

**Settings → General:**

```
Application Title: Jellyseerr
Application URL: http://nuc-server:5055
Display Language: English
Discover Region: IN (or US)

✅ Partial Request (allow requesting specific seasons)
❌ Hide Available

Default Movie Quality: HD-1080p/720p
Default TV Quality: HD-1080p/720p

✅ Auto-Approve All Requests
✅ Auto-Approve Movie Requests
✅ Auto-Approve TV Requests
❌ Allow 4K Requests
```

Click **"Save Changes"**

### Phase 4 Verification Checklist

- [ ] Jellyseerr service running
- [ ] Signed in with Jellyfin admin account
- [ ] Jellyfin integration configured and tested
- [ ] Radarr integration configured and tested
- [ ] Sonarr integration configured and tested
- [ ] Users imported from Jellyfin
- [ ] User permissions configured
- [ ] General settings configured

For detailed Jellyseerr setup, see: [`docs/jellyseerr-setup.md`](jellyseerr-setup.md)

---

## 7. Complete Workflow Testing

**Goal:** Verify end-to-end automation pipeline

**⏱ Estimated Time:** 60-90 minutes

### Test 1: Movie Request Workflow

**Step 1: Request Movie in Jellyseerr**

1. Open Jellyseerr: `http://nuc-server:5055`
2. Browse or search for a popular movie NOT in your library
3. Example: "Inception (2010)"
4. Click on movie card → Click **"Request"**
5. Verify settings and click **"Request Movie"**

**Expected:** Success notification appears

**Step 2: Verify in Radarr**

1. Open Radarr: `http://nuc-server:7878`
2. Go to **Movies** tab
3. Should see "Inception" added with status "Monitoring"
4. Check **Activity** → Should show searching

**Step 3: Check Prowlarr Search**

1. Open Prowlarr: `http://nuc-server:9696`
2. Check **History** tab
3. Should show search queries from Radarr

**Step 4: Monitor Deluge Download**

1. Open Deluge: `http://nuc-server:8112`
2. Should see movie downloading
3. Category should be "radarr-movies"
4. Verify VPN is active:
   ```bash
   docker exec gluetun curl -s ifconfig.me
   # Should show VPN IP, NOT home IP
   ```

**Step 5: Watch Download Progress**

```bash
# Monitor Radarr activity
# Radarr → Activity → Queue

# Check Deluge logs
docker logs deluge --tail 20

# Watch file system
watch -n 5 'ls -lh /data/media/downloads/complete/movies/'
```

**Step 6: Verify Import**

When download completes (15 min to 2 hours):

```bash
# Check if file was imported
ls -lh /data/media/movies/

# Should show: Inception (2010)/
#              └─ Inception (2010) - 1080p.mkv

# Check permissions
ls -la /data/media/movies/"Inception (2010)"/
# Should be: drwxrwxr-x root:media
```

**Step 7: Verify Jellyfin Detection**

1. Open Jellyfin: `http://nuc-server:8096`
2. Go to **Movies** library
3. Movie should appear automatically
4. Click on movie to verify metadata loaded

**Step 8: Test Playback with Transcoding**

1. Start playing the movie
2. Change quality to 720p to force transcoding
3. Dashboard → Activity → Should show "Transcode (hw)"
4. Monitor CPU usage:
   ```bash
   htop
   # CPU should be <20% with hardware transcoding
   ```

**Step 9: Check Subtitles (Bazarr)**

Wait 5-10 minutes after import, then:

```bash
# Check for subtitle files
ls -lh /data/media/movies/"Inception (2010)"/
# Should see: Inception (2010) - 1080p.en.srt

# Or check in Bazarr
# http://nuc-server:6767 → Movies
# Should show subtitle downloaded
```

**Step 10: Verify Jellyseerr Status**

1. Open Jellyseerr: `http://nuc-server:5055`
2. Go to **Requests** page
3. Movie status should be **"Available"**
4. Green badge should appear on movie card

### Test 2: TV Show Request Workflow

**Step 1: Request TV Show**

1. In Jellyseerr, search for a TV show
2. Example: "Breaking Bad"
3. Click on show → Select seasons
4. Request **Latest Season** or **All Seasons**
5. Click **"Request"**

**Step 2: Verify in Sonarr**

1. Open Sonarr: `http://nuc-server:8989`
2. Go to **Series** tab
3. Should see "Breaking Bad" added
4. Check which seasons are monitored

**Step 3: Monitor Episode Downloads**

1. Open Deluge: `http://nuc-server:8112`
2. Should see episode torrents with category "sonarr-tv"
3. Multiple torrents may appear (one per episode or season pack)

**Step 4: Verify Import**

```bash
# Check TV directory
ls -lh /data/media/tv/

# Should show: Breaking Bad (2008)/
#              ├─ Season 01/
#              │  ├─ Breaking Bad - S01E01 - Pilot [1080p].mkv
#              │  └─ Breaking Bad - S01E01 - Pilot [1080p].en.srt
#              └─ Season 02/
#                 └─ ...

# Check in Jellyfin
# Go to TV Shows library → Should see Breaking Bad
```

**Step 5: Verify Complete Workflow**

✅ **Request submitted** → Jellyseerr  
✅ **Added to Sonarr** → Automatic  
✅ **Searched indexers** → Prowlarr  
✅ **Sent to Deluge** → Via VPN  
✅ **Downloaded** → VPN-isolated  
✅ **Imported** → Sonarr to `/data/media/tv`  
✅ **Subtitles fetched** → Bazarr  
✅ **Detected by Jellyfin** → Automatic  
✅ **Status updated** → Jellyseerr "Available"  
✅ **Ready to watch** → Jellyfin  

### Test 3: Family Member Experience

**Sign in as regular user:**

1. Create test user account in Jellyfin (if not already done)
2. Sign into Jellyseerr with user credentials
3. Request a movie/TV show
4. Verify:
   - User can browse content
   - User can make requests
   - User sees request status
   - Request limit is enforced (if configured)
   - User can watch in Jellyfin when available

### Workflow Testing Checklist

- [ ] Movie request workflow tested end-to-end
- [ ] TV show request workflow tested end-to-end
- [ ] VPN isolation verified (downloads through VPN)
- [ ] Radarr imports movies correctly
- [ ] Sonarr imports episodes correctly
- [ ] Bazarr downloads subtitles
- [ ] Jellyfin detects new content automatically
- [ ] Hardware transcoding works (CPU <20%)
- [ ] Jellyseerr status updates to "Available"
- [ ] Family member can request and watch content

---

## 8. Service Access Reference

### Local Network Access

When connected to your home network:

| Service | Port | URL | Purpose |
|---------|------|-----|---------|
| **Jellyfin** | 8096 | http://localhost:8096 | Media streaming |
| **Jellyseerr** | 5055 | http://localhost:5055 | Request interface |
| **Radarr** | 7878 | http://localhost:7878 | Movie management |
| **Sonarr** | 8989 | http://localhost:8989 | TV management |
| **Prowlarr** | 9696 | http://localhost:9696 | Indexer management |
| **Bazarr** | 6767 | http://localhost:6767 | Subtitle management |
| **Deluge** | 8112 | http://localhost:8112 | Torrent client |

### Tailscale VPN Access

For remote admin access (requires Tailscale installed):

| Service | URL | Access Level |
|---------|-----|--------------|
| **Jellyfin** | http://nuc-server:8096 | Full (family) |
| **Jellyseerr** | http://nuc-server:5055 | Full (family) |
| **Radarr** | http://nuc-server:7878 | Admin only |
| **Sonarr** | http://nuc-server:8989 | Admin only |
| **Prowlarr** | http://nuc-server:9696 | Admin only |
| **Bazarr** | http://nuc-server:6767 | Admin only |
| **Deluge** | http://nuc-server:8112 | Admin only |
| **SSH** | ssh somesh@nuc-server | Admin only |

### Default Credentials

⚠️ **CHANGE ALL DEFAULT PASSWORDS IMMEDIATELY**

| Service | Default Username | Default Password | Action Required |
|---------|-----------------|------------------|-----------------|
| **Deluge** | admin | deluge | ✅ Change in Preferences |
| **Jellyfin** | (your choice) | (your choice) | Set during wizard |
| **Radarr** | (your choice) | (your choice) | Set during wizard |
| **Sonarr** | (your choice) | (your choice) | Set during wizard |
| **Prowlarr** | (your choice) | (your choice) | Set during wizard |
| **Bazarr** | (your choice) | (your choice) | Set during wizard |
| **Jellyseerr** | (Jellyfin auth) | (Jellyfin auth) | Uses Jellyfin login |

### Service Dependencies

```
Jellyseerr
    ├─► Jellyfin (authentication, availability)
    ├─► Radarr (movie requests)
    └─► Sonarr (TV requests)

Radarr / Sonarr
    ├─► Prowlarr (search indexers)
    ├─► Deluge (download client)
    └─► Jellyfin (optional: notify on import)

Deluge
    └─► Gluetun (VPN tunnel)

Bazarr
    ├─► Radarr (movie subtitles)
    └─► Sonarr (TV subtitles)

Jellyfin
    └─► ZFS datasets (media libraries)
```

---

## 9. Common Issues and Troubleshooting

### Issue 1: ZFS Datasets Not Mounting

**Symptoms:**
- Services fail to start after reboot
- `/data` directory is empty
- Error: "Transport endpoint not connected"

**Solutions:**

```bash
# Check if ZFS pool is imported
zpool status storagepool

# If pool not imported, import manually
sudo zpool import storagepool

# Check if datasets are mounted
zfs list | grep storagepool
df -h | grep storagepool

# Remount if needed
sudo zfs mount -a

# Restart services
sudo systemctl restart jellyfin radarr sonarr bazarr prowlarr jellyseerr
```

**Prevention:**
- Ensure `boot.zfs.extraPools = [ "storagepool" ];` in configuration.nix
- Check systemd service dependencies include `zfs-mount.service`

### Issue 2: Docker Compose Fails to Start

**Symptoms:**
- Gluetun or Deluge won't start
- Error: "network not found" or "service unavailable"

**Solutions:**

```bash
# Check Docker service
sudo systemctl status docker

# Restart Docker
sudo systemctl restart docker

# Remove old containers and networks
cd ~/nixos-homelab-v2/docker/deluge-vpn
docker-compose down
docker-compose up -d

# Check logs
docker logs gluetun
docker logs deluge

# Verify .env file exists and has credentials
cat .env | grep VPN_USERNAME
```

### Issue 3: VPN Not Connecting

**Symptoms:**
- Gluetun logs show "connection failed"
- Deluge can't reach internet
- VPN IP check shows home IP

**Solutions:**

```bash
# Check Gluetun logs for specific error
docker logs gluetun | tail -50

# Common fixes:

# 1. Wrong credentials
nano ~/nixos-homelab-v2/docker/deluge-vpn/.env
# Verify VPN_USERNAME and VPN_PASSWORD

# 2. Server unavailable
# Change SERVER_COUNTRIES in .env
# Try: Netherlands, Germany, United States

# 3. Restart VPN stack
docker restart gluetun
docker restart deluge

# 4. Check firewall allows VPN
sudo iptables -L -n | grep -E "51820|1194"

# Verify VPN is working
docker exec gluetun curl -s ifconfig.me
# Should NOT be your home IP
```

### Issue 4: Services Can't Communicate

**Symptoms:**
- Radarr can't connect to Deluge
- Prowlarr can't connect to Radarr/Sonarr
- Error: "Connection refused" or "Timeout"

**Solutions:**

```bash
# Check all services are running
sudo systemctl status jellyfin radarr sonarr bazarr prowlarr jellyseerr
docker ps | grep -E "gluetun|deluge"

# Test service connectivity
curl http://localhost:8096  # Jellyfin
curl http://localhost:7878/api/v3/system/status  # Radarr (needs API key)
curl http://localhost:8989/api/v3/system/status  # Sonarr (needs API key)
nc -zv localhost 58846  # Deluge daemon

# Check firewall isn't blocking localhost
sudo iptables -L -n | grep 127.0.0.1

# Restart services in order
sudo systemctl restart prowlarr
sudo systemctl restart radarr sonarr
sudo systemctl restart bazarr
sudo systemctl restart jellyseerr
```

### Issue 5: Permission Errors

**Symptoms:**
- Radarr/Sonarr can't import files
- Error: "Permission denied"
- Files in downloads but not in media folders

**Solutions:**

```bash
# Fix media directory permissions
sudo chown -R root:media /data/media/movies
sudo chown -R root:media /data/media/tv
sudo chown -R root:media /data/media/downloads
sudo chmod -R 775 /data/media/movies
sudo chmod -R 775 /data/media/tv
sudo chmod -R 775 /data/media/downloads

# Verify service users are in media group
groups radarr
groups sonarr
groups jellyfin
# Should all include "media"

# Check file chmod mask in *arr settings
# Should be: 0775

# Restart services
sudo systemctl restart radarr sonarr
```

### Issue 6: Hardware Transcoding Not Working

**Symptoms:**
- High CPU usage during playback (>80%)
- Jellyfin Dashboard shows "Transcode (sw)"
- Slow/stuttering playback

**Solutions:**

```bash
# Verify GPU device exists
ls -la /dev/dri/renderD128

# Check jellyfin user has access
groups jellyfin
# Should include: render, video

# Test VAAPI
vainfo --display drm --device /dev/dri/renderD128
# Should list codecs

# If not working, rebuild NixOS config
sudo nixos-rebuild switch

# Restart Jellyfin
sudo systemctl restart jellyfin

# Re-configure in Jellyfin:
# Dashboard → Playback → Transcoding
# Hardware acceleration: VAAPI
# VA-API Device: /dev/dri/renderD128
```

### Issue 7: Downloads Not Importing

**Symptoms:**
- Download completes in Deluge
- File stays in `/data/media/downloads/complete/`
- Never moves to movies/tv folder

**Solutions:**

```bash
# Check Deluge categories are correct
# Open Deluge UI → Check torrent category

# Verify download paths in *arr settings
# Radarr → Settings → Download Clients
# Category should be: radarr-movies

# Check file permissions on downloads
ls -la /data/media/downloads/complete/
# Should be readable by media group

# Check Radarr/Sonarr activity
# Activity → Queue → Manual Import (if needed)

# Force re-scan
# Radarr → System → Tasks → RSS Sync → Run

# Check logs for import errors
sudo journalctl -u radarr -n 100 | grep -i import
sudo journalctl -u sonarr -n 100 | grep -i import
```

---

## 10. Verification Commands

### Quick Health Check

Run this comprehensive health check:

```bash
#!/bin/bash
# Media Server Health Check

echo "=== SERVICE STATUS ==="
sudo systemctl status jellyfin --no-pager -l | head -3
sudo systemctl status radarr --no-pager -l | head -3
sudo systemctl status sonarr --no-pager -l | head -3
sudo systemctl status bazarr --no-pager -l | head -3
sudo systemctl status prowlarr --no-pager -l | head -3
sudo systemctl status jellyseerr --no-pager -l | head -3

echo -e "\n=== DOCKER CONTAINERS ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo -e "\n=== VPN STATUS ==="
docker exec gluetun curl -s ifconfig.me
echo " <- VPN IP (should NOT be your home IP)"

echo -e "\n=== ZFS DATASETS ==="
zfs list -o name,used,avail,quota,mountpoint | grep storagepool | head -10

echo -e "\n=== DISK SPACE ==="
df -h | grep -E "storagepool|Filesystem"

echo -e "\n=== RECENT ERRORS ==="
sudo journalctl -p err --since "1 hour ago" --no-pager | tail -10

echo -e "\n=== NETWORK PORTS ==="
sudo ss -tulpn | grep -E "8096|5055|7878|8989|9696|6767|8112"
```

Save as `/usr/local/bin/health-check.sh` and run: `bash /usr/local/bin/health-check.sh`

### Individual Service Checks

```bash
# Check specific service
sudo systemctl status jellyfin

# View service logs (last 50 lines)
sudo journalctl -u jellyfin -n 50 --no-pager

# Follow service logs in real-time
sudo journalctl -u radarr -f

# Check if service is listening on port
sudo ss -tulpn | grep 8096  # Jellyfin

# Test service API
curl -I http://localhost:8096  # Should return HTTP 200
```

### ZFS Health Checks

```bash
# Pool status
zpool status storagepool

# Dataset list with quotas
zfs list -o name,used,avail,quota,refer

# Check for ZFS errors
zpool status -v | grep -i error

# Recent snapshots
zfs list -t snapshot | tail -10

# Disk space by dataset
zfs list -o name,used,refer | sort -h -k 2
```

### VPN and Network Checks

```bash
# Verify VPN is connected
docker logs gluetun | grep -i "wireguard is up"

# Check VPN IP
docker exec gluetun curl -s ifconfig.me

# Check your real home IP
curl -s ifconfig.me

# Test DNS resolution
docker exec gluetun nslookup google.com

# Check Deluge is using VPN network
docker inspect deluge | grep NetworkMode
# Should show: service:gluetun
```

### Permission and Ownership Checks

```bash
# Check media directories
ls -la /data/media/

# Verify group ownership
ls -ld /data/media/movies /data/media/tv
# Should show: drwxrwxr-x root:media

# Check service config directories
ls -la /var/lib/ | grep -E "radarr|sonarr|jellyfin"

# Verify users in media group
getent group media
```

---

## 11. Maintenance Tasks

### Daily Automated Tasks

These run automatically via systemd/cron:

- ✅ ZFS auto-scrub (weekly)
- ✅ Docker auto-prune (weekly)
- ✅ Service monitoring (continuous)

### Weekly Manual Checks

**Every Monday (15 minutes):**

```bash
# 1. Check service health
bash /usr/local/bin/health-check.sh

# 2. Review disk space
zfs list -o name,used,avail,quota | grep -E "movies|tv|downloads"

# 3. Check for failed downloads
# Open Radarr → Activity → Queue
# Open Sonarr → Activity → Queue

# 4. Review recent errors
sudo journalctl -p err --since "1 week ago" | less

# 5. Check VPN status
docker logs gluetun | tail -20

# 6. Update Jellyseerr requests
# Open Jellyseerr → Requests → Check status
```

### Monthly Tasks

**First of each month (30-45 minutes):**

```bash
# 1. Update NixOS and services
sudo nix-channel --update
sudo nixos-rebuild switch --upgrade

# 2. Restart services after updates
sudo systemctl restart jellyfin radarr sonarr bazarr prowlarr jellyseerr
docker restart gluetun deluge

# 3. Review user permissions
# Jellyseerr → Settings → Users → Review limits

# 4. Check indexer health
# Prowlarr → Indexers → Test all

# 5. Clean old downloads
find /data/media/downloads/complete/ -type f -mtime +30 -delete

# 6. Backup configurations
sudo rsync -av /var/lib/jellyfin/ /backups/jellyfin-$(date +%Y%m%d)/
sudo rsync -av /var/lib/radarr/ /backups/radarr-$(date +%Y%m%d)/
sudo rsync -av /var/lib/sonarr/ /backups/sonarr-$(date +%Y%m%d)/
sudo rsync -av /var/lib/jellyseerr/ /backups/jellyseerr-$(date +%Y%m%d)/

# 7. Review ZFS snapshots
zfs list -t snapshot | wc -l  # Check count
# Prune old snapshots if needed
```

### Quarterly Tasks

**Every 3 months (1-2 hours):**

```bash
# 1. Full system backup
sudo tar -czf /backups/full-system-$(date +%Y%m%d).tar.gz \
  /etc/nixos/ \
  /var/lib/jellyfin/ \
  /var/lib/radarr/ \
  /var/lib/sonarr/ \
  /var/lib/bazarr/ \
  /var/lib/prowlarr/ \
  /var/lib/jellyseerr/

# 2. Test disaster recovery
# Practice restoring from backup on test VM

# 3. Rotate API keys
# Regenerate API keys in all services
# Update connections

# 4. Security audit
# Review firewall rules
# Check for unauthorized access attempts
# Review user permissions

# 5. Performance review
# Check transcode performance
# Review disk I/O
# Optimize quality profiles if needed

# 6. Hardware check
# Monitor disk SMART status
# Check temperatures
# Verify hardware transcoding still working
```

### Backup Script

Save as `/usr/local/bin/backup-media-server.sh`:

```bash
#!/bin/bash
# Media Server Backup Script

BACKUP_ROOT="/backups"
DATE=$(date +%Y%m%d)

echo "Starting backup: $(date)"

# Create backup directory
mkdir -p "$BACKUP_ROOT"

# Backup NixOS configuration
echo "Backing up NixOS configuration..."
sudo tar -czf "$BACKUP_ROOT/nixos-config-$DATE.tar.gz" /etc/nixos/

# Backup service configurations
echo "Backing up service configurations..."
for service in jellyfin radarr sonarr bazarr prowlarr jellyseerr; do
  if [ -d "/var/lib/$service" ]; then
    sudo rsync -av "/var/lib/$service/" "$BACKUP_ROOT/$service-$DATE/"
  fi
done

# Backup Docker configs
echo "Backing up Docker configurations..."
sudo rsync -av ~/nixos-homelab-v2/docker/ "$BACKUP_ROOT/docker-$DATE/"

# Create ZFS snapshots
echo "Creating ZFS snapshots..."
for dataset in $(zfs list -H -o name | grep storagepool/services); do
  sudo zfs snapshot "$dataset@backup-$DATE"
done

# Cleanup old backups (keep last 7 days)
echo "Cleaning up old backups..."
find "$BACKUP_ROOT" -name "*-20*" -mtime +7 -delete 2>/dev/null

echo "Backup completed: $(date)"
```

Make executable: `sudo chmod +x /usr/local/bin/backup-media-server.sh`

---

## 12. Performance Monitoring

### Real-Time Monitoring

**Monitor system resources:**

```bash
# CPU, Memory, Processes
htop

# Disk I/O
sudo iotop

# Network usage
sudo iftop

# GPU usage (Intel)
intel_gpu_top
```

### Service-Specific Monitoring

**Jellyfin Performance:**

1. Dashboard → Activity
   - Active streams
   - Transcode type (hw/sw)
   - Bandwidth usage

2. Dashboard → Logs
   - Recent errors
   - Performance warnings

**Download Performance:**

```bash
# Check active downloads
docker exec deluge deluge-console info

# Monitor network through VPN
docker exec gluetun iftop
```

**ZFS Performance:**

```bash
# I/O statistics
zpool iostat storagepool 5  # Update every 5 seconds

# ARC cache statistics
arcstat

# Dataset compression ratios
zfs get compressratio storagepool/media/movies
zfs get compressratio storagepool/media/tv
```

### Performance Metrics to Watch

| Metric | Healthy Range | Action If Exceeded |
|--------|---------------|-------------------|
| CPU Usage (idle) | <10% | Check for runaway processes |
| CPU Usage (transcode) | <20% | Verify hardware transcoding |
| Memory Usage | <12GB of 16GB | Check for memory leaks |
| Disk I/O (sequential) | ~100 MB/s | Normal for USB HDD |
| Disk I/O (random) | <50 IOPS | Expected for HDD |
| ZFS ARC hit rate | >80% | Increase RAM if possible |
| Network (LAN streaming) | <50 Mbps/stream | Normal for 1080p |
| Download speed (VPN) | 20-80 Mbps | Depends on VPN server |

### Performance Optimization Tips

**For Jellyfin:**
- Always use hardware transcoding
- Limit concurrent streams to 3-5
- Pre-transcode 4K content if needed
- Use direct play when possible

**For Downloads:**
- Limit active downloads to 3-5
- Set reasonable upload limits
- Use download scheduling for off-peak hours

**For ZFS:**
- Keep pool under 80% capacity
- Regular scrubs (weekly)
- Monitor compression ratios
- Use appropriate recordsize per dataset

**For Overall System:**
- Keep 2-4GB RAM free for cache
- Monitor temperatures (keep under 70°C)
- Update services monthly
- Regular reboots (monthly)

---

## 13. Family Member Onboarding

### Creating Accounts

**Step 1: Create Jellyfin Account**

1. Jellyfin → Dashboard → Users → **+ New User**
2. Enter family member's name and password
3. Set permissions (enable playback, downloads optional)
4. Select libraries (Movies, TV Shows)
5. Click **Save**

**Step 2: Sync to Jellyseerr**

1. Jellyseerr → Settings → Jellyfin → **Sync Libraries**
2. Verify user appears in Settings → Users
3. Configure request limits for user

**Step 3: Configure User Device**

Help family member set up their device:

**Mobile (iOS/Android):**
1. Install Jellyfin app from App Store/Play Store
2. Add server: `http://nuc-server:8096` (or Tailscale IP)
3. Sign in with their credentials
4. Configure playback settings

**Smart TV (Roku/Fire TV):**
1. Install Jellyfin channel/app
2. Note the code displayed on TV
3. Go to: `http://jellyfin.org/link`
4. Enter code to link account

**Desktop/Laptop:**
1. Use web browser: `http://nuc-server:8096`
2. Or install Jellyfin Media Player
3. Sign in with credentials

### Quick User Guide

Print or send this guide to family members:

---

**📺 How to Watch Media**

1. **Open Jellyfin App**
   - Website: http://nuc-server:8096
   - Or use Jellyfin app on your device

2. **Sign In**
   - Username: [your name]
   - Password: [your password]

3. **Browse and Watch**
   - Browse Movies or TV Shows library
   - Click on any title to watch
   - Playback starts automatically

**🎬 How to Request New Content**

1. **Open Jellyseerr**
   - Website: http://nuc-server:5055
   - Use same username/password as Jellyfin

2. **Find What You Want**
   - Browse popular/trending content
   - Or use search bar

3. **Request It**
   - Click on the title
   - Click "Request" button
   - Confirm your request

4. **Wait for Download**
   - Check "Requests" page for status
   - Usually takes 1-6 hours
   - You'll see when it's "Available"

5. **Watch in Jellyfin**
   - Once available, open Jellyfin
   - Your requested content appears in library

**📌 Tips:**
- Check if content exists before requesting
- You can request up to 10 movies per week
- TV shows: Request specific seasons or all seasons
- For help, contact [your name]

---

### Troubleshooting for Users

**Common User Issues:**

**Problem:** "Can't sign in"
- **Solution:** Use same username/password as Jellyfin. Contact admin if forgot password.

**Problem:** "Buffering/slow playback"
- **Solution:** 
  - Check your internet connection
  - Lower playback quality in player settings
  - Try different device

**Problem:** "Requested content not appearing"
- **Solution:**
  - Check "Requests" page in Jellyseerr for status
  - Downloads can take 1-6 hours
  - Contact admin if stuck for >24 hours

**Problem:** "No subtitles available"
- **Solution:**
  - Subtitles added automatically (give it 10-15 minutes after movie appears)
  - In player, click CC button to enable
  - Contact admin if missing

### Device Recommendations

**Best Experience:**

- **Smart TV:** Roku, Fire TV, Apple TV with Jellyfin app
- **Mobile:** Official Jellyfin app (free)
- **Desktop:** Web browser (Chrome/Firefox) or Jellyfin Media Player app
- **Alternative:** Infuse app (iOS/Apple TV, paid but beautiful UI)

---

## 14. Next Steps and Future Enhancements

### Immediate Post-Deployment

**Week 1-2 After Deployment:**

1. **Monitor System Stability**
   - Check services daily for first week
   - Watch for any recurring errors
   - Monitor disk space usage
   - Verify VPN stays connected

2. **Add Initial Media**
   - Request 5-10 popular movies
   - Request 2-3 TV shows
   - Test complete workflow
   - Verify quality and transcoding

3. **Fine-Tune Settings**
   - Adjust quality profiles based on results
   - Optimize download/upload speeds
   - Configure subtitle preferences
   - Set up email notifications

4. **Family Onboarding**
   - Create accounts for each family member
   - Install apps on their devices
   - Walk through request process
   - Share quick user guide

### Month 1-3: Optimization Phase

**Tailscale Setup (Priority: High)**

If not already configured:

```bash
# Install Tailscale
sudo tailscale up

# Authenticate via browser
# Copy your Tailscale IP: tailscale ip -4

# Enable MagicDNS in Tailscale admin console
# Access services: http://nuc-server:8096
```

**Benefits:**
- Secure remote access from anywhere
- No port forwarding needed
- End-to-end encryption
- Easy family member setup

**Monitoring Setup (Optional)**

Add basic monitoring:

```bash
# Install Prometheus and Grafana (future enhancement)
# For now, use basic monitoring scripts

# Create monitoring cron job
sudo crontab -e

# Add:
# 0 * * * * /usr/local/bin/health-check.sh >> /var/log/media-server-health.log
```

**Backup Automation**

Set up automatic backups:

```bash
# Add to crontab
sudo crontab -e

# Daily config backups at 2 AM
0 2 * * * /usr/local/bin/backup-media-server.sh

# Weekly ZFS snapshots
0 3 * * 0 for dataset in $(zfs list -H -o name | grep services); do zfs snapshot "$dataset@weekly-$(date +\%Y\%m\%d)"; done
```

### Month 3-6: Enhancement Phase

**Cloudflare Tunnel for Public Access**

Enable family access from outside network:

1. **Create Cloudflare Account**
   - Sign up at cloudflare.com
   - Add your domain (if you have one)

2. **Install Cloudflared**

```nix
# Add to configuration.nix
services.cloudflared = {
  enable = true;
  tunnels = {
    homelab = {
      credentialsFile = "/var/lib/cloudflared/credentials.json";
      default = "http_status:404";
      ingress = {
        "jellyfin.yourdomain.com" = "http://localhost:8096";
        "request.yourdomain.com" = "http://localhost:5055";
      };
    };
  };
};
```

3. **Setup DNS**
   - Create CNAME records in Cloudflare
   - Point to tunnel ID
   - Enable proxy (orange cloud)

**Benefits:**
- HTTPS encryption automatic
- DDoS protection
- CDN for better performance
- No port forwarding needed

**Advanced Download Automation**

Consider adding:

- **Autobrr**: Automated torrent grabbing from IRC/RSS
- **FlexGet**: Advanced automation rules
- **Tdarr**: Automated media transcoding/optimization
- **Recyclarr**: Automated quality profile management

### Long-Term Enhancements

**Additional Services to Consider:**

**Media Services:**
- **Audiobookshelf**: Audiobook and podcast management
- **Navidrome**: Music streaming (Subsonic-compatible)
- **Calibre-Web**: Ebook library management
- **Komga**: Comic/manga reader

**Productivity:**
- **Nextcloud**: File sync, calendar, contacts
- **Vaultwarden**: Password manager (Bitwarden)
- **Immich**: Photo backup and management (Google Photos alternative)

**Home Automation:**
- **Home Assistant**: Smart home control
- **AdGuard Home**: Network-wide ad blocking
- **Wireguard**: Alternative VPN for remote access

**Monitoring & Management:**
- **Grafana + Prometheus**: Advanced monitoring
- **Uptime Kuma**: Service uptime monitoring
- **Portainer**: Docker management UI

**Implementation Priority:**

1. **High Priority** (Next 3 months):
   - ✅ Tailscale setup
   - ✅ Automated backups
   - ✅ Basic monitoring

2. **Medium Priority** (Next 6 months):
   - ⏳ Cloudflare Tunnel
   - ⏳ Nextcloud (file sync)
   - ⏳ Vaultwarden (passwords)

3. **Low Priority** (When needed):
   - ⏳ Additional media services
   - ⏳ Advanced monitoring
   - ⏳ Home automation

### Hardware Upgrades to Consider

**If Performance Issues:**

- **More RAM**: Upgrade to 32GB if running many services
- **Faster Storage**: Add SSD cache for ZFS (L2ARC)
- **Better CPU**: Upgrade to N200/N300 for more concurrent transcodes
- **Network**: Upgrade to 2.5Gbps NIC for faster transfers

**If Storage Full:**

- **Larger HDD**: Upgrade to 24TB or 32TB drive
- **Multiple Drives**: Add second drive, create mirror or RAIDZ
- **External Backup**: Add separate backup drive

### Security Hardening

**After Initial Setup:**

```bash
# Disable password authentication (use SSH keys only)
# Edit /etc/nixos/configuration.nix:
services.openssh.settings.PasswordAuthentication = false;

# Disable root login
services.openssh.settings.PermitRootLogin = "no";

# Enable fail2ban
services.fail2ban.enable = true;

# Regular security updates
sudo nix-channel --update
sudo nixos-rebuild switch --upgrade
```

**Best Practices:**
- Change all default passwords immediately
- Rotate API keys annually
- Review user permissions quarterly
- Monitor failed login attempts
- Keep VPN credentials secure
- Regular security audits

### Community and Support

**Resources:**

- **NixOS Manual**: https://nixos.org/manual/nixos/stable/
- **Self-Hosted Community**: r/selfhosted on Reddit
- **Homelab Community**: r/homelab on Reddit
- **Jellyfin Docs**: https://jellyfin.org/docs/
- **Servarr Wiki**: https://wiki.servarr.com/

**Getting Help:**

- NixOS Discourse: discourse.nixos.org
- Jellyfin Forum: forum.jellyfin.org
- *arr Discord servers
- GitHub issues for specific services

### Documentation Maintenance

**Keep Your Docs Updated:**

```bash
# Create local documentation
mkdir -p ~/docs/media-server

# Document your customizations
vim ~/docs/media-server/custom-settings.md

# Track changes
cd /etc/nixos
git init
git add .
git commit -m "Initial media server configuration"

# Push to private repo (recommended)
git remote add origin <your-private-repo>
git push -u origin main
```

**What to Document:**

- Custom quality profiles
- Indexer configurations
- API keys and passwords (encrypted!)
- Network configuration
- Custom scripts
- Troubleshooting notes
- Lessons learned

---

## Conclusion

**🎉 Congratulations!** You've successfully deployed a complete, automated media server stack!

### What You've Accomplished

✅ **Infrastructure**: ZFS storage, Docker, firewall protection  
✅ **VPN-Isolated Downloads**: Secure torrenting via Surfshark  
✅ **Media Streaming**: Jellyfin with hardware transcoding  
✅ **Automated Acquisition**: Complete *arr stack integration  
✅ **User-Friendly Requests**: Jellyseerr for family members  
✅ **End-to-End Workflow**: Request → Download → Import → Watch  

### System Capabilities

**You Can Now:**

- Stream media to any device in your home
- Request new content with a few clicks
- Automatically download high-quality releases
- Watch with hardware-accelerated transcoding
- Enjoy subtitles in multiple languages
- Manage everything through intuitive web interfaces
- Access remotely via Tailscale VPN
- Scale to add more services as needed

### Maintenance Schedule

**Daily**: Automated (ZFS, Docker, services)  
**Weekly**: 15-minute health check  
**Monthly**: 30-minute updates and review  
**Quarterly**: 1-hour backup test and security audit  

### Getting the Most Out of Your System

**For Best Experience:**

1. **Quality Over Quantity**: Start with a curated library
2. **Regular Maintenance**: Follow the weekly checklist
3. **Monitor Performance**: Keep an eye on disk space and CPU
4. **Security First**: Keep services updated, use strong passwords
5. **Document Changes**: Note customizations and learnings
6. **Backup Regularly**: Test disaster recovery procedures
7. **Stay Informed**: Follow community updates and security news

### Next Actions

**Immediate (Today):**
- [ ] Complete end-to-end workflow test
- [ ] Create family member accounts
- [ ] Document your API keys securely
- [ ] Set up automated backups

**This Week:**
- [ ] Install Jellyfin apps on family devices
- [ ] Request 5-10 initial movies/shows
- [ ] Monitor system stability daily
- [ ] Fine-tune quality profiles

**This Month:**
- [ ] Set up Tailscale for remote access
- [ ] Configure email notifications
- [ ] Establish maintenance routine
- [ ] Review and adjust settings

### Support and Resources

**If You Need Help:**

1. Check this guide's troubleshooting section
2. Review service-specific setup guides in `docs/`
3. Check service logs: `sudo journalctl -u <service>`
4. Search community forums (r/selfhosted, r/homelab)
5. Consult official documentation for each service

**Additional Guides in This Repo:**

- [`docs/media-server-architecture.md`](media-server-architecture.md) - Complete system architecture
- [`docs/jellyfin-setup.md`](jellyfin-setup.md) - Detailed Jellyfin configuration
- [`docs/arr-stack-setup.md`](arr-stack-setup.md) - Complete *arr stack setup
- [`docs/jellyseerr-setup.md`](jellyseerr-setup.md) - Jellyseerr configuration
- [`docker/deluge-vpn/README.md`](../docker/deluge-vpn/README.md) - VPN setup details

### Final Thoughts

You now have a powerful, automated, self-hosted media server that rivals commercial services. The system is:

- **Private**: Your data stays on your hardware
- **Automated**: Minimal manual intervention needed
- **Secure**: VPN isolation, firewall protection, encrypted access
- **Scalable**: Easy to add more services and storage
- **Cost-Effective**: No monthly subscription fees
- **Family-Friendly**: Easy for anyone to use

**Enjoy your personal Netflix!** 🍿🎬📺

---

## Quick Reference Card

### Essential URLs (via Tailscale)

```
Jellyfin:    http://nuc-server:8096  (Watch content)
Jellyseerr:  http://nuc-server:5055  (Request content)
Radarr:      http://nuc-server:7878  (Manage movies - admin)
Sonarr:      http://nuc-server:8989  (Manage TV - admin)
Prowlarr:    http://nuc-server:9696  (Manage indexers - admin)
Bazarr:      http://nuc-server:6767  (Manage subtitles - admin)
Deluge:      http://nuc-server:8112  (Manage downloads - admin)
SSH:         ssh somesh@nuc-server   (System access - admin)
```

### Critical Commands

```bash
# Service status
sudo systemctl status jellyfin radarr sonarr bazarr prowlarr jellyseerr

# Restart service
sudo systemctl restart <service>

# View logs
sudo journalctl -u <service> -f

# Check VPN
docker exec gluetun curl -s ifconfig.me

# ZFS status
zpool status storagepool
zfs list -o name,used,avail,quota

# Disk space
df -h | grep storagepool

# Health check
bash /usr/local/bin/health-check.sh

# Backup
bash /usr/local/bin/backup-media-server.sh
```

### Important Paths

```
Media:      /data/media/movies, /data/media/tv
Downloads:  /data/media/downloads/complete
Configs:    /var/lib/<service>
Logs:       sudo journalctl -u <service>
Docker:     ~/nixos-homelab-v2/docker/deluge-vpn
NixOS:      /etc/nixos/configuration.nix
Backups:    /backups
```

### Emergency Contacts

```
Admin:     [Your name and contact]
VPN:       support@surfshark.com
NixOS:     discourse.nixos.org
Services:  Check service-specific docs
```

---

**Document Version:** 1.0  
**Last Updated:** 2025-10-23  
**Next Review:** After 30 days of operation  
**Status:** Production Ready ✅

---

*Happy streaming! If you found this guide helpful, consider contributing back to the self-hosted community by sharing your experiences and improvements.* 🚀