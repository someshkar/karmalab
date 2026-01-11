# Jellyfin Media Server Setup Guide

**Version:** 1.0  
**Date:** 2025-10-23  
**System:** Intel NUC N150 with NixOS  
**Jellyfin Port:** 8096 (HTTP)

---

## Overview

Jellyfin is your self-hosted media streaming server, providing Netflix-like experience for your personal movie and TV show collection. This guide covers complete setup, configuration, and optimization for your Intel N150 system with hardware-accelerated transcoding.

**Key Features:**
- 🎬 Stream movies and TV shows to any device
- 🚀 Hardware transcoding via Intel Quick Sync (3-5 concurrent 1080p streams)
- 📱 Native apps for iOS, Android, Fire TV, Roku, etc.
- 👨‍👩‍👧‍👦 Multiple user accounts with parental controls
- 🌐 Remote access via Tailscale (later: Cloudflare Tunnel)

---

## Table of Contents

1. [Initial Deployment](#1-initial-deployment)
2. [First-Time Setup Wizard](#2-first-time-setup-wizard)
3. [Adding Media Libraries](#3-adding-media-libraries)
4. [Configuring Hardware Transcoding](#4-configuring-hardware-transcoding)
5. [Creating User Accounts](#5-creating-user-accounts)
6. [Network Access](#6-network-access)
7. [Client Applications](#7-client-applications)
8. [Optimization Settings](#8-optimization-settings)
9. [Troubleshooting](#9-troubleshooting)
10. [Maintenance](#10-maintenance)

---

## 1. Initial Deployment

### Apply NixOS Configuration

```bash
# Navigate to NixOS config directory
cd /etc/nixos

# Test the configuration (dry-run)
sudo nixos-rebuild dry-build --flake .#nuc-server

# Apply the configuration
sudo nixos-rebuild switch --flake .#nuc-server
```

### Verify Service Status

```bash
# Check if Jellyfin is running
sudo systemctl status jellyfin

# Expected output:
# ● jellyfin.service - Jellyfin Media Server
#    Loaded: loaded
#    Active: active (running)
#    ...

# Check service logs
sudo journalctl -u jellyfin -f
```

### Verify Hardware Access

```bash
# Check if jellyfin user has access to GPU
ls -la /dev/dri/
# Should show: renderD128, card0

# Verify jellyfin user groups
groups jellyfin
# Should include: media, render, video
```

### Verify ZFS Mounts

```bash
# Check if datasets are mounted
zfs list | grep jellyfin
# Should show:
# storagepool/services/jellyfin/config  → /var/lib/jellyfin
# storagepool/services/jellyfin/cache   → /var/cache/jellyfin

df -h | grep jellyfin
# Should show both directories mounted
```

---

## 2. First-Time Setup Wizard

### Access Jellyfin Web UI

**Local Access:**
```
http://localhost:8096
```

**From another device on your network:**
```
http://192.168.x.x:8096
(Replace with your server's IP address)
```

**Via Tailscale (recommended for remote access):**
```
http://<tailscale-ip>:8096
http://nuc-server.tail-xxxx.ts.net:8096
```

### Setup Wizard Steps

#### Step 1: Welcome Screen
- Click **Next** to begin setup

#### Step 2: Create Administrator Account
- **Username:** Choose your admin username (e.g., "admin" or your name)
- **Password:** Use a strong password (store in Vaultwarden!)
- Click **Next**

#### Step 3: Add Media Libraries
- **Skip for now** - we'll add these in the next section
- Click **Next**

#### Step 4: Metadata Language
- **Preferred Metadata Language:** English (or your preference)
- **Country:** India (or your location)
- Click **Next**

#### Step 5: Remote Access
- Leave default settings for now
- Click **Next**

#### Step 6: Finish Setup
- Click **Finish**
- Log in with your admin credentials

---

## 3. Adding Media Libraries

### Prepare Media Directories

Ensure your media is organized according to Jellyfin's recommended structure:

```
/data/media/
├── movies/
│   ├── Movie Name (2020)/
│   │   └── Movie Name (2020) - 1080p.mkv
│   └── Another Movie (2021)/
│       └── Another Movie (2021).mp4
└── tv/
    └── Show Name (2020)/
        ├── Season 01/
        │   ├── Show Name - S01E01 - Episode Title.mkv
        │   └── Show Name - S01E02 - Episode Title.mkv
        └── Season 02/
            └── ...
```

### Add Movies Library

1. **Go to Dashboard**
   - Click the **☰** menu (top-left)
   - Select **Dashboard**

2. **Navigate to Libraries**
   - In left sidebar: **Libraries** section
   - Click **+ Add Media Library**

3. **Configure Movies Library**
   - **Content type:** Movies
   - **Display name:** Movies
   - Click **+ (Add)** under Folders
   - Browse to: `/data/media/movies`
   - Click **OK**

4. **Configure Metadata Settings**
   - **Language:** English (or your preference)
   - **Country:** India
   - Enable these options:
     - ✅ **Enable real-time monitoring** (auto-detect new files)
     - ✅ **Automatically refresh metadata from the internet**
   - Metadata downloaders (recommended):
     - ✅ **TheMovieDb**
     - ✅ **The Open Movie Database**
   - Image fetchers:
     - ✅ **TheMovieDb**
   - Click **OK**

### Add TV Shows Library

1. **Add Another Library**
   - Click **+ Add Media Library**

2. **Configure TV Shows Library**
   - **Content type:** Shows
   - **Display name:** TV Shows
   - Click **+ (Add)** under Folders
   - Browse to: `/data/media/tv`
   - Click **OK**

3. **Configure Metadata Settings**
   - **Language:** English
   - **Country:** India
   - Enable options:
     - ✅ **Enable real-time monitoring**
     - ✅ **Automatically refresh metadata**
   - Metadata downloaders:
     - ✅ **TheTVDB**
     - ✅ **TheMovieDb**
   - Click **OK**

### Scan Libraries

After adding libraries, Jellyfin will automatically scan for media. You can monitor progress:

1. Go to **Dashboard** → **Libraries**
2. Click **Scan All Libraries** to force a scan
3. Progress shown in **Activity** section

**Note:** Initial scan may take a while depending on library size.

---

## 4. Configuring Hardware Transcoding

Hardware transcoding is **critical** for good performance on the Intel N150. This enables 3-5 concurrent 1080p streams.

### Enable Hardware Acceleration

1. **Navigate to Transcoding Settings**
   - Dashboard → **Playback** section (left sidebar)
   - Click **Transcoding**

2. **Select Hardware Acceleration**
   - **Hardware acceleration:** Select `Video Acceleration API (VAAPI)`
   - **VA-API Device:** `/dev/dri/renderD128`
   
3. **Enable Hardware Encoding**
   - Under "Hardware encoding options":
     - ✅ **Enable hardware encoding**
     - ✅ **Enable hardware decoding for:** (select all)
       - H264
       - HEVC
       - VP8
       - VP9
       - AV1 (if supported by your Intel N150)

4. **Enable Tone Mapping**
   - ✅ **Enable tone mapping** (for HDR → SDR conversion)
   - **Tone mapping mode:** Use hardware tone mapping when available
   - This allows HDR content to play on non-HDR devices

5. **Transcoding Settings**
   - **Transcoding thread count:** 0 (auto, recommended)
   - **FFmpeg path:** Leave default
   - **Transcoding temporary path:** `/var/cache/jellyfin/transcodes`
   - **Maximum transcoding jobs:** 3-5 (adjust based on performance)

6. **Other Recommended Settings**
   - ✅ **Enable VPP Tone mapping** (Intel-specific enhancement)
   - ✅ **Allow encoding in HEVC format**
   - ❌ **Prefer OS native DXVA or VA-API hardware decoders** (uncheck)

7. **Click Save**

### Verify Hardware Transcoding Works

1. **Start Playing a Video**
   - Play any video that requires transcoding
   - (Change quality to force transcode, e.g., set to 720p)

2. **Check Dashboard Activity**
   - Go to **Dashboard** → **Activity**
   - While video is playing, look for transcoding info
   - Should show: `Transcode (hw)` or `Transcode (Video: hw, Audio: direct)`
   - `hw` indicates hardware transcoding is active

3. **Monitor CPU Usage**
   - Run: `htop` in terminal
   - During hardware transcoding: CPU usage should be <20%
   - During software transcoding: CPU usage would be 80-100%

### Troubleshooting Hardware Transcoding

**If hardware transcoding doesn't work:**

```bash
# Check if GPU is accessible
ls -la /dev/dri/renderD128
# Should be accessible by video/render groups

# Check jellyfin user groups
groups jellyfin
# Should show: media, render, video

# Check Jellyfin logs for errors
sudo journalctl -u jellyfin | grep -i vaapi
sudo journalctl -u jellyfin | grep -i transcode

# Test VAAPI manually
vainfo --display drm --device /dev/dri/renderD128
# Should list supported codecs
```

---

## 5. Creating User Accounts

### Create Family Member Accounts

1. **Navigate to Users**
   - Dashboard → **Users** (left sidebar)

2. **Add New User**
   - Click **+ (New User)**

3. **Configure User**
   - **Name:** Enter user's name (e.g., "Mom", "Dad", "Sister")
   - **Password:** Set a password (optional but recommended)
   - **User Policy:**
     - ✅ **Enable media playback** (essential)
     - ✅ **Allow audio playback that requires transcoding**
     - ✅ **Allow video playback that requires transcoding**
     - ✅ **Allow media download** (if desired)
     - ❌ **Is Administrator** (only for you)

4. **Library Access**
   - Select which libraries this user can access:
     - ✅ Movies
     - ✅ TV Shows
   - For kids, you might limit access

5. **Parental Controls** (for children)
   - Set **Maximum parental rating** (e.g., PG-13, R)
   - Block specific content

6. **Click Save**

7. **Repeat** for each family member

### User Profiles

Each user gets:
- Separate watch history
- Individual continue watching
- Personal favorites/collections
- Customizable home screen

---

## 6. Network Access

### Local Network Access

**From any device on your home network:**

```
http://<server-ip>:8096
```

Find server IP: `ip addr show enp1s0 | grep inet`

### Tailscale VPN Access (Private)

**Recommended for secure remote access:**

1. **Install Tailscale on your devices**
   - iOS: Install from App Store
   - Android: Install from Play Store
   - Desktop: Download from tailscale.com

2. **Access Jellyfin via Tailscale**
   ```
   http://<tailscale-ip>:8096
   http://nuc-server.tail-xxxx.ts.net:8096
   ```

3. **Configure Jellyfin for Tailscale**
   - Dashboard → **Networking**
   - Add to **Known proxies:** Your Tailscale IP
   - **LAN Networks:** Add `100.64.0.0/10` (Tailscale range)

### Cloudflare Tunnel (Public - Phase 3)

**For family access from anywhere (configured later):**

```
https://watch.yourdomain.com
```

This will be set up in Phase 3 to provide public HTTPS access.

---

## 7. Client Applications

### Official Jellyfin Apps

**Mobile:**
- **iOS:** [Jellyfin Mobile](https://apps.apple.com/app/jellyfin-mobile/id1480192618) (Free)
- **Android:** [Jellyfin for Android](https://play.google.com/store/apps/details?id=org.jellyfin.mobile) (Free)

**TV/Streaming Devices:**
- **Fire TV:** Search "Jellyfin" in Amazon App Store
- **Roku:** Search "Jellyfin" in Roku Channel Store
- **Apple TV:** [Swiftfin](https://apps.apple.com/app/swiftfin/id1604098728) (Free)
- **Android TV/Google TV:** [Jellyfin for Android TV](https://play.google.com/store/apps/details?id=org.jellyfin.androidtv)

**Desktop:**
- **Windows/Mac/Linux:** [Jellyfin Media Player](https://github.com/jellyfin/jellyfin-media-player/releases)
- **Web Browser:** Any modern browser (Chrome, Firefox, Safari)

**Alternative Clients (Better UI):**
- **Infuse (iOS/Apple TV):** Paid app, beautiful UI ($10/year)
- **Kodi:** Free, via Jellyfin for Kodi addon

### Configure Jellyfin App

1. **Open app on your device**
2. **Add Server**
   - Enter server address: `http://<server-ip>:8096`
   - Or scan QR code from Jellyfin dashboard
3. **Sign In**
   - Enter username and password
4. **Start Streaming!**

### Playback Settings (per device)

**For best experience:**
- **Maximum streaming bitrate:** 120 Mbps (home network)
- **Maximum streaming bitrate:** 8-20 Mbps (remote/mobile)
- **Video quality:** Auto (recommended)
- **Allow video transcoding:** Yes
- **Allow audio transcoding:** Yes

---

## 8. Optimization Settings

### Playback Settings

**Dashboard → Playback:**

1. **Streaming**
   - **Internet streaming bitrate limit:** 8-20 Mbps (for remote users)
   - **Allow media conversion:** ✅ Yes

2. **Resume Settings**
   - ✅ **Enable next episode auto play**
   - **Auto play delay:** 10 seconds

3. **Subtitle Settings**
   - ✅ **Extract chapter images** (thumbnail preview)
   - ✅ **Extract subtitles on the fly**

### Library Settings

**For each library (Movies/TV Shows):**

1. **Metadata**
   - **Preferred download language:** English
   - **Metadata savers:** Select all
   - ✅ **Save artwork into media folders** (recommended)

2. **Chapter Images**
   - ✅ **Enable chapter image extraction**
   - **Extract during library scan:** Yes

### Network Settings

**Dashboard → Networking:**

1. **Server Settings**
   - **Public HTTP port:** 8096
   - **Enable automatic port mapping:** ❌ No (we control ports)
   - **Enable remote access:** ✅ Yes

2. **Known Proxies**
   - Add your Tailscale IP if using VPN
   - Add Cloudflare IPs if using tunnel (later)

### Scheduled Tasks

**Dashboard → Scheduled Tasks:**

Recommended tasks to enable:

1. **Extract chapter images**
   - Run: Daily at 2:00 AM

2. **Refresh metadata**
   - Run: Weekly on Sunday at 3:00 AM

3. **Scan library**
   - Automatic on file changes (real-time monitoring)

---

## 9. Troubleshooting

### Common Issues

#### 1. Jellyfin Won't Start

```bash
# Check service status
sudo systemctl status jellyfin

# View detailed logs
sudo journalctl -u jellyfin -n 100 --no-pager

# Common fixes:
# - Ensure ZFS datasets are mounted
# - Check permissions on /var/lib/jellyfin
# - Restart service: sudo systemctl restart jellyfin
```

#### 2. Can't Access Web UI

```bash
# Check if Jellyfin is listening
sudo ss -tulpn | grep 8096

# Check firewall (should show port 8096 on tailscale0)
sudo iptables -L -n | grep 8096

# Check from server itself
curl http://localhost:8096

# If local works but remote doesn't:
# - Verify firewall allows Tailscale interface
# - Check Tailscale status: tailscale status
```

#### 3. Hardware Transcoding Not Working

```bash
# Verify VAAPI support
vainfo --display drm --device /dev/dri/renderD128

# Check permissions
ls -la /dev/dri/
# renderD128 should be accessible by render/video groups

# Verify jellyfin user groups
groups jellyfin
# Should include: render, video

# Check Jellyfin logs for VAAPI errors
sudo journalctl -u jellyfin | grep -i vaapi

# If still issues, try rebuilding config:
sudo nixos-rebuild switch --flake /etc/nixos#nuc-server
```

#### 4. Media Not Showing Up

```bash
# Check media directory permissions
ls -la /data/media/movies
ls -la /data/media/tv

# Ensure jellyfin user (via media group) can read
# Files should be: drwxrwxr-x root:media or similar

# Force library scan
# Dashboard → Libraries → Scan All Libraries

# Check scan logs
# Dashboard → Scheduled Tasks → Scan Library → View logs
```

#### 5. Playback Stuttering/Buffering

**Causes and fixes:**

1. **Network issue**
   - Check bandwidth: Lower quality in client
   - Use ethernet instead of WiFi on server

2. **Transcoding overload**
   - Reduce concurrent streams
   - Enable hardware transcoding (see section 4)
   - Lower client quality settings

3. **Storage bottleneck (USB HDD)**
   - Check disk I/O: `iotop`
   - Reduce simultaneous downloads in Deluge
   - Consider direct play instead of transcode

4. **Check transcoding in Dashboard**
   - Dashboard → Activity
   - See which streams are transcoding
   - If "sw" (software), enable hardware acceleration

#### 6. Permission Denied Errors

```bash
# Fix media directory permissions
sudo chown -R root:media /data/media/movies
sudo chown -R root:media /data/media/tv
sudo chmod -R 775 /data/media/movies
sudo chmod -R 775 /data/media/tv

# Fix Jellyfin directories
sudo chown -R jellyfin:media /var/lib/jellyfin
sudo chown -R jellyfin:media /var/cache/jellyfin

# Restart Jellyfin
sudo systemctl restart jellyfin
```

### Performance Monitoring

**Monitor Jellyfin Performance:**

```bash
# Real-time system resources
htop

# Disk I/O
iotop

# Network usage
iftop

# Jellyfin-specific:
# Dashboard → Activity (shows active streams)
# Dashboard → Logs (for errors)
```

---

## 10. Maintenance

### Regular Tasks

**Weekly:**
- [ ] Check Dashboard → Activity for errors
- [ ] Review recent logs: `sudo journalctl -u jellyfin -n 100`
- [ ] Verify transcoding cache size: `du -sh /var/cache/jellyfin`

**Monthly:**
- [ ] Update NixOS: `sudo nixos-rebuild switch`
- [ ] Check ZFS health: `zpool status`
- [ ] Review user accounts and access
- [ ] Check storage usage: `zfs list`

**As Needed:**
- [ ] Clear transcoding cache: `rm -rf /var/cache/jellyfin/transcodes/*`
- [ ] Refresh all metadata: Dashboard → Library → Scan All Libraries
- [ ] Backup Jellyfin config: `/var/lib/jellyfin/data/`

### Backup Important Data

**What to backup:**

```bash
# Jellyfin configuration (includes users, settings, library metadata)
/var/lib/jellyfin/data/
/var/lib/jellyfin/config/

# Backup command (daily recommended):
sudo tar -czf /backups/jellyfin/jellyfin-config-$(date +%Y%m%d).tar.gz \
  /var/lib/jellyfin/data/ \
  /var/lib/jellyfin/config/

# Keep last 7 days
find /backups/jellyfin/ -name "jellyfin-config-*.tar.gz" -mtime +7 -delete
```

**Note:** Media files themselves don't need backup if you can re-download them.

### Updating Jellyfin

Jellyfin updates through NixOS system updates:

```bash
# Update NixOS (includes Jellyfin)
sudo nixos-rebuild switch --upgrade-all --flake /etc/nixos#nuc-server

# Check new Jellyfin version
journalctl -u jellyfin | grep "Jellyfin version"
```

---

## Recommended Workflow

### For Family Use

1. **Request Media** (Phase 3: Jellyseerr)
   - Family uses Jellyseerr to request movies/shows
   - Automated download via Radarr/Sonarr
   - Auto-appears in Jellyfin

2. **Watch Together**
   - Create collections for family movie nights
   - Use Jellyfin's sync play feature
   - Each person has their own watch history

3. **Mobile Streaming**
   - Enable downloads for offline viewing
   - Adjust quality for mobile data vs WiFi

---

## Next Steps

✅ **Phase 2 Complete!** You now have a fully functional Jellyfin media server.

**What's Next:**

🎯 **Phase 3: Media Automation** (Radarr, Sonarr, Prowlarr, Jellyseerr)
- Automatic movie/TV downloads
- Request interface for family
- Subtitle automation

**Enjoy your personal Netflix! 🍿🎬**

---

## Quick Reference

### Important URLs

- **Local:** http://localhost:8096
- **LAN:** http://192.168.x.x:8096
- **Tailscale:** http://nuc-server.tail-xxxx.ts.net:8096

### Important Directories

- **Config:** `/var/lib/jellyfin`
- **Cache:** `/var/cache/jellyfin`
- **Movies:** `/data/media/movies`
- **TV Shows:** `/data/media/tv`
- **Logs:** `sudo journalctl -u jellyfin`

### Quick Commands

```bash
# Check service
sudo systemctl status jellyfin

# Restart Jellyfin
sudo systemctl restart jellyfin

# View logs
sudo journalctl -u jellyfin -f

# Test hardware acceleration
vainfo --display drm --device /dev/dri/renderD128

# Check port
sudo ss -tulpn | grep 8096
```

---

**Document Version:** 1.0  
**Last Updated:** 2025-10-23  
**For Support:** Check Jellyfin docs at https://jellyfin.org/docs/