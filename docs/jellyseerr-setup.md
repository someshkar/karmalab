# Jellyseerr Setup Guide

**Version:** 1.0  
**Date:** 2025-10-23  
**Phase:** 4 (Media Request Interface)  
**Service Port:** 5055  

---

## Overview

Jellyseerr is a user-friendly media request management interface that allows family members to request movies and TV shows. It integrates seamlessly with your media automation stack:

- **Jellyfin**: Authentication, user sync, library browsing
- **Radarr**: Movie requests and management
- **Sonarr**: TV show requests and management
- **Jellyfin**: Content availability checking and viewing

### Key Features

✅ **User-Friendly Interface**: Beautiful, intuitive UI for requesting content  
✅ **Jellyfin Integration**: Uses Jellyfin accounts for authentication  
✅ **Automatic Request Handling**: Sends requests directly to Radarr/Sonarr  
✅ **Availability Detection**: Checks if content already exists in Jellyfin  
✅ **Request Tracking**: Monitor status from requested → downloading → available  
✅ **User Permissions**: Control who can request what and how much  
✅ **Notifications**: Email/Webhook alerts for request status updates  

---

## Architecture

```
Family Member
      │
      ▼
Jellyseerr :5055
      │
      ├──────────► Jellyfin :8096 (Check availability, authenticate users)
      │
      ├──────────► Radarr :7878 (Movie requests)
      │                 │
      │                 ▼
      │            Prowlarr :9696 (Search indexers)
      │                 │
      │                 ▼
      │            Deluge :8112 (Download via VPN)
      │                 │
      │                 ▼
      │            /data/media/movies
      │                 │
      │                 ▼
      │            Jellyfin :8096 (Available for watching)
      │
      └──────────► Sonarr :8989 (TV show requests)
                        │
                        ▼
                   [Same flow as Radarr for TV shows]
```

---

## Prerequisites

Before setting up Jellyseerr, ensure these services are running and configured:

### Required Services

- [x] **Jellyfin** (Port 8096) - Media server with admin account created
- [x] **Radarr** (Port 7878) - Configured with Prowlarr and Deluge
- [x] **Sonarr** (Port 8989) - Configured with Prowlarr and Deluge
- [x] **Prowlarr** (Port 9696) - Indexers added and synced to Radarr/Sonarr
- [x] **Deluge** (Port 8112) - VPN-isolated torrent client working

### Information You'll Need

Gather this information before starting setup:

1. **Jellyfin Admin Credentials**
   - Username: `admin` (or your admin username)
   - Password: (from Jellyfin first-time setup)

2. **Radarr API Key**
   - Location: Radarr → Settings → General → API Key
   - Copy the API key string

3. **Sonarr API Key**
   - Location: Sonarr → Settings → General → API Key
   - Copy the API key string

---

## Installation and Service Start

### Step 1: Apply Configuration

The Jellyseerr configuration is already added to [`configuration.nix`](../configuration.nix:722). Apply it:

```bash
# Apply NixOS configuration
sudo nixos-rebuild switch
```

### Step 2: Verify Service Status

Check that Jellyseerr is running:

```bash
# Check service status
sudo systemctl status jellyseerr

# Should show: Active: active (running)
```

If the service fails to start:

```bash
# View detailed logs
sudo journalctl -u jellyseerr -n 50 --no-pager

# Check ZFS dataset is mounted
df -h | grep jellyseerr
# Should show: storagepool/services/jellyseerr mounted at /var/lib/jellyseerr

# Restart service
sudo systemctl restart jellyseerr
```

### Step 3: Access Jellyseerr Web UI

Access Jellyseerr via one of these methods:

**On Local LAN:**
```
http://localhost:5055
```

**Via Tailscale:**
```
http://nuc-server:5055
http://<tailscale-ip>:5055
```

---

## First-Time Setup Wizard

When you first access Jellyseerr, you'll be greeted with a setup wizard. Follow these steps:

