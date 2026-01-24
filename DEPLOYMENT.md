# Media Automation Deployment Guide

## Changes Summary

Added complete media automation stack with manual file management:

**New services**:
- LazyLibrarian (port 5299) - Ebook/audiobook automation
- FileBrowser (port 8085) - Web-based file manager

**Commits**:
```
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
git fetch origin
git checkout feature/media-automation
git pull origin feature/media-automation

# Deploy configuration
sudo nixos-rebuild switch

# Check service status
sudo systemctl status lazylibrarian
sudo systemctl status filebrowser

# View logs
journalctl -u lazylibrarian -n 50 -f
journalctl -u filebrowser -n 50 -f
```

---

## Service Configuration

### LazyLibrarian (http://192.168.0.200:5299)

**Initial setup wizard**:
1. Set admin username/password
2. Configure directories:
   - Ebook library: `/data/media/ebooks/calibre-library`
   - Audiobook library: `/data/media/audiobooks`
   - Download directory: `/data/media/downloads/complete`

**Configure Deluge**:
- Settings → Download Client → Deluge
- Host: `192.168.0.200`
- Port: `58846`
- Username/password: (from Deluge web UI)
- Category: `lazylibrarian`
- Test connection

**Configure Prowlarr**:
- Settings → Indexers → Prowlarr
- URL: `http://192.168.0.200:9696`
- API Key: (from Prowlarr Settings → General → Security)
- Enable sync → Click "Sync" button

**Set search priorities**:
- Settings → Search Priorities
- Ebooks: Public sources first, MAM last (freeleech only)
- Audiobooks: MAM first (freeleech preferred)

**Configure Calibre integration**:
- Settings → Calibre
- Calibre path: `/data/media/ebooks/calibre-library`
- Auto-import: Enable

**Quality settings**:
- Settings → Quality
- Ebook formats: EPUB > MOBI > AZW3 > PDF
- Audiobook formats: M4B > MP3
- Max file size: 50MB (ebooks), 500MB (audiobooks)

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

## Prowlarr Configuration

### Add MyAnonaMouse (MAM)

1. Prowlarr → Settings → Indexers → Add Indexer
2. Search for "MyAnonaMouse"
3. Configure:
   - Name: `MyAnonaMouse`
   - Base URL: `https://www.myanonamouse.net`
   - Cookie: (get from browser dev tools after logging into MAM)
     - Open MAM in browser, login
     - Press F12 → Application → Cookies → `myanonamouse.net`
     - Copy value of `mam_id` cookie
   - Categories: Books, Audiobooks
   - Minimum seeders: `1`
   - Enable "Freeleech Only": ✅
   - Test → Should show green checkmark
   - Save

### Add TorrentLeech

1. Add Indexer → Search for "TorrentLeech"
2. Configure:
   - Name: `TorrentLeech`
   - API Key: (from TorrentLeech profile page)
   - Categories: Movies, TV
   - Minimum seeders: `5`
   - Enable "Freeleech Only": ✅
   - Test → Save

### Configure HTTP Proxy

Settings → General → Proxy:
- Type: `HTTP(S)`
- Host: `192.168.0.200`
- Port: `8888`
- Bypass local addresses: ✅
- Test → Save

### Sync to Apps

Settings → Apps:
- Verify Radarr, Sonarr, Bazarr are listed
- Click "Sync" button on each app
- MAM and TorrentLeech will appear as indexers in Radarr/Sonarr

---

## Radarr/Sonarr Quality Profiles

### Radarr - 1080p HEVC Efficient

**Create custom quality profile**:
1. Settings → Profiles → Add Profile
2. Name: `1080p HEVC Efficient`
3. Qualities (check these):
   - ✅ Bluray-1080p
   - ✅ WEB-DL 1080p
   - ✅ WEBRip-1080p
   - ✅ HDTV-1080p
4. Quality order (drag to reorder):
   1. WEB-DL 1080p
   2. Bluray-1080p
   3. WEBRip-1080p
   4. HDTV-1080p
5. Size limits:
   - Min: `800 MB`
   - Max: `4000 MB` (4GB)
6. Save

**Create custom format - x265/HEVC**:
1. Settings → Custom Formats → Add Custom Format
2. Name: `x265 / HEVC`
3. Add Condition → Release Title
4. Regular Expression: `(x265|HEVC|h265)`
5. Score: `100` (strongly prefer)
6. Save

