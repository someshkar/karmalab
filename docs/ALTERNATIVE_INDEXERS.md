# Alternative Public Indexers for Prowlarr

This document lists reliable public torrent indexers to use as alternatives or backups to 1337x.

## ⭐ Recommended Public Indexers (2026)

### 1. YTS / YTS.mx ⭐⭐⭐⭐⭐
- **Focus:** Movies only (high quality encodes)
- **URL:** https://yts.mx
- **Pros:** 
  - Small file sizes (720p/1080p optimized)
  - Fast downloads
  - No Cloudflare protection needed
  - Consistent quality
- **Cons:** 
  - Movies only (no TV shows)
  - Limited to popular mainstream content
- **Status:** Active and reliable
- **Prowlarr:** Built-in indexer, easy to add

---

### 2. EZTV / EZTV.re ⭐⭐⭐⭐⭐
- **Focus:** TV shows exclusively
- **URL:** https://eztv.re
- **Pros:**
  - Daily updates for new TV episodes
  - Very reliable
  - No Cloudflare protection
  - Organized by show
- **Cons:**
  - TV shows only (no movies)
- **Status:** Active and reliable
- **Prowlarr:** Built-in indexer, easy to add

---

### 3. TorrentGalaxy / torrentgalaxy.to ⭐⭐⭐⭐
- **Focus:** Movies, TV shows, Games, Software
- **URL:** https://torrentgalaxy.to
- **Pros:**
  - Good variety of content
  - Active community
  - Both movies and TV
- **Cons:**
  - May require Flaresolverr for Cloudflare bypass
  - Quality varies
- **Status:** Active
- **Prowlarr:** Built-in indexer

---

### 4. The Pirate Bay ⭐⭐⭐
- **Focus:** Everything (movies, TV, music, software, games)
- **URL:** https://thepiratebay.org
- **Mirrors:** Multiple mirrors available if main site is blocked
- **Pros:**
  - Huge library (largest public tracker)
  - Well-known and established
  - Community-driven
- **Cons:**
  - **Requires Flaresolverr** for Cloudflare bypass
  - Quality varies (need to check comments/ratings)
  - Frequently blocked in many countries
  - Many mirrors needed
- **Status:** Active but requires careful configuration
- **Prowlarr:** Built-in indexer, configure with Flaresolverr

---

### 5. LimeTorrents / limetorrents.lol ⭐⭐⭐
- **Focus:** Movies, TV shows, Games, Software
- **URL:** https://limetorrents.lol
- **Pros:**
  - Good backup option
  - Decent variety
- **Cons:**
  - Quality varies
  - Smaller library than others
- **Status:** Active
- **Prowlarr:** Built-in indexer

---

### 6. Torlock / torlock.com ⭐⭐⭐
- **Focus:** Verified torrents only
- **URL:** https://torlock.com
- **Pros:**
  - No fake torrents (verified only)
  - Quality control
- **Cons:**
  - Smaller library due to verification requirement
- **Status:** Active
- **Prowlarr:** Built-in indexer

---

## 1337x Mirrors

If 1337x.to is blocked but you want to keep using 1337x, try these official mirrors:

- https://1337x.st
- https://x1337x.ws
- https://x1337x.eu
- https://x1337x.se

These mirrors may not be blocked in your region even if the main site is.

---

## Configuration in Prowlarr

### Adding a New Indexer

1. Open Prowlarr web UI: http://192.168.0.200:9696
2. Go to **Settings** → **Indexers**
3. Click **Add Indexer** (big + button)
4. Search for the indexer name (e.g., "YTS", "EZTV", "TorrentGalaxy")
5. Click on the indexer to configure
6. Fill in any required fields (most are pre-configured)
7. Click **Test** to verify connectivity
8. Click **Save**

### Configuring Flaresolverr (for Cloudflare-protected sites)

Some indexers (The Pirate Bay, TorrentGalaxy) require Flaresolverr to bypass Cloudflare protection.

1. Ensure Flaresolverr is running:
   ```bash
   systemctl status flaresolverr.service
   ```

2. In Prowlarr, go to **Settings** → **Indexers**
3. When adding an indexer that requires Cloudflare bypass:
   - Enable "Use Flaresolverr"
   - Set Flaresolverr URL: `http://localhost:8191`

---

## Recommended Strategy

**For Movies + TV (Comprehensive Coverage):**
1. **YTS** - High quality movies, small files
2. **EZTV** - TV shows, daily updates
3. **TorrentGalaxy** - Backup for both movies and TV
4. **1337x** (via Iceland VPN once fixed) - Comprehensive coverage

**For Quick Setup (No Flaresolverr needed):**
1. **YTS** - Movies
2. **EZTV** - TV shows
3. **LimeTorrents** - Backup for both

**For Maximum Coverage (Advanced):**
1. All of the above
2. **The Pirate Bay** (with Flaresolverr)
3. Consider private trackers if you have invites

---

## Testing Indexers

After adding indexers, test them:

1. Go to **Settings** → **Indexers** in Prowlarr
2. Click the **Test All Indexers** button
3. Check for any failures (red indicators)
4. Review logs for specific error messages

Common issues:
- **Connection timeout:** Site may be blocked or down
- **Cloudflare challenge:** Need to enable Flaresolverr
- **API rate limit:** Wait a few minutes and try again
- **Invalid response:** Check indexer URL/configuration

---

## Performance Notes

- **YTS:** Very fast, lightweight (ideal for bandwidth-limited connections)
- **EZTV:** Fast, focused on TV (best for Sonarr)
- **TorrentGalaxy:** Medium speed, good variety
- **The Pirate Bay:** Slower due to Cloudflare bypass, but huge library
- **LimeTorrents:** Medium speed

---

## Privacy & VPN Considerations

Currently configured VPN routing:
- **Iceland VPN:** Prowlarr indexer searches (bypasses 1337x blocks in India)
- **Singapore VPN:** Deluge torrent downloads (fast speeds)
- **Host network:** Radarr, Sonarr (use Prowlarr for searches)

All indexer searches go through Iceland VPN automatically once the routing is fixed.

---

## Maintenance

### Checking Indexer Health

Run periodically to check indexer status:
```bash
# Check Prowlarr logs for indexer failures
journalctl -u prowlarr.service --since "1 hour ago" | grep -i "error\|fail"

# Test all indexers via Prowlarr web UI
# Settings → Indexers → Test All Indexers
```

### Updating Indexer URLs

If an indexer changes domain or gets blocked:
1. Check indexer's official status page or subreddit
2. Find new domain/mirror
3. Update in Prowlarr: Settings → Indexers → Click indexer → Update URL → Test → Save

---

## Additional Resources

- **r/Prowlarr** - Reddit community for Prowlarr support
- **Prowlarr Wiki** - Official documentation
- **Prowlarr Discord** - Real-time support

---

## Notes

- This list is current as of January 2026
- Indexer availability changes frequently
- Always verify indexer status before relying on it
- Consider supporting content creators by purchasing content when possible
- Use indexers responsibly and in compliance with local laws
