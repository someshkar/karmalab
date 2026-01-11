
# *arr Stack Setup Guide

**Phase 3: Automated Media Acquisition**

This guide covers the complete setup and integration of the *arr stack for automated media management on your NixOS homelab.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Service Access](#service-access)
5. [Setup Order](#setup-order)
6. [Prowlarr Setup](#prowlarr-setup)
7. [Radarr Setup](#radarr-setup)
8. [Sonarr Setup](#sonarr-setup)
9. [Bazarr Setup](#bazarr-setup)
10. [Testing the Workflow](#testing-the-workflow)
11. [Troubleshooting](#troubleshooting)
12. [Maintenance](#maintenance)

---

## Overview

The *arr stack provides automated media acquisition and organization:

| Service | Purpose | Port | Priority |
|---------|---------|------|----------|
| **Prowlarr** | Indexer management (searches torrent sites) | 9696 | Setup First |
| **Radarr** | Movie automation and management | 7878 | Setup Second |
| **Sonarr** | TV show automation and management | 8989 | Setup Second |
| **Bazarr** | Subtitle automation | 6767 | Setup Last |

### Key Features

- ✅ **Automatic searching** for requested media across multiple indexers
- ✅ **Quality management** with customizable profiles
- ✅ **Download client integration** with Deluge (VPN-isolated)
- ✅ **Automatic file organization** and renaming
- ✅ **Subtitle automation** in multiple languages
- ✅ **Integration with Jellyfin** for seamless library updates

---

## Architecture

```
User Request (Jellyseerr, Phase 4)
         │
         ▼
    Radarr/Sonarr
         │
         ├──────────► Prowlarr ────► Torrent Indexers
         │                              (Search)
         │                                  │
         │                                  ▼
         │                              Results
         │                                  │
         └──────────► Deluge ◄──────────────┘
                   (via VPN)              (Download)
                        │
                        ▼
            /data/media/downloads/complete/
                        │
         ┌──────────────┴──────────────┐
         ▼                             ▼
    Radarr Import                Sonarr Import
         │                             │
         ▼                             ▼
  /data/media/movies           /data/media/tv
         │                             │
         └──────────┬──────────────────┘
                    ▼
                 Bazarr
            (Fetch Subtitles)
                    │
                    ▼
                Jellyfin
            (Stream Media)
```

---

## Prerequisites

Before starting, ensure:

- ✅ **Phase 0-2 complete**: ZFS datasets, Deluge, and Jellyfin configured
- ✅ **Configuration applied**: `sudo nixos-rebuild switch`
- ✅ **Services running**: Check with `sudo systemctl status prowlarr radarr sonarr bazarr`
- ✅ **Deluge configured**: Web UI accessible, daemon running
- ✅ **Tailscale connected**: For admin access to services

### Verify Services Status

```bash
# Check all *arr services are active
sudo systemctl status prowlarr radarr sonarr bazarr

# Check ZFS datasets mounted
zfs list | grep services

# Check Deluge is running
docker ps | grep deluge

# Test Deluge daemon port
nc -zv localhost 58846
```

---

## Service Access

Access all services via **Tailscale only** (admin access):

| Service | URL | Default Credentials |
|---------|-----|-------------------|
| Prowlarr | `http://nuc-server:9696` | Set on first access |
| Radarr | `http://nuc-server:7878` | Set on first access |
| Sonarr | `http://nuc-server:8989` | Set on first access |
| Bazarr | `http://nuc-server:6767` | Set on first access |
| Deluge | `http://nuc-server:8112` | Password: `deluge` |

**Note:** Replace `nuc-server` with your Tailscale hostname or IP (e.g., `100.x.x.x`).

---

## Setup Order

**IMPORTANT:** Configure services in this exact order to ensure proper integration.

1. **Prowlarr** - Set up indexers first (15-20 minutes)
2. **Radarr** - Connect to Prowlarr and Deluge (10-15 minutes)
3. **Sonarr** - Connect to Prowlarr and Deluge (10-15 minutes)
4. **Bazarr** - Connect to Radarr and Sonarr (10 minutes)

**Total Time:** ~45-60 minutes for complete setup

---

## Prowlarr Setup

**Purpose:** Central indexer management for searching torrent sites.

### Step 1: Initial Setup

1. Navigate to `http://nuc-server:9696`
2. Complete the authentication setup wizard
3. Create an admin account (username/password)

### Step 2: Add Indexers

Prowlarr searches public and private torrent indexers. Add indexers based on your needs:

#### Public Indexers (No Account Required)

1. Go to **Indexers** → **Add Indexer**
2. Search for and add these recommended public indexers:
   - **1337x** (General, movies + TV)
   - **The Pirate Bay** (General, large catalog)
   - **RARBG** (Quality releases)
   - **EZTV** (TV shows focus)
   - **YTS** (Movies, smaller file sizes)

3. For each indexer:
   - Click the indexer name
   - Leave default settings (usually no configuration needed)
   - Click **Test** to verify connection
   - Click **Save**

#### Private Indexers (Optional, Account Required)

If you have accounts on private trackers:

1. Go to **Indexers** → **Add Indexer**
2. Search for your tracker (e.g., TorrentLeech, IPTorrents)
3. Configure:
   - **API Key** or **Username/Password** (from tracker site)
   - **Minimum Seeders**: 1 (default)
   - Click **Test** → **Save**

### Step 3: Configure Indexer Settings

1. Go to **Settings** → **Indexers**
2. Set these preferences:
   - **Minimum Seeders**: 1 (ensures active torrents)
   - **Seed Ratio**: Leave blank (handled by Deluge)
   - **Required Flags**: Leave default

### Step 4: Generate API Key

Prowlarr's API key will be used by Radarr and Sonarr:

1. Go to **Settings** → **General** → **Security**
2. Copy the **API Key** (looks like: `a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6`)
3. **Save this API key** - you'll need it for Radarr and Sonarr setup

### Step 5: Enable Sync to Applications

1. Go to **Settings** → **Apps**
2. Click **Add Application** → **Radarr**
3. Configure:
   - **Name**: `Radarr`
   - **Sync Level**: `Full Sync`
   - **Prowlarr Server**: `http://localhost:9696`
   - **Radarr Server**: `http://localhost:7878`
   - **API Key**: (You'll get this from Radarr in the next section - come back to this)
   - Click **Test** → **Save**

4. Repeat for Sonarr:
   - **Name**: `Sonarr`
   - **Sonarr Server**: `http://localhost:8989`
   - **API Key**: (You'll get this from Sonarr - come back to this)

**Note:** You'll complete the API key configuration after setting up Radarr and Sonarr.

### Prowlarr Verification

- [ ] At least 3-5 indexers added and tested
- [ ] API key generated and saved
- [ ] Application sync configured (API keys pending)

---

## Radarr Setup

**Purpose:** Automated movie acquisition and organization.

### Step 1: Initial Setup

1. Navigate to `http://nuc-server:7878`
2. Complete the authentication wizard
3. Create an admin account

### Step 2: Add Download Client (Deluge)

1. Go to **Settings** → **Download Clients** → **Add** → **Deluge**
2. Configure:
   - **Name**: `Deluge`
   - **Enable**: ✅ (checked)
   - **Host**: `localhost`
   - **Port**: `58846` ⚠️ **CRITICAL: Use daemon port, NOT 8112**
   - **URL Base**: (leave blank)
   - **Password**: `deluge` (or your custom Deluge password)
   - **Category**: `radarr-movies`
   - **Add Paused**: ❌ (unchecked - start downloads immediately)
   - **Priority**: `Normal`

3. Click **Test** (should show green checkmark)
4. Click **Save**

**Important Notes:**
- ⚠️ Must use port **58846** (Deluge daemon), NOT 8112 (web UI)
- The password is set in Deluge web UI: **Preferences** → **Daemon**
- Default Deluge password is `deluge` (change it for security)

### Step 3: Configure Root Folder

1. Go to **Settings** → **Media Management**
2. Scroll to **Root Folders** → **Add Root Folder**
3. Enter: `/data/media/movies`
4. Click the checkmark to save

### Step 4: Configure Quality Profiles

1. Go to **Settings** → **Profiles** → **Quality Profiles**
2. Edit the default profile or create new:
   - **Name**: `HD-1080p/720p` (or your preference)
   - **Allowed Qualities**:
     - ✅ Bluray-1080p
     - ✅ WEB-DL 1080p
     - ✅ WEBDL-720p
     - ✅ Bluray-720p
   - **Quality Cutoff**: `Bluray-1080p`
   - Click **Save**

### Step 5: Connect to Prowlarr

1. Go to **Settings** → **Indexers**
2. You should see indexers automatically added from Prowlarr
3. If not, go back to Prowlarr and complete Step 5 from Prowlarr Setup

**Get Radarr API Key:**
1. In Radarr: **Settings** → **General** → **Security**
2. Copy the **API Key**
3. Go back to Prowlarr → **Settings** → **Apps** → **Radarr**
4. Paste the API key and click **Save**

### Step 6: Configure File Naming

1. Go to **Settings** → **Media Management**
2. Enable **Rename Movies**: ✅
3. Set **Standard Movie Format**: 
   ```
   {Movie Title} ({Release Year}) - {Quality Full}
   ```
4. Set **Movie Folder Format**:
   ```
   {Movie Title} ({Release Year})
   ```
5. Click **Save Changes**

### Step 7: Configure Permissions (Important)

1. Go to **Settings** → **Media Management**
2. Scroll to **Permissions**
3. Set **File chmod mask**: `0775` (group writable)
4. Click **Save Changes**

This ensures Jellyfin and other services can read the files.

### Radarr Verification

- [ ] Deluge download client connected and tested
- [ ] Root folder `/data/media/movies` configured
- [ ] Quality profile created
- [ ] Indexers synced from Prowlarr (or API key added to Prowlarr)
- [ ] File naming configured
- [ ] Permissions set to 0775

---

## Sonarr Setup

**Purpose:** Automated TV show acquisition and organization.

### Step 1: Initial Setup

1. Navigate to `http://nuc-server:8989`
2. Complete the authentication wizard
3. Create an admin account

### Step 2: Add Download Client (Deluge)

1. Go to **Settings** → **Download Clients** → **Add** → **Deluge**
2. Configure:
   - **Name**: `Deluge`
   - **Enable**: ✅
   - **Host**: `localhost`
   - **Port**: `58846` ⚠️ **CRITICAL: Use daemon port**
   - **Password**: `deluge` (or your custom password)
   - **Category**: `sonarr-tv`
   - **Add Paused**: ❌
   - **Priority**: `Normal`

3. Click **Test** → **Save**

### Step 3: Configure Root Folder

1. Go to **Settings** → **Media Management**
2. **Root Folders** → **Add Root Folder**
3. Enter: `/data/media/tv`
4. Click the checkmark to save

### Step 4: Configure Quality Profiles

1. Go to **Settings** → **Profiles** → **Quality Profiles**
2. Edit or create profile:
   - **Name**: `HD-1080p/720p`
   - **Allowed Qualities**:
     - ✅ WEBDL-1080p
     - ✅ WEBRip-1080p
     - ✅ WEBDL-720p
     - ✅ Bluray-1080p
     - ✅ Bluray-720p
   - **Quality Cutoff**: `WEBDL-1080p`
   - Click **Save**

### Step 5: Connect to Prowlarr

1. Go to **Settings** → **Indexers**
2. Indexers should auto-sync from Prowlarr

**Get Sonarr API Key:**
1. In Sonarr: **Settings** → **General** → **Security**
2. Copy the **API Key**
3. Go back to Prowlarr → **Settings** → **Apps** → **Sonarr**
4. Paste the API key and click **Save**

### Step 6: Configure File Naming

1. Go to **Settings** → **Media Management**
2. Enable **Rename Episodes**: ✅
3. Set **Standard Episode Format**:
   ```
   {Series Title} - S{season:00}E{episode:00} - {Episode Title} [{Quality Full}]
   ```
4. Set **Season Folder Format**:
   ```
   Season {season:00}
   ```
5. Set **Series Folder Format**:
   ```
   {Series Title} ({Series Year})
   ```
6. Click **Save Changes**

### Step 7: Configure Series Types

1. Go to **Settings** → **Media Management**
2. Under **Episode Naming**:
   - **Daily Episode Format**: (for daily shows like news)
     ```
     {Series Title} - {Air-Date} - {Episode Title}
     ```
   - **Anime Episode Format**: (if you watch anime)
     ```
     {Series Title} - S{season:00}E{episode:00} - {Episode Title}
     ```

### Step 8: Configure Permissions

1. Go to **Settings** → **Media Management**
2. **Permissions**:
   - **File chmod mask**: `0775`
3. Click **Save Changes**

### Sonarr Verification

- [ ] Deluge download client connected and tested
- [ ] Root folder `/data/media/tv` configured
- [ ] Quality profile created
- [ ] Indexers synced from Prowlarr
- [ ] File naming configured with season folders
- [ ] Permissions set to 0775

---

## Bazarr Setup

**Purpose:** Automated subtitle downloading for movies and TV shows.

### Step 1: Initial Setup

1. Navigate to `http://nuc-server:6767`
2. Complete the language configuration
3. Select your preferred subtitle languages (e.g., English)
4. Create admin account

### Step 2: Connect to Radarr

1. Go to **Settings** → **Radarr**
2. Enable **Use Radarr**: ✅
3. Configure:
   - **Hostname or IP**: `localhost`
   - **Port**: `7878`
   - **API Key**: (Get from Radarr → Settings → General → Security)
   - **SSL**: ❌
   - **Download Only Monitored**: ✅ (recommended)
4. Click **Test** → **Save**

### Step 3: Connect to Sonarr

1. Go to **Settings** → **Sonarr**
2. Enable **Use Sonarr**: ✅
3. Configure:
   - **Hostname or IP**: `localhost`
   - **Port**: `8989`
   - **API Key**: (Get from Sonarr → Settings → General → Security)
   - **SSL**: ❌
   - **Download Only Monitored**: ✅
4. Click **Test** → **Save**

### Step 4: Configure Subtitle Providers

1. Go to **Settings** → **Providers**
2. Add subtitle providers (at least 2-3 for redundancy):

#### OpenSubtitles (Recommended)
1. Click **Add Provider** → **OpenSubtitles.com**
2. You'll need a free account at https://www.opensubtitles.com
3. Configure:
   - **Username**: (your OpenSubtitles username)
   - **Password**: (your OpenSubtitles password)
   - Click **Save**

#### Subscene
1. Click **Add Provider** → **Subscene**
2. No configuration needed (public)
3. Click **Save**

#### YIFY Subtitles (Movies Only)
1. Click **Add Provider** → **YIFY Subtitles**
2. No configuration needed
3. Click **Save**

### Step 5: Configure Languages

1. Go to **Settings** → **Languages**
2. Set **Languages Profiles**:
   - **Name**: `English`
   - **Languages**: 
     - ✅ English
     - (Add others if needed: Hindi, Spanish, etc.)
   - **Cutoff**: `English`
3. Click **Save**

### Step 6: Configure Subtitle Settings

1. Go to **Settings** → **Subtitles**
2. Configure:
   - **Subtitle Folder**: `With Media` (subtitles saved next to video files)
   - **Encoding**: `UTF-8`
   - **Hi Extension**: `.hi` (for hearing impaired subtitles)
   - **Subtitle Format**: `SRT` (most compatible)
3. Click **Save**

### Step 7: Enable Automatic Search

1. Go to **Settings** → **Scheduler**
2. Configure:
   - **Search for Subtitles**: ✅ (enabled)
   - **Interval**: `6 hours` (default)
   - **Upgrade Subtitles**: ✅ (optional - finds better quality subs)
3. Click **Save**

### Bazarr Verification

- [ ] Radarr connected and tested
- [ ] Sonarr connected and tested
- [ ] At least 2 subtitle providers added
- [ ] Language profile configured
- [ ] Automatic search enabled

---

## Testing the Workflow

Now test the complete automation pipeline:

### Test 1: Manual Movie Search (Radarr)

1. In Radarr, click **Add Movie**
2. Search for a popular movie (e.g., "The Matrix")
3. Select the movie from results
4. Configure:
   - **Root Folder**: `/data/media/movies`
   - **Quality Profile**: Your configured profile
   - **Monitor**: Yes
   - **Search on Add**: ✅ (immediately search for movie)
5. Click **Add Movie**

**Expected Behavior:**
- Radarr searches Prowlarr for the movie
- Prowlarr queries all configured indexers
- Best match is selected based on quality profile
- Torrent is sent to Deluge
- Download starts automatically

**Verification Steps:**
```bash
# Check Deluge has the torrent
# Visit: http://nuc-server:8112
# Should see the movie downloading with category "radarr-movies"

# Monitor download progress
docker logs deluge -f

# Once complete, check if file appears in downloads
ls -lh /data/media/downloads/complete/movies/

# Radarr should automatically import it to:
ls -lh /data/media/movies/
```

### Test 2: Manual TV Show Search (Sonarr)

1. In Sonarr, click **Add Series**
2. Search for a TV show (e.g., "Breaking Bad")
3. Select the series from results
4. Configure:
   - **Root Folder**: `/data/media/tv`
   - **Quality Profile**: Your configured profile
   - **Season Monitoring**: Latest Season (or all)
   - **Search on Add**: ✅
5. Click **Add Series**

**Expected Behavior:**
- Sonarr searches for all monitored episodes
- Multiple torrents may be added (one per season/episode)
- Downloads start automatically in Deluge

**Verification:**
```bash
# Check Deluge for torrents with category "sonarr-tv"
# Monitor in Sonarr: Activity → Queue

# Once imported:
ls -lh /data/media/tv/"Breaking Bad (2008)"/
```

### Test 3: Subtitle Automation (Bazarr)

After media is imported by Radarr/Sonarr:

1. Go to Bazarr → **Movies** (or **Series**)
2. You should see your added media listed
3. Bazarr will automatically search for subtitles
4. Wait a few minutes, then check:

```bash
# Check for subtitle files (.srt)
ls -lh /data/media/movies/"The Matrix (1999)"/
# Should see: The Matrix (1999) - 1080p.mkv
#             The Matrix (1999) - 1080p.en.srt

ls -lh /data/media/tv/"Breaking Bad (2008)"/Season\ 01/
# Should see .srt files for each episode
```

### Test 4: Jellyfin Integration

1. Open Jellyfin: `http://nuc-server:8096`
2. Go to **Dashboard** → **Libraries**
3. Scan your Movies and TV Shows libraries
4. New media should appear in Jellyfin
5. Play a video and verify:
   - Video plays smoothly
   - Subtitles are available (click CC button)

### Test 5: Complete Automation Test

Test the full workflow without manual intervention:

1. In Radarr, add a movie but **disable "Search on Add"**
2. Wait for the next automatic search cycle (RSS sync, every 15 minutes)
3. Monitor the process:
   ```bash
   # Radarr logs
   sudo journalctl -u radarr -f
   
   # Sonarr logs
   sudo journalctl -u sonarr -f
   
   # Deluge logs
   docker logs deluge -f
   ```

**Expected:** Movie should be found, downloaded, imported, and subtitles added automatically.

---

## Troubleshooting

### Issue: Radarr/Sonarr Can't Connect to Deluge

**Symptoms:**
- Error: "Unable to connect to Deluge"
- Test button fails in Download Clients

**Solutions:**

1. **Verify Deluge daemon is running:**
   ```bash
   docker ps | grep deluge
   docker logs deluge
   ```

2. **Check port 58846 is accessible:**
   ```bash
   nc -zv localhost 58846
   # Should output: Connection to localhost 58846 port [tcp/*] succeeded!
   ```

3. **Verify Deluge password:**
   - Open Deluge web UI: `http://nuc-server:8112`
   - Go to **Preferences** → **Daemon**
   - Check/set daemon password
   - Use this password in Radarr/Sonarr

4. **Check if using correct port:**
   - ⚠️ Must use `58846` (daemon), NOT `8112` (web UI)
   - Double-check Download Client settings

### Issue: No Search Results from Prowlarr

**Symptoms:**
- Radarr/Sonarr searches return no results
- Prowlarr shows no activity

**Solutions:**

1. **Test indexers individually:**
   - Go to Prowlarr → **Indexers**
   - Click **Test** on each indexer
   - Remove any failing indexers

2. **Check Prowlarr connectivity:**
   ```bash
   sudo journalctl -u prowlarr -f
   ```

3. **Verify Prowlarr API keys:**
   - Prowlarr → **Settings** → **Apps**
   - Check Radarr and Sonarr connections
   - Re-test each application

4. **Manual search test:**
   - Prowlarr → **Search**
   - Try searching for a popular movie
   - Should show results from multiple indexers

### Issue: Downloaded Files Not Importing

**Symptoms:**
- Deluge completes download
- File stays in `/data/media/downloads/complete/`
- Not moved to `/data/media/movies/` or `/tv/`

**Solutions:**

1. **Check file permissions:**
   ```bash
   ls -la /data/media/downloads/complete/
   # Files should be readable by radarr/sonarr users
   
   # Fix if needed:
   sudo chown -R root:media /data/media/downloads/
   sudo chmod -R 775 /data/media/downloads/
   ```

2. **Verify category in Deluge:**
   - Open Deluge web UI
   - Check torrent has correct category (`radarr-movies` or `sonarr-tv`)
   - If not, update Download Client settings

3. **Check Radarr/Sonarr logs:**
   ```bash
   sudo journalctl -u radarr -f
   # Look for import errors
   ```

4. **Manual import:**
   - Radarr/Sonarr → **Activity** → **Queue**
   - Look for completed downloads
   - Click **Manual Import** if needed

### Issue: Bazarr Not Finding Subtitles

**Symptoms:**
- Movies/TV shows appear in Bazarr
- No subtitles downloaded

**Solutions:**

1. **Check subtitle providers:**
   - Bazarr → **Settings** → **Providers**
   - Test each provider
   - Add more providers if needed

2. **Verify language profile:**
   - Bazarr → **Settings** → **Languages**
   - Ensure language is configured
   - Check it matches your media

3. **Manual subtitle search:**
   - Bazarr → **Movies** or **Series**
   - Click on a movie/episode
   - Click **Search** to manually trigger
   - Check for error messages

4. **Check OpenSubtitles rate limit:**
   - Free accounts have daily download limits
   - Consider multiple providers to avoid limits

### Issue: VPN Affecting Connectivity

**Symptoms:**
- Intermittent connection issues
- Services can't reach Deluge

**Solutions:**

1. **Verify VPN is stable:**
   ```bash
   docker logs gluetun | tail -20
   # Should show "Wireguard is up"
   ```

2. **Check Deluge is using VPN:**
   ```bash
   docker exec gluetun wget -qO- ifconfig.me
   # Should show VPN IP, not your home IP
   ```

3. **Restart VPN stack if needed:**
   ```bash
   cd /root/nixos-homelab-v2/docker/deluge-vpn
   docker-compose restart
   ```

### Issue: Services Not Starting After Reboot

**Symptoms:**
- Services show "failed" status
- Config directories empty

**Solutions:**

1. **Check ZFS datasets mounted:**
   ```bash
   zfs list | grep services
   # Should show all *arr datasets
   ```

2. **Verify mount dependencies:**
   ```bash
   sudo systemctl status zfs-mount.service
   sudo systemctl status radarr.service
   # Check After/Requires dependencies
   ```

3. **Manual service start:**
   ```bash
   sudo systemctl start prowlarr radarr sonarr bazarr
   ```

4. **Check logs:**
   ```bash
   sudo journalctl -u radarr -n 50 --no-pager
   ```

---

## Maintenance

### Regular Tasks

#### Weekly
- [ ] Check download client connectivity
- [ ] Review failed downloads in Radarr/Sonarr
- [ ] Verify disk space: `df -h /data`
- [ ] Check for service errors: `sudo systemctl --failed`

#### Monthly
- [ ] Update quality profiles as needed
- [ ] Review and update indexers in Prowlarr
- [ ] Check for NixOS service updates
- [ ] Verify backup of configurations

#### Quarterly
- [ ] Review and clean up old downloads
- [ ] Audit media library organization
- [ ] Update download categories if needed
- [ ] Test disaster recovery procedures

### Backup Important Configurations

All *arr configurations are stored in ZFS datasets, which are automatically snapshotted. However, you can also manually backup:

```bash
# Backup all *arr configs
sudo tar -czf /backups/arr-configs-$(date +%Y%m%d).tar.gz \
  /var/lib/prowlarr \
  /var/lib/radarr \
  /var/lib/sonarr \
  /var/lib/bazarr

# List current backups
ls -lh /backups/arr-configs-*
```

### Updating Services

To update *arr services to latest versions:

```bash
# Update NixOS packages
sudo nix-channel --update
sudo nixos-rebuild switch

# Restart services to use new versions
sudo systemctl restart prowlarr radarr sonarr bazarr

# Verify versions
# Check each service's UI: Settings → General → About
```

### API Key Management

Keep track of API keys for integration:

| Service | API Key Location | Used By |
|---------|-----------------|---------|
| Prowlarr | Settings → General → Security | Radarr, Sonarr |
| Radarr | Settings → General → Security | Prowlarr, Bazarr, Jellyseerr |
| Sonarr | Settings → General → Security | Prowlarr, Bazarr, Jellyseerr |
| Bazarr | Settings → General → Security | None (optional) |

**Security:** Store API keys securely, rotate periodically (annually recommended).

---

## Quick Reference

### Important Paths

| Path | Purpose | Owner |
|------|---------|-------|
| `/var/lib/prowlarr` | Prowlarr config | prowlarr:media |
| `/var/lib/radarr` | Radarr config | radarr:media |
| `/var/lib/sonarr` | Sonarr config | sonarr:media |
| `/var/lib/bazarr` | Bazarr config | bazarr:media |
| `/data/media/movies` | Movie library | root:media |
| `/data/media/tv` | TV show library | root:media |
| `/data/media/downloads/complete` | Completed downloads | deluge:media |

### Useful Commands

```bash
# Check all *arr services status
sudo systemctl status prowlarr radarr sonarr bazarr

# View service logs
sudo journalctl -u radarr -f        # Follow Radarr logs
sudo journalctl -u sonarr -n 100    # Last 100 Sonarr log lines

# Restart services
sudo systemctl restart radarr