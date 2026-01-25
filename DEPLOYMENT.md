# Media Automation Deployment Guide

## Changes Summary

Added complete media automation stack with manual file management:

**New services**:
- LazyLibrarian (port 5299) - Ebook/audiobook automation (Docker with Calibre support)
- FileBrowser (port 8085) - Web-based file manager

**Commits**:
```
89674b4 fix: move lazylibrarian to zfs instead of nvme
e5377f7 chore: wire up lazylibrarian and filebrowser services
49d0e68 chore: add lazylibrarian zfs dataset and mount
9bfd0d4 feat: add filebrowser for web-based file management
c2aacd6 feat: add lazylibrarian for ebook/audiobook automation
```

---

## Deployment Steps

### 1. Deploy to karmalab

```bash
ssh karmalab
cd ~/karmalab
git pull origin main

# Deploy configuration
sudo nixos-rebuild switch

# Check service status
systemctl status docker-lazylibrarian
systemctl status filebrowser

# View logs
journalctl -u docker-lazylibrarian -n 50 -f
journalctl -u filebrowser -n 50 -f

# Check Docker container
docker ps | grep lazylibrarian
docker logs lazylibrarian
```

---

## Service Configuration

### LazyLibrarian (http://192.168.0.200:5299) - Docker Container

**Docker image**: LinuxServer.io `lazylibrarian:latest` with Calibre Docker Mod  
**HTTP Proxy**: Routes public sources through Gluetun Iceland VPN (privacy)  
**Seeding**: Configured for private tracker reputation (ratio 2.0, 7 days minimum)

---

#### Initial Setup Wizard

1. Access http://192.168.0.200:5299
2. Complete setup wizard (no authentication required initially)
3. **IMPORTANT: Set admin password immediately**:
   - Settings → Security → Admin Password
   - Username: `admin` (default)
   - Password: (strong password)
   - Save

---

#### Configure Calibre Integration

**Purpose**: Auto-import ebooks to Calibre library with metadata fetching

**Steps**:
1. Settings → Processing → Calibre
2. Calibre executable path: `/usr/bin/calibredb` (pre-installed via Docker Mod)
3. Calibre library path: `/books` (container mount point)
4. Import mode: `copy` (leaves original in downloads for seeding)
5. Auto-import: ✅ Enable
6. Auto-update metadata: ✅ Enable
7. Fetch covers: ✅ Enable
8. Test → Should show green checkmark
9. Save

**How it works**:
- LazyLibrarian downloads ebook → `/downloads/`
- Calls `calibredb import --library-path=/books /downloads/book.epub`
- Calibre adds book with metadata (title, author, cover, ISBN, etc.)
- Original file stays in `/downloads/` for seeding torrents
- Book appears in Calibre-Web immediately at http://192.168.0.200:8083

---

#### Configure Prowlarr Integration

**Purpose**: Search MAM + TorrentLeech with freeleech filtering (ratio protection)

##### In Prowlarr (http://192.168.0.200:9696)

**1. Add MyAnonaMouse (MAM) indexer**:
- Settings → Indexers → Add Indexer → Search "MyAnonaMouse"
- Name: `MyAnonaMouse`
- Base URL: `https://www.myanonamouse.net`
- **Cookie authentication**:
  - Open MAM in browser, login
  - Press F12 → Application tab → Cookies → `myanonamouse.net`
  - Copy `mam_id` cookie value
  - Paste into Prowlarr cookie field
- Categories: ✅ Books, ✅ Audiobooks
- Additional parameters:
  - Minimum Seeders: `1`
  - **Freeleech Only**: ✅ **CRITICAL - ENABLE THIS**
- Test → Should show green checkmark
- Save