### 1. Initial Welcome Screen

Click **"Sign in"** to begin setup.

### 2. Sign In with Jellyfin

On the sign-in screen:

1. Click **"Use your Jellyfin account"**
2. Enter your Jellyfin server URL: `http://localhost:8096`
3. Click **"Continue"**
4. Sign in with your **Jellyfin admin account**:
   - Email/Username: Your Jellyfin admin username
   - Password: Your Jellyfin admin password
5. Click **"Sign In"**

**Troubleshooting:**
- If connection fails, verify Jellyfin is running: `sudo systemctl status jellyfin`
- Try the full local IP: `http://192.168.x.x:8096`
- Ensure Jellyfin is accessible from Jellyseerr: `curl -I http://localhost:8096`

---

## Service Integration Configuration

### Jellyfin Server Configuration

After signing in, configure the Jellyfin integration:

**Location:** Settings → Jellyfin

1. **Server Settings:**
   - Server Name: `Jellyfin` (or custom name)
   - Server URL: `http://localhost:8096`
   - Server Type: `Jellyfin`
   
2. **Authentication:**
   - Already configured from sign-in
   - Test connection: Click **"Test"** button
   - Should show green checkmark ✅

3. **Library Sync:**
   - Enable **"Scan Libraries"**
   - Enable **"Import Jellyfin Users"** ⚠️ **IMPORTANT**
   - Click **"Save Changes"**

4. **Library Sync Trigger:**
   - Click **"Sync Libraries"** to import Jellyfin users
   - This imports existing Jellyfin users into Jellyseerr
   - Family members can now use their Jellyfin credentials to sign in

---

### Radarr (Movie Automation) Configuration

**Location:** Settings → Radarr

1. Click **"Add Radarr Server"**

2. **Server Configuration:**
   ```
   Default Server:         ✅ Yes
   4K Server:              ❌ No (unless you have a separate 4K Radarr)
   Server Name:            Radarr (or custom name)
   Hostname or IP Address: localhost
   Port:                   7878
   Use SSL:                ❌ No
   API Key:                [Paste Radarr API key here]
   Base URL:               [Leave empty]
   ```

3. **Quality & Root Folder:**
   ```
   Quality Profile:        [Select from dropdown]
                          Options: Any, HD-1080p, Ultra-HD, etc.
                          Recommendation: HD-1080p or Ultra-HD
   
   Root Folder:           [Select from dropdown]
                          Should show: /data/media/movies
                          If not visible, check Radarr root folder config
   
   Minimum Availability:  Released
                          (Only request movies that are released)
   ```

4. **Advanced Settings (Optional):**
   ```
   ✅ Enable Automatic Search
      (Automatically search for movie when requested)
   
   ✅ Enable RSS Sync
      (Check RSS feeds for new releases)
   
   Tags:                  [Leave empty or add custom tags]
   External URL:          [Leave empty]
   Enable Scan:           ✅ Yes
   ```

5. **Test and Save:**
   - Click **"Test"** button
   - Should show: ✅ "Connection successful"
   - Click **"Save Changes"**

**Troubleshooting:**
- If test fails, verify Radarr is running: `sudo systemctl status radarr`
- Check API key is correct: Radarr → Settings → General → API Key
- Ensure root folder exists: `ls -la /data/media/movies`
- Test connection: `curl http://localhost:7878/api/v3/system/status?apikey=YOUR_API_KEY`

---

### Sonarr (TV Show Automation) Configuration

**Location:** Settings → Sonarr

1. Click **"Add Sonarr Server"**

2. **Server Configuration:**
   ```
   Default Server:         ✅ Yes
   4K Server:              ❌ No
   Server Name:            Sonarr (or custom name)
   Hostname or IP Address: localhost
   Port:                   8989
   Use SSL:                ❌ No
   API Key:                [Paste Sonarr API key here]
   Base URL:               [Leave empty]
   ```