**Create custom format - Bloated Encodes**:
1. Add Custom Format
2. Name: `Bloated Encodes`
3. Add Condition → Size
4. Min: `6000 MB` (6GB)
5. Score: `-50` (discourage)
6. Save

**Apply to all movies**:
1. Movies → Mass Editor
2. Select All
3. Change Quality Profile → `1080p HEVC Efficient`
4. Save

### Sonarr - Same Process

Repeat above steps in Sonarr with per-episode sizing:
- Min: `200 MB/episode`
- Max: `1500 MB/episode`

---

## Testing Workflows

### Test 1: Ebook Download (Public Source)

1. Open LazyLibrarian: http://192.168.0.200:5299
2. Search for a popular book (e.g., "The Martian")
3. Click "Add Book"
4. Wait for search (check Status page)
5. Should find on Anna's Archive or Libgen
6. Downloads to `/data/media/downloads/complete`
7. Moves to `/data/media/ebooks/calibre-library`
8. Open Calibre-Web: http://192.168.0.200:8083
9. Book should appear (refresh if needed)

### Test 2: Manual Torrent + FileBrowser

1. Find movie magnet link on 1337x
2. Open Deluge: http://192.168.0.200:8112
3. Add magnet link → Downloads to `/data/media/downloads/complete`
4. Open FileBrowser: http://192.168.0.200:8085
5. Navigate to `downloads/complete/`
6. Find movie file → Right-click → Cut
7. Navigate to `movies/`
8. Right-click → Paste
9. Right-click anywhere → "Refresh Jellyfin Library"
10. Open Jellyfin: http://192.168.0.200:8096
11. Movie should appear within 30 seconds

### Test 3: Audiobook from MAM (Freeleech)

1. Open LazyLibrarian
2. Search for audiobook (e.g., "Project Hail Mary")
3. Add audiobook
4. Should search MAM first (freeleech preferred)
5. Downloads via Deluge through VPN
6. Moves to `/data/media/audiobooks`
7. Open Audiobookshelf: http://192.168.0.200:13378
8. Audiobook should appear after library scan

---

## Troubleshooting

### LazyLibrarian not starting

```bash
# Check service status
sudo systemctl status lazylibrarian

# View logs
journalctl -u lazylibrarian -n 100

# Check permissions
ls -lh /var/lib/lazylibrarian
ls -lh /data/media/ebooks
```

### FileBrowser not starting

```bash
# Check service status
sudo systemctl status filebrowser

# View logs
journalctl -u filebrowser -n 100

# Check if directory exists
ls -lh /var/lib/filebrowser
```

### MAM not appearing in LazyLibrarian

1. Check Prowlarr connection:
   - LazyLibrarian → Settings → Indexers → Prowlarr
   - Test connection → Should be green
2. Check Prowlarr has MAM configured
3. Click "Sync" in LazyLibrarian Prowlarr settings

### Freeleech filter not working

1. Check Prowlarr indexer settings:
   - Edit MAM indexer
   - Verify "Freeleech Only" is checked
2. Test search in Prowlarr directly
3. Check if any freeleech torrents exist for your search

---

## Next Steps

After deployment and testing:

1. **Merge to main**:
   ```bash
   cd ~/projects/experiments/nixos-homelab-v2
   git checkout main
   git merge feature/media-automation
   git push origin main
   ```

2. **Monitor services** (24 hours):
   - Check logs for errors
   - Test downloads from each source
   - Verify file permissions

3. **Add Uptime Kuma monitoring**:
   - LazyLibrarian: http://192.168.0.200:5299
   - FileBrowser: http://192.168.0.200:8085

4. **Document any issues** for future refinement

---

## Service Access Summary

| Service | Local URL | External URL | Purpose |
|---------|-----------|--------------|---------|
| LazyLibrarian | http://192.168.0.200:5299 | N/A | Ebook/audiobook automation |
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

- **Deployment**: 10 minutes
- **LazyLibrarian config**: 30 minutes
- **FileBrowser config**: 10 minutes
- **Prowlarr config**: 20 minutes
- **Radarr/Sonarr profiles**: 20 minutes
- **Testing**: 30 minutes

**Total**: ~2 hours for complete setup and testing

---

**Ready to deploy!** Branch `feature/media-automation` pushed to GitHub.