**2. Add TorrentLeech indexer**:
- Add Indexer → Search "TorrentLeech"
- Name: `TorrentLeech`
- **API Key**: (get from https://www.torrentleech.org/profile)
- Categories: ✅ Books, ✅ Audiobooks
- Additional parameters:
  - Minimum Seeders: `1`
  - **Freeleech Only**: ✅ **CRITICAL - ENABLE THIS**
- Test → Should show green checkmark
- Save

**3. Add LazyLibrarian as application**:
- Settings → Apps → Add Application
- Type: `LazyLibrarian`
- Prowlarr Server: `http://127.0.0.1:9696` (leave default)
- LazyLibrarian Server: `http://127.0.0.1:5299`
- **API Key**: Get from LazyLibrarian:
  - LazyLibrarian → Settings → General → API Key
  - Copy the key
- Sync Level: `Add and Remove Only`
- Tags: (leave empty)
- Test → Should show green checkmark
- Save
- **Click "Sync All" button** → Pushes MAM + TorrentLeech to LazyLibrarian

##### In LazyLibrarian (http://192.168.0.200:5299)

- Settings → Indexers
- Should see MAM + TorrentLeech appear automatically after Prowlarr sync
- Verify both show:
  - Type: `Newznab/Torznab`
  - Enabled: ✅
  - Categories: Books, Audiobooks
- **Verify freeleech filter**:
  - Click "Test" on each indexer
  - Should only return freeleech results

---

#### Configure Deluge (Torrent Download Client)

**Purpose**: Download torrents via VPN with proper seeding for private tracker reputation

**Steps**:
1. Settings → Download Clients → Deluge
2. **Connection**:
   - Host: `127.0.0.1`
   - Port: `58846`
   - Username: `admin` (default, or check Deluge settings)
   - Password: Get from Deluge web UI:
     - Open http://192.168.0.200:8112
     - Preferences → Interface → Password
3. **Label**: `lazylibrarian` (auto-applied to all LazyLibrarian torrents)
4. **Download directory**: `/downloads` (container mount point)
5. **Seeding settings** (CRITICAL for private tracker reputation):
   - Remove at ratio: `2.0` (upload 200% of download size)
   - Remove at time: `168` hours (7 days = 168 hours)
   - Remove condition: `ratio AND time` (must meet BOTH requirements)
   - **Why these settings**:
     - MAM/TorrentLeech track upload/download ratio
     - Good ratio = account standing, avoid warnings/bans
     - 2.0 ratio is generous, builds reputation quickly
     - 7 days ensures good availability for community
6. **Test connection** → Should show green checkmark
7. Save

**Important**: Torrents will continue seeding until BOTH ratio ≥2.0 AND time ≥168 hours

---

#### Configure Search Sources & Priority

**Purpose**: Search public sources first (free), private trackers last (ratio protection)

**Steps**:
1. Settings → Search → Sources

**Ebooks** (public sources first, private trackers last):
- ✅ Anna's Archive: Priority `10`, Enable ✅
- ✅ Libgen: Priority `9`, Enable ✅
- ✅ MAM (via Prowlarr): Priority `5`, Freeleech only ✅
- ❌ Direct torrent sites (handled by Prowlarr)

**Audiobooks** (private trackers first for quality):
- ✅ MAM (via Prowlarr): Priority `10`, Freeleech preferred ✅
- ✅ AudioBook Bay: Priority `5`, Enable ✅

**Metadata sources**:
- ✅ Goodreads: Enable for book metadata
- ✅ Google Books: Enable as fallback

**Why this order**:
- Public sources are free (no ratio concerns)
- MAM freeleech protects your ratio (only downloads freeleech)
- Higher priority = searched first
- Ebooks: Public sources abundant, use them first
- Audiobooks: MAM has better quality, prefer it

2. Save

---

#### Configure Quality Preferences

**Purpose**: Prefer best formats, reject bloated/corrupt files

**Steps**:
1. Settings → Quality

**Ebooks**:
- Preferred formats (in order): `EPUB, MOBI, AZW3, PDF`
- Maximum file size: `50 MB`
- Minimum file size: `0.1 MB` (100 KB)
- Reject keywords: `sample, preview, corrupt`

**Audiobooks**:
- Preferred formats (in order): `M4B, MP3`
- Maximum file size: `500 MB`
- Minimum file size: `10 MB`
- Reject keywords: `sample, preview, incomplete`

**Why these settings**:
- EPUB: Most compatible ebook format, works everywhere
- M4B: Superior for audiobooks (single file, chapter markers, metadata)
- Size limits prevent bloated scans and corrupt files
- Reject keywords filter out incomplete downloads

2. Save

---

#### Configure Author Monitoring (Conservative Approach)

**Purpose**: Monitor authors for new releases, require manual approval before downloading

**Steps**:
1. Settings → Processing

**Monitoring settings**:
- Author check interval: `12 hours`
- Auto-add new books: ❌ **Disabled** (manual approval required)
- Mark new books as: `Skipped` (not automatic "Wanted")
- Process audiobooks: ✅ Enable

**How to use**:
1. Add author to library (Search → Author → Add Author)
2. LazyLibrarian checks for new releases every 12 hours
3. New books appear on author page as "Skipped"
4. Review book details (rating, reviews, format availability)
5. Click "Wanted" button to manually approve download
6. LazyLibrarian searches and downloads approved books only

**Why conservative approach**:
- Prevents automatic downloads of unwanted content (sequels, spin-offs, etc.)
- Protects private tracker ratio (no wasted downloads)
- Gives you control over what enters your library
- Allows quality review before downloading (check ratings, reviews)

2. Save

---

#### Verify HTTP Proxy (Privacy Check)

**Purpose**: Ensure all public source downloads route through Iceland VPN (ISP can't see traffic)

**Steps**:
1. Settings → General → HTTP Proxy
2. Verify settings (should be auto-configured via Docker environment):
   - Proxy URL: `http://127.0.0.1:8888`
   - Proxy type: `HTTP`
   - No authentication required
3. Save

**Test proxy is working**:

```bash
# 1. Download a book from Anna's Archive (any public source)
# 2. Check Gluetun logs for LazyLibrarian connections
ssh karmalab
docker logs gluetun 2>&1 | tail -100 | grep -E "CONNECT|GET|HTTP"

# Should see connections from LazyLibrarian container

# 3. Verify Iceland IP (not your India ISP IP)
docker exec gluetun wget -qO- https://api.ipify.org

# Should show Iceland IP address
```

**Why this matters**:
- Anna's Archive, Libgen, Z-Library are "piracy" sites
- ISP can see your DNS queries and HTTP traffic to these domains
- HTTP proxy routes ALL traffic through Iceland VPN
- ISP only sees encrypted WireGuard traffic to Surfshark servers
- Protects your privacy and avoids ISP warnings/throttling

---

### FileBrowser (http://192.168.0.200:8085)

**Initial setup**:
1. Login with default: `admin/admin`
2. **IMMEDIATELY change password**:
   - Settings → User Management → Edit admin → Change password
3. Create your user:
   - Settings → User Management → Add User
   - Username: `somesh`
   - Password: (strong password)
   - Scope: `/data/media`
   - Permissions: Check ALL (Admin, Execute, Create, Rename, Modify, Delete, Share, Download)
   - Save
4. Logout, login as `somesh`
5. Delete default admin:
   - Settings → User Management → Delete `admin`
6. Disable signup:
   - Settings → Global Settings → Signup: Disable

**Add custom command - Refresh Jellyfin**:
1. Get Jellyfin API key:
   - Login to Jellyfin: http://192.168.0.200:8096
   - Dashboard → API Keys → Add API Key
   - Name: `FileBrowser`
   - Copy the generated key

2. Add command in FileBrowser:
   - Settings → Commands → Add Command
   - Name: `Refresh Jellyfin Library`
   - Command:
     ```bash
     curl -X POST "http://192.168.0.200:8096/Library/Refresh" -H "X-MediaBrowser-Token: YOUR_API_KEY_HERE"
     ```
   - Replace `YOUR_API_KEY_HERE` with the key from step 1
   - Save

**Usage**: Right-click any file → "Refresh Jellyfin Library"

---

## Testing Workflows

### Test 1: Ebook Download via Public Source (HTTP Proxy)

**Purpose**: Verify direct downloads work through Gluetun proxy for privacy

**Steps**:
1. Open LazyLibrarian: http://192.168.0.200:5299
2. Search for popular book: `Project Hail Mary`
3. Click "Add Book" (automatically marked as "Wanted")
4. Navigate to Status page → Should show search progress
5. Should find multiple sources (Anna's Archive, Libgen)
6. Download starts automatically
7. **Check download location**:
   ```bash
   ssh karmalab
   ls -lh /data/media/downloads/complete/lazylibrarian/
   ```
8. **Verify Calibre import** (~30 seconds after download):
   ```bash
   ls -lh /data/media/ebooks/calibre-library/
   # Should see new author folder with book
   ```
9. **Verify in Calibre-Web**:
   - Open http://192.168.0.200:8083
   - Search for "Project Hail Mary"
   - Book should appear with cover, metadata
10. **Verify HTTP proxy usage**:
    ```bash
    docker logs gluetun 2>&1 | tail -200 | grep -i "annas-archive\|libgen"
    ```

**Expected result**: Book downloads via proxy, imports to Calibre, appears in Calibre-Web  
**Time**: ~5 minutes

---

### Test 2: Audiobook Download via MAM (Freeleech Torrent)

**Purpose**: Verify private tracker integration, freeleech filtering, and seeding

**Prerequisites**: MAM freeleech audiobook exists (check MAM site first)

**Steps**:
1. Open LazyLibrarian: http://192.168.0.200:5299
2. Search for audiobook: `The Martian` (usually has freeleech)
3. Click "Add Audiobook"
4. Mark as "Wanted"
5. Navigate to Status page → Should show MAM search
6. **Verify freeleech filter**:
   - Only freeleech torrents should appear
   - If no results, try different audiobook
7. Download queues via Deluge
8. **Check Deluge**:
   - Open http://192.168.0.200:8112
   - Should see torrent with label `lazylibrarian`
   - Status: Downloading (or Seeding if complete)
   - Ratio: 0.0/2.0, Time: 0h/168h
9. **Wait for download to complete** (~5-30 min depending on size)
10. **Verify file moves to audiobooks**:
    ```bash
    ls -lh /data/media/audiobooks/
    ```
11. **Verify torrent stays seeding**:
    - Check Deluge → Torrent still present
    - Status: Seeding
    - Will remain until ratio ≥2.0 AND time ≥168 hours (7 days)
12. **Verify in Audiobookshelf**:
    - Open http://192.168.0.200:13378
    - Trigger library scan: Settings → Libraries → Scan
    - Audiobook should appear

**Expected result**: Audiobook downloads, imports to Audiobookshelf, torrent continues seeding  
**Time**: ~10 minutes (excluding download time)

---

### Test 3: Author Monitoring (Conservative Approach)

**Purpose**: Verify author monitoring requires manual approval (no automatic downloads)

**Steps**:
1. Open LazyLibrarian: http://192.168.0.200:5299
2. Search for prolific author: `Brandon Sanderson`
3. Click author name → View author page
4. Click "Add Author"
5. **Wait 2 minutes** (or trigger manual search: Author page → Search button)
6. Author page updates with complete book list
7. **Verify books are "Skipped"** (NOT "Wanted"):
   - All books should show status "Skipped"
   - No automatic downloads triggered
8. **Manually approve one book**:
   - Find a book you want (e.g., "Mistborn: The Final Empire")
   - Click "Wanted" button
   - Status changes from "Skipped" to "Wanted"
9. LazyLibrarian immediately searches for book
10. Download starts when found (check Status page)
11. **Add another author for ongoing monitoring**:
    - Add author with upcoming releases
    - Verify author added to monitoring list
    - Settings → Processing → Shows next author check time

**Expected result**: Authors monitored, books require manual approval, no automatic downloads  
**Time**: ~5 minutes

---

### Test 4: Manual Torrent + FileBrowser

**Purpose**: Verify manual torrent workflow with FileBrowser file management

**Steps**:
1. Find movie magnet link on 1337x or similar site
2. Open Deluge: http://192.168.0.200:8112
3. Add magnet link → Downloads to `/data/media/downloads/complete`
4. Wait for download to complete
5. Open FileBrowser: http://192.168.0.200:8085
6. Navigate to `downloads/complete/`
7. Find movie file → Right-click → Cut
8. Navigate to `movies/`
9. Right-click → Paste
10. Right-click anywhere → "Refresh Jellyfin Library"
11. Open Jellyfin: http://192.168.0.200:8096
12. Movie should appear within 30 seconds

**Expected result**: Manual torrent workflow works, FileBrowser simplifies file management  
**Time**: ~10 minutes (excluding download time)

---

## Troubleshooting

### LazyLibrarian container not starting

```bash
# Check Docker container status
docker ps -a | grep lazylibrarian

# Check container logs
docker logs lazylibrarian

# Check systemd service
systemctl status docker-lazylibrarian.service

# Check dependencies
systemctl status docker-gluetun.service
systemctl status storage-online.target

# Check permissions
ls -lhd /var/lib/lazylibrarian
ls -lhd /data/media/downloads/complete/lazylibrarian

# Fix permissions if needed
sudo chown -R 2000:2000 /var/lib/lazylibrarian
sudo chown -R root:media /data/media/downloads/complete/lazylibrarian
sudo chmod 0775 /data/media/downloads/complete/lazylibrarian
```

---

### HTTP proxy not working

```bash
# Check Gluetun container is running
docker ps | grep gluetun

# Check Gluetun logs
docker logs gluetun | tail -100

# Verify Iceland VPN connection
docker exec gluetun wget -qO- https://api.ipify.org
# Should show Iceland IP, not India IP

# Test proxy from LazyLibrarian container
docker exec lazylibrarian wget -e use_proxy=yes -e http_proxy=127.0.0.1:8888 -qO- https://api.ipify.org
# Should show Iceland IP

# Check LazyLibrarian environment variables
docker inspect lazylibrarian | grep -i proxy
# Should show HTTP_PROXY and HTTPS_PROXY set to http://127.0.0.1:8888
```

---

### MAM/TorrentLeech not appearing in LazyLibrarian

```bash
# 1. Check Prowlarr connection
# In LazyLibrarian: Settings → Indexers → Should see "Prowlarr" section
# Verify Prowlarr URL and API key are correct

# 2. Check Prowlarr has indexers configured
# In Prowlarr: Settings → Indexers → Should see MAM + TorrentLeech

# 3. Sync indexers manually
# In Prowlarr: Settings → Apps → Find LazyLibrarian → Click "Sync"
# Should see "Synced successfully" message

# 4. Check LazyLibrarian logs
docker logs lazylibrarian | grep -i prowlarr

# 5. Test indexer in Prowlarr directly
# Prowlarr → Indexers → MAM → Test
# Should return results (freeleech only)
```

---

### Freeleech filter not working

```bash
# 1. Verify Prowlarr indexer settings
# Prowlarr → Settings → Indexers → MAM
# Ensure "Freeleech Only" checkbox is ENABLED ✅

# 2. Test search in Prowlarr
# Prowlarr → Search → Search for book
# Results should only show freeleech torrents (FL icon)

# 3. Check if any freeleech content exists
# Login to MAM directly, search for ebooks
# Filter by freeleech to see availability

# 4. Check LazyLibrarian search logs
docker logs lazylibrarian | grep -i "freeleech\|mam"
```

---

### Calibre import not working

```bash
# Check Calibre is available in container
docker exec lazylibrarian which calibredb
# Should output: /usr/bin/calibredb

# Check Calibre version
docker exec lazylibrarian calibredb --version

# Test manual import
docker exec lazylibrarian calibredb add /downloads/test.epub --library-path=/books

# Check Calibre library permissions
ls -lh /data/media/ebooks/calibre-library/

# Check LazyLibrarian logs for Calibre errors
docker logs lazylibrarian | grep -i calibre
```

---

### Deluge connection failed

```bash
# Check Deluge is running
systemctl status deluge-service.service

# Check Deluge web UI accessible
curl -I http://127.0.0.1:58846

# Get Deluge password
# Deluge web UI → Preferences → Interface → Password

# Test connection from LazyLibrarian container
docker exec lazylibrarian telnet 127.0.0.1 58846
# Should connect (Ctrl+C to exit)

# Check LazyLibrarian logs for Deluge errors
docker logs lazylibrarian | grep -i deluge
```

---

### Seeding stops prematurely

```bash
# Check Deluge seed settings
# Deluge web UI → Preferences → Queue

# Verify settings:
# - Share Ratio Limit: 2.0
# - Seed Time Limit: 10080 minutes (168 hours = 7 days)
# - Stop seeding when: "ratio AND time" (NOT "ratio OR time")

# Check torrent status in Deluge
# Should show:
# - Ratio: X.X/2.0
# - Time: XXh/168h
# - Status: Seeding (if ratio < 2.0 OR time < 168h)

# Check LazyLibrarian label in Deluge
# All LazyLibrarian torrents should have "lazylibrarian" label
```

---

## Next Steps

After deployment and testing:

1. **Monitor services** (first 24 hours):
   ```bash
   # Check logs for errors
   docker logs lazylibrarian --tail 100 -f
   
   # Monitor Gluetun proxy usage
   docker logs gluetun | grep -i lazylibrarian
   
   # Check MAM ratio (should increase if seeding)
   # Login to MAM, check your profile
   
   # Verify author monitoring triggers
   # Check LazyLibrarian logs every 12 hours for "Checking authors"
   ```

2. **Add Uptime Kuma monitoring**:
   - LazyLibrarian: http://192.168.0.200:5299
   - FileBrowser: http://192.168.0.200:8085
   - Check interval: 5 minutes
   - Alert on failure

3. **Document any issues** for future refinement

---

## Service Access Summary

| Service | Local URL | External URL | Purpose |
|---------|-----------|--------------|---------|
| LazyLibrarian | http://192.168.0.200:5299 | N/A (local only) | Ebook/audiobook automation |
| FileBrowser | http://192.168.0.200:8085 | https://files.somesh.dev (local only) | Web file manager |
| Prowlarr | http://192.168.0.200:9696 | N/A | Indexer management |
| Radarr | http://192.168.0.200:7878 | N/A | Movie automation |
| Sonarr | http://192.168.0.200:8989 | N/A | TV automation |
| Deluge | http://192.168.0.200:8112 | N/A | Torrent client |
| Calibre-Web | http://192.168.0.200:8083 | https://books.somesh.dev | Ebook library |
| Audiobookshelf | http://192.168.0.200:13378 | https://audiobooks.somesh.dev | Audiobook library |
| Jellyfin | http://192.168.0.200:8096 | https://jellyfin.somesh.dev | Movie/TV streaming |

---

## Estimated Timeline

- **Deployment**: 5 minutes
- **LazyLibrarian initial setup**: 5 minutes
- **Calibre integration**: 5 minutes
- **Prowlarr integration**: 10 minutes (MAM + TorrentLeech)
- **Deluge configuration**: 5 minutes
- **Search sources & quality**: 5 minutes
- **HTTP proxy verification**: 3 minutes
- **Testing**: 20 minutes (3 tests)

**Total**: ~1 hour for complete setup and testing

---

**Ready to deploy!** Push changes to main and deploy on karmalab.