3. **Quality & Root Folder:**
   ```
   Quality Profile:        [Select from dropdown]
                          Options: Any, HD-1080p, Ultra-HD, etc.
                          Recommendation: HD-1080p
   
   Root Folder:           [Select from dropdown]
                          Should show: /data/media/tv
   
   Language Profile:      English
                          (Primary subtitle/audio language)
   
   Series Type:           Standard
                          (Use Standard for most TV shows)
   ```

4. **Advanced Settings (Optional):**
   ```
   ✅ Enable Automatic Search
      (Automatically search for episodes when requested)
   
   ✅ Enable Season Folders
      (Organize episodes into season folders)
   
   Tags:                  [Leave empty or add custom tags]
   External URL:          [Leave empty]
   Enable Scan:           ✅ Yes
   ```

5. **Test and Save:**
   - Click **"Test"** button
   - Should show: ✅ "Connection successful"
   - Click **"Save Changes"**

**Troubleshooting:**
- If test fails, verify Sonarr is running: `sudo systemctl status sonarr`
- Check API key is correct: Sonarr → Settings → General → API Key
- Ensure root folder exists: `ls -la /data/media/tv`
- Test connection: `curl http://localhost:8989/api/v3/system/status?apikey=YOUR_API_KEY`

---

## User Management

### Import Users from Jellyfin

**Location:** Settings → Users

1. **Automatic Import:**
   - Users are automatically imported from Jellyfin when you enabled "Import Jellyfin Users"
   - Each Jellyfin user becomes a Jellyseerr user
   - Users sign in with their Jellyfin credentials

2. **Verify Imported Users:**
   - Go to Settings → Users
   - Should see list of users from Jellyfin
   - Each user shows: Avatar, Name, Email, Role

### User Permission Levels

Configure permissions for each user:

**Admin:**
- Full access to all settings
- Can approve/deny requests (if approval required)
- Can manage other users
- Can view all requests

**User:**
- Can browse and request content
- Can view their own requests
- Limited by request quotas
- Cannot access settings

### Configure User Permissions

**Location:** Settings → Users → [Select User]

```
Display Name:          [User's name from Jellyfin]
Email:                 [User's email]
User Type:             User (or Admin)

--- Request Limits ---
Movie Request Limit:   [Number per period]
                      Example: 10 (movies per week)
                      0 = Unlimited

Series Request Limit:  [Number per period]
                      Example: 5 (TV shows per week)
                      0 = Unlimited

Request Limit Period:  Weekly (or Daily/Monthly)

--- Permissions ---
✅ Auto-Approve Requests
   (Requests automatically approved without admin review)
   Recommendation: Enable for trusted family members

✅ Auto-Approve TV Shows
   (Separate auto-approval for TV shows)
   Recommendation: Enable

✅ Auto-Approve Movies
   (Separate auto-approval for movies)
   Recommendation: Enable

❌ Request 4K Content
   (Only enable if you have 4K Radarr/Sonarr)
```

**Save Changes** after configuring each user.

---

## Notification Configuration (Optional)

### Email Notifications

**Location:** Settings → Notifications → Email

Configure email notifications to alert users about request status:

```
Enable Agent:          ✅ Yes

--- SMTP Settings ---
Email From:            jellyseerr@yourdomain.com
SMTP Host:             smtp.gmail.com (or your SMTP server)
SMTP Port:             587
Encryption:            TLS
Auth User:             your-email@gmail.com
Auth Pass:             [Your app-specific password]

--- Test Email ---
Test Email To:         your-email@example.com
```

Click **"Test"** to verify email configuration.

### Notification Types

Configure which notifications to send:

```
✅ Request Approved      (User's request was approved)
✅ Request Available     (Content is ready to watch)
✅ Request Failed        (Download failed)
❌ Request Pending       (Request needs approval - if manual approval enabled)
✅ Media Added           (New media added to library)
✅ Media Failed          (Import to library failed)
```

### Discord/Slack Webhooks (Optional)

**Location:** Settings → Notifications → Discord/Slack

Configure webhook notifications for admin alerts:

```
Enable Agent:          ✅ Yes
Webhook URL:           [Your Discord/Slack webhook URL]
Bot Username:          Jellyseerr
Bot Avatar URL:        [Custom avatar URL - optional]
```

---

## General Settings Configuration

### Main Settings

**Location:** Settings → General

```
--- Application ---
Application Title:     Jellyseerr (or custom name)
Application URL:       http://nuc-server:5055
                      (For email notification links)

--- Display Settings ---
Display Language:      English
Discover Region:       IN (India) or US (United States)
                      (Affects trending/popular content)

--- Regional Settings ---
Partial Request:       ✅ Enable
                      (Allow requesting specific seasons/episodes)

Hide Available:        ❌ No
                      (Show already available content)
```

### Request Settings

**Location:** Settings → General (scroll down)

```
--- Default Request Settings ---
Default Movie Quality:  HD-1080p (or your preference)
Default TV Quality:     HD-1080p

--- Auto-Approval ---
✅ Auto-Approve All Requests
   (Requests go directly to Radarr/Sonarr without admin approval)
   Recommendation: Enable for family homelab

✅ Auto-Approve Movie Requests
✅ Auto-Approve TV Requests

--- 4K Settings ---
❌ Allow 4K Requests (unless you have separate 4K services)
```

---

## Testing the Request Workflow

### Test Movie Request

1. **Browse for Content:**
   - Go to Jellyseerr home page
   - Browse **"Popular Movies"** or use search
   - Find a movie NOT in your library

2. **Request Movie:**
   - Click on the movie card
   - Click **"Request"** button
   - Confirm quality profile and root folder
   - Click **"Request Movie"**

3. **Verify Request:**
   - Should see notification: "Request for [Movie Name] sent successfully"
   - Check **"Requests"** page in Jellyseerr
   - Should show status: **"Pending"** → **"Requested"**

4. **Check Radarr:**
   - Open Radarr: http://nuc-server:7878
   - Go to **"Movies"** tab
   - Should see the requested movie added
   - Status should show: **"Monitoring"** or **"Searching"**

5. **Monitor Download:**
   - Radarr searches via Prowlarr
   - Sends torrent to Deluge
   - Open Deluge: http://nuc-server:8112
   - Should see torrent downloading (via VPN)

6. **Check Import:**
   - When download completes, Radarr imports to `/data/media/movies`
   - Jellyfin automatically detects new content
   - Jellyseerr updates status to **"Available"**

7. **Watch Content:**
   - Open Jellyfin: http://nuc-server:8096
   - Movie should appear in library
   - Click play to verify streaming works

### Test TV Show Request

1. **Search for TV Show:**
   - Search for a TV show NOT in your library
   - Click on the show card

2. **Request Specific Content:**
   - Option 1: Request **All Seasons**
   - Option 2: Request **Latest Season**
   - Option 3: Request **Specific Season/Episodes**

3. **Submit Request:**
   - Select quality profile
   - Click **"Request"**
   - Should see success notification

4. **Verify in Sonarr:**
   - Open Sonarr: http://nuc-server:8989
   - Go to **"Series"** tab
   - Should see TV show added
   - Check monitoring status for requested seasons

5. **Monitor Episode Downloads:**
   - Sonarr searches for episodes
   - Downloads via Deluge (VPN-isolated)
   - Imports episodes to `/data/media/tv/[Show Name]/Season XX/`

6. **Check Jellyfin:**
   - Episodes appear in Jellyfin TV library
   - Jellyseerr status updates to **"Available"**

---

## Common Issues and Troubleshooting

### Issue: Cannot Connect to Jellyfin

**Symptoms:** "Failed to connect to Jellyfin server" error

**Solutions:**
```bash
# Check if Jellyfin is running
sudo systemctl status jellyfin

# Restart Jellyfin
sudo systemctl restart jellyfin

# Check Jellyfin is accessible
curl -I http://localhost:8096

# Check firewall allows localhost connections
sudo iptables -L -n | grep 8096
```

### Issue: Cannot Connect to Radarr/Sonarr

**Symptoms:** "Failed to connect" or "Invalid API key" errors

**Solutions:**
```bash
# Verify service is running
sudo systemctl status radarr
sudo systemctl status sonarr

# Check API key is correct
# Radarr: Settings → General → API Key
# Sonarr: Settings → General → API Key

# Test API connection
curl http://localhost:7878/api/v3/system/status?apikey=YOUR_RADARR_API_KEY
curl http://localhost:8989/api/v3/system/status?apikey=YOUR_SONARR_API_KEY

# Check service logs
sudo journalctl -u radarr -n 50
sudo journalctl -u sonarr -n 50
```

### Issue: Root Folder Not Showing

**Symptoms:** Root folder dropdown is empty in Radarr/Sonarr config

**Solutions:**
```bash
# Check directories exist and have correct permissions
ls -la /data/media/movies
ls -la /data/media/tv

# Verify ownership (should be media group)
sudo chown -R root:media /data/media/movies
sudo chown -R root:media /data/media/tv
sudo chmod -R 775 /data/media/movies
sudo chmod -R 775 /data/media/tv

# Configure root folders in Radarr/Sonarr
# Radarr → Settings → Media Management → Root Folders → Add
# Sonarr → Settings → Media Management → Root Folders → Add
```

### Issue: Users Cannot Sign In

**Symptoms:** Family members get "Invalid credentials" error

**Solutions:**
1. **Verify Import:**
   - Settings → Users
   - Check if user is listed
   - If not, re-import: Settings → Jellyfin → Sync Libraries

2. **Check Jellyfin Account:**
   - User must have account in Jellyfin first
   - User must use same credentials as Jellyfin
   - Test login directly in Jellyfin

3. **Reset Jellyseerr User:**
   - Settings → Users → [Select User]
   - Click **"Reset Password"**
   - User signs in with Jellyfin credentials

### Issue: Requests Not Going to Radarr/Sonarr

**Symptoms:** Request shows "Pending" but never sent to *arr services

**Solutions:**
```bash
# Check Jellyseerr logs
sudo journalctl -u jellyseerr -n 100

# Verify API keys are correct
# Re-test connections in Jellyseerr settings

# Check Radarr/Sonarr are monitoring correctly
# Radarr → System → Tasks → Check for new movies
# Sonarr → System → Tasks → Check for new episodes

# Manually trigger search in Radarr/Sonarr
```

### Issue: VPN Preventing Downloads

**Symptoms:** Requests sent to Radarr/Sonarr but downloads fail

**Solutions:**
```bash
# Verify VPN is connected
docker logs gluetun | grep -i connected

# Check VPN IP (should NOT be your home IP)
docker exec gluetun curl ifconfig.me

# Restart VPN stack
docker restart gluetun deluge

# Check Deluge is accessible
curl http://localhost:8112

# Verify Radarr/Sonarr can reach Deluge
# Settings → Download Clients → Test
```

---

## Security Considerations

### For Family Access

**Current Setup (Tailscale):**
- Users access via Tailscale VPN
- Requires Tailscale app on their devices
- Secure, encrypted connection
- No exposure to public internet

**Recommended Settings:**
```
✅ Auto-approve requests for trusted family
✅ Set reasonable request limits (e.g., 10 movies/week)
✅ Import users from Jellyfin (single sign-on experience)
✅ Enable email notifications for transparency
❌ Don't allow 4K requests (unless needed)
```

### For Public Exposure (Future - Cloudflare Tunnel)

When exposing Jellyseerr publicly via Cloudflare Tunnel:

**Required Precautions:**
```
✅ Strong passwords for all users
✅ Enable request limits per user
✅ Consider manual approval for new users
✅ Enable email notifications
✅ Regular security updates via NixOS
✅ Monitor request activity
✅ Use Cloudflare rate limiting
✅ Enable fail2ban on the server
```

**Cloudflare Tunnel Configuration (Future):**
```nix
# Add to configuration.nix
services.cloudflared.tunnels.homelab.ingress = {
  "request.yourdomain.com" = "http://localhost:5055";
};
```

---

## User Guide for Family Members

### How to Request a Movie

1. **Open Jellyseerr**
   - Visit: http://nuc-server:5055 (or your configured URL)

2. **Sign In**
   - Use your Jellyfin username and password
   - Same credentials you use to watch content

3. **Find Movie**
   - Browse popular/trending movies on home page
   - Or use search bar to find specific movie

4. **Check Availability**
   - Green badge = Already available in Jellyfin
   - No badge = Not available, can request

5. **Request Movie**
   - Click on movie card
   - Click **"Request"** button
   - Confirm request

6. **Track Status**
   - Go to **"Requests"** page
   - See status: Pending → Requested → Downloading → Available

7. **Watch Movie**
   - When status is "Available", open Jellyfin
   - Movie appears in your library
   - Click play and enjoy!

### How to Request a TV Show

1. **Find TV Show**
   - Browse or search for TV show

2. **Choose What to Request**
   - All Seasons: Get the entire series
   - Latest Season: Only the newest season
   - Specific Seasons: Choose which seasons you want

3. **Submit Request**
   - Click **"Request"**
   - Episodes download as they become available

4. **Watch Episodes**
   - Check "Requests" page for status
   - When available, open Jellyfin
   - Episodes appear in TV Shows library

### Tips for Users

- **Check First:** Always search before requesting - content might already be available
- **Be Patient:** Downloads can take 1-6 hours depending on size and seeders
- **Request Limits:** You can request X movies per week (check with admin)
- **Quality:** All content is HD-1080p or better
- **Notifications:** You'll receive email when your request is available (if configured)

---

## Maintenance and Monitoring

### Daily Checks

```bash
# Check service status
sudo systemctl status jellyseerr

# View recent logs
sudo journalctl -u jellyseerr --since "1 hour ago"

# Check disk space
df -h /var/lib/jellyseerr
zfs list | grep jellyseerr
```

### Weekly Maintenance

```bash
# Review request activity
# Login to Jellyseerr → Requests → View all

# Check for failed requests
# Jellyseerr → Requests → Filter: Failed

# Monitor storage usage
sudo ncdu /data/media
```

### Monthly Tasks

- Review and adjust user request limits
- Check for Jellyseerr updates (NixOS channel updates)
- Review notification settings
- Audit user permissions

---

## Backup and Recovery

### Configuration Backup

Jellyseerr configuration is stored in the ZFS dataset:

```bash
# Configuration location
/var/lib/jellyseerr

# Backup configuration
sudo rsync -av /var/lib/jellyseerr/ /backups/jellyseerr-$(date +%Y%m%d)/

# ZFS snapshot (automatic via NixOS)
sudo zfs snapshot storagepool/services/jellyseerr@manual-$(date +%Y%m%d)
```

### Restore Configuration

```bash
# From backup
sudo systemctl stop jellyseerr
sudo rsync -av /backups/jellyseerr-YYYYMMDD/ /var/lib/jellyseerr/
sudo chown -R jellyseerr:jellyseerr /var/lib/jellyseerr
sudo systemctl start jellyseerr

# From ZFS snapshot
sudo systemctl stop jellyseerr
sudo zfs rollback storagepool/services/jellyseerr@snapshot-name
sudo systemctl start jellyseerr
```

---

## Integration with Media Stack

### Complete Media Automation Flow

```
1. Family Member
   └─► Jellyseerr :5055 (Request content)
        │
        ├─► Check Jellyfin :8096 (Already available?)
        │   ├─► Yes → Show "Available" badge
        │   └─► No → Continue to request
        │
        ├─► Send to Radarr :7878 (Movies)
        │   └─► Radarr searches Prowlarr :9696
        │       └─► Prowlarr queries indexers
        │           └─► Returns results to Radarr
        │               └─► Radarr sends to Deluge :8112
        │                   └─► Deluge downloads (VPN-isolated)
        │                       └─► Saves to /data/media/downloads/complete/
        │                           └─► Radarr imports to /data/media/movies/
        │                               └─► Jellyfin detects new movie
        │                                   └─► Jellyseerr marks "Available"
        │                                       └─► User receives notification
        │
        └─► Send to Sonarr :8989 (TV Shows)
            └─► [Same flow as Radarr for TV shows]
```

### Service Dependencies

Jellyseerr requires these services to function:

**Critical Dependencies:**
- ✅ Radarr (movie requests)
- ✅ Sonarr (TV show requests)

**Optional but Recommended:**
- ✅ Jellyfin (authentication, availability checking)
- ✅ Prowlarr (search functionality via Radarr/Sonarr)
- ✅ Deluge (actual downloads)

---

## Performance Optimization

### Database Optimization

Jellyseerr uses SQLite database stored in ZFS dataset:

```bash
# Check database size
du -sh /var/lib/jellyseerr/db/db.sqlite3

# Optimize database (if performance degrades)
sudo systemctl stop jellyseerr
sqlite3 /var/lib/jellyseerr/db/db.sqlite3 "VACUUM;"
sudo systemctl start jellyseerr
```

### Cache Management

```bash
# Clear image cache (if corrupted)
sudo systemctl stop jellyseerr
sudo rm -rf /var/lib/jellyseerr/cache/*
sudo systemctl start jellyseerr
# Jellyseerr will rebuild cache automatically
```

---

## Upgrading Jellyseerr

### Via NixOS Channel Update

```bash
# Update NixOS channel
sudo nix-channel --update

# Rebuild system (updates Jellyseerr)
sudo nixos-rebuild switch

# Restart service
sudo systemctl restart jellyseerr

# Check version
curl http://localhost:5055/api/v1/status | jq .version
```

---

## Conclusion

Jellyseerr is now fully configured and integrated with your media automation stack! 🎉

### What You've Accomplished

✅ **Service Running**: Jellyseerr accessible at http://nuc-server:5055  
✅ **Jellyfin Integration**: Users authenticate with Jellyfin credentials  
✅ **Radarr Integration**: Movie requests sent automatically  
✅ **Sonarr Integration**: TV show requests sent automatically  
✅ **User Management**: Family members can request content  
✅ **Request Tracking**: Monitor requests from submission to availability  

### Next Steps

1. **Test Request Workflow**: Request a movie and verify full automation
2. **Add Family Members**: Import users from Jellyfin
3. **Configure Notifications**: Set up email alerts (optional)
4. **Public Access**: Configure Cloudflare Tunnel for external access (future)

### Quick Reference

**Service URLs (via Tailscale):**
- Jellyseerr: http://nuc-server:5055
- Jellyfin: http://nuc-server:8096
- Radarr: http://nuc-server:7878
- Sonarr: http://nuc-server:8989
- Prowlarr: http://nuc-server:9696
- Deluge: http://nuc-server:8112

**Important Commands:**
```bash
# Service status
sudo systemctl status jellyseerr

# View logs
sudo journalctl -u jellyseerr -f

# Restart service
sudo systemctl restart jellyseerr

# Check configuration
cat /etc/nixos/configuration.nix | grep -A 50 "PHASE 4"
```

---

**Happy requesting! Your family can now enjoy a Netflix-like request experience with your self-hosted media server! 🍿📺**