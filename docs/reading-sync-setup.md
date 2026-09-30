# Reading Progress Sync (KOSync)

One private server that keeps your place in every book, across every device.

You read on an e-ink reader at home, a pocket reader on the train, an iPad on
the sofa, and a laptop at a desk. KOSync stores, per account and per book, the
furthest reading position you've reached (percentage + exact position). Every
device pulls and pushes through the same account, so you always resume where
you left off — like Netflix "Continue watching", but for books.

## Why KOSync

KOSync is the open protocol KOReader uses. It has become the de-facto standard
for cross-vendor reading sync, and everything you own can speak it:

| Device | Reader / firmware | KOSync support |
|--------|-------------------|----------------|
| Kobo Libra Colour | KOReader | Built-in "Progress sync" plugin |
| XTEINK X4 Pro | CrossPoint (or Crossing) firmware | Built-in "KOReader Sync" |
| Phone (iOS/Android) | Readest (or KOReader on Android) | Built-in KOReader integration |
| iPad Pro | Readest | Built-in KOReader integration |
| MacBook | Readest, or KOReader desktop | Same account |
| Omarchy (Arch) | KOReader desktop, Readest AppImage, or a browser | Same account |

Instead of trusting the public `sync.koreader.rocks` server, karmalab runs your
own. Your reading history stays on your hardware and is included in ZFS
snapshots.

**New here?** `docs/reading-devices-quickstart.md` has the exact
device-by-device click-path (which app, which URL, which setting). This document
is the reference/why.

## Architecture

```
 Kobo Libra Colour  (KOReader)        ─┐
 XTEINK X4 Pro      (CrossPoint)      ─┤     ┌──────────────────────────────┐
 iPad / MacBook     (Readest)         ─┼───▶ │  Caddy  :7200  (LAN + VPN)    │
 Omarchy desktop    (KOReader/Readest)─┘     └──────────────┬───────────────┘
                                              127.0.0.1:17200 │
                                             ┌────────────────▼──────────────┐
                                             │  kosync-dotnet (Docker)       │
                                             │  /var/lib/kosync/Kosync.db    │
                                             └───────────────────────────────┘
```

- **Caddy** listens on `:7200` on all interfaces (LAN + Tailscale) and proxies
  to the container over loopback. Devices only ever need one URL.
- **kosync-dotnet** is an API-compatible KOSync server (LiteDB, no external
  services) chosen over the official image because it speaks plain HTTP and has
  a user-management API.
- **External access** (optional) is a Cloudflare Tunnel hostname pointed at
  `http://localhost:7200` — no port forwarding.

## What was added

| File | Purpose |
|------|---------|
| `modules/services/kosync.nix` | KOSync server: container, data dir, firewall, `kosync-user` helper |
| `modules/services/koinsight.nix` | Reading-statistics dashboard container |
| `modules/services/kosync-backup.nix` | Daily copy of reading state onto the ZFS pool |
| `modules/services/caddy.nix` | Serves `:7200` (KOSync + CORS) and `:3005` (stats) |
| `modules/services/homepage.nix` | "KOSync" and "Reading Stats" entries in the Books group |
| `modules/storage.nix` | `services/kosync` dataset; media-library mounts; auto-snapshot selection |
| `modules/services/calibre-web.nix` | `enableKepubify` for Kobo-native downloads |
| `configuration.nix` | Imports the modules and enables the services |

Default ports: **7200** (sync), **3005** (stats). Data: **`/var/lib/kosync`**
(LiteDB, on ZFS), **`/var/lib/koinsight`** (SQLite, backed up daily).

## 1. Deploy

On karmalab:

```bash
cd ~/karmalab
git pull
sudo nixos-rebuild switch --flake /etc/nixos#karmalab

# Create the admin password file (once, outside git):
printf 'ADMIN_PASSWORD=%s\n' "$(openssl rand -base64 24)" \
  | sudo tee /etc/nixos/secrets/kosync.env
sudo chmod 600 /etc/nixos/secrets/kosync.env
```

> Create the secret **before** the switch (or immediately after — the container
> restarts every 10s until the env file exists). `kosync-user` reads the same
> file, so it stays the single source of truth.

Verify:

```bash
systemctl status docker-kosync
curl -s http://127.0.0.1:17200/healthcheck      # {"state":"OK"}
curl -s http://127.0.0.1:7200/healthcheck       # through Caddy
```

## 2. Create your reading account

Use the helper — it does the md5 juggling the protocol needs (see the note
below):

```bash
sudo kosync-user add somesh 'your-reading-password'
sudo kosync-user list
```

Use the **same username + password** on every device. (Optional: add a second
account for a family member.)

> **Why the helper?** KOSync devices authenticate by sending
> `md5(password)` in an `x-auth-key` header. The management API hashes the
> plaintext you give it, so `kosync-user add` with your normal password produces
> exactly the value devices expect. Always pass the **plain text** password to
> the helper — never a pre-computed hash.

## 3. Set up each device

Use the **same account** everywhere. Pick the URL that matches each device:

- **At home (LAN):** `http://192.168.68.59:7200`
- **Anywhere (Tailscale):** `http://karmalab:7200` or `http://100.80.102.100:7200`
- **Public HTTPS (works for every reader):** `https://kosync.somesh.dev`

> **Which URL should I use?** The e-ink readers can't join Tailscale, so:
> - On home Wi-Fi → the **LAN** URL (fastest, no internet dependency).
> - Away from home → **`https://kosync.somesh.dev`**.
> - Phone / iPad / MacBook / Omarchy with Tailscale → `http://karmalab:7200`.
>
> All three URLs share one account and database, so mixing them is fine — two
> devices only need the *same username/password*, not the same URL. For phones
> the public URL is the simplest choice since it works on mobile data and any
> Wi-Fi.

### 3.1 Kobo Libra Colour (KOReader)

1. Install KOReader via the **One-Click Install Package** (Kfmon + NickelMenu +
   KOReader). The current release supports Libra Colour.
2. Open a book → menu → **Plugins → Progress sync**.
3. Tap **Custom sync server**, enter the server URL, then **Register / Login**
   with your username and password.
4. Set **Document matching = Binary** (a.k.a. file content). *This matters* —
   filename matching will silently fail to line up books between KOReader and
   other apps.
5. Optional: enable **Auto sync**.

### 3.2 XTEINK X4 Pro (CrossPoint)

1. Flash **CrossPoint** (`https://crosspointreader.com/#flash-tools`), select
   "Xteink X4Pro" and an official release.
2. Join Wi-Fi (STA mode), then open the device web UI from a browser.
3. Under **KOReader Sync** set the server URL, username and password. Or set it
   on-device at **Settings → System → KOReader Sync**.
4. Set **Document matching = Binary**.
5. Tap **Authenticate**, then open a book and use **Sync Progress**.

### 3.3 iPad Pro / MacBook (Readest)

1. Install **Readest** (App Store / download).
2. **Settings → Integrations → KOSync (KOReader sync)**.
3. Enter the server URL, username and password.
4. Set **Checksum method = File Content** (same as "Binary" above).
5. Progress syncs both ways. Use **Sync now** to force a sync.

> Readest also syncs highlights/notes through *Readest Cloud*; the KOSync path
> carries reading position.

### 3.4 Omarchy desktop

Any of these work, all using the same account:

- **KOReader desktop** — install `koreader`, then Plugins → Progress sync →
  Custom sync server. Set Document matching to **Binary**.
- **Readest** — AppImage from the Readest releases; set it up as in 3.3.
- **Browser** — open Calibre-Web (`http://192.168.68.59:8083`) to read and see
  the current position, or the Readest web app.

### 3.5 Phone (iOS *and* Android)

The phone is the easiest device to add, and it can do **both** halves — browse
your library *and* resume at the right page.

**Readest (recommended, iOS + Android):**

1. Install **Readest** from the App Store / Play Store.
2. **Settings → Integrations → KOSync** → server
   `https://kosync.somesh.dev`, username `somesh`, your reading password,
   checksum **File Content**.
3. Get books onto the phone — either:
   - **OPDS:** library → **Import Books → Online Library**, add catalog
     `https://books.somesh.dev/opds` with your Calibre-Web username/password
     (`somesh` / `Index.calibre1`). Browse and download straight into Readest.
   - **Web Browser import:** **Import Books → From Web Browser**, save
     `https://books.somesh.dev` and browse it in-app.
   - **WebDAV** (OpenCloud) or manual file import.
4. Add the Readest **widget** to your home screen — it shows recent books with
   progress, so resuming is one tap.

> On iOS, reaching a *LAN* OPDS URL triggers a Local Network permission prompt.
> Using the public `https://books.somesh.dev` avoids that entirely.

**KOReader on Android** — also works, same account: install KOReader, open a
book → **Plugins → Progress sync → Custom sync server** →
`https://kosync.somesh.dev`, then set **Document matching = Binary**.

**Audiobooks on the phone:** install the **Audiobookshelf** app and point it at
`https://abs.somesh.dev`. Audiobook position syncs across your phone and other
devices through Audiobookshelf (separate from KOSync, which is ebook-only).

**Why the phone is worth setting up first:** it shares the *exact same account*
as the Kobo and XTEINK, so one book read on the phone resumes on the e-reader —
and it needs no flashing, rooting, or USB sideloading.

## 4. Remote access (already configured)

`kosync.somesh.dev` is live and reachable from anywhere:

- **Cloudflare Tunnel** — the existing `karmalab` tunnel (id
  `838930b7-5642-453e-9ac8-dbb4e1ff41e4`) has an ingress rule
  `kosync.somesh.dev → http://localhost:7200`, plus a proxied CNAME
  `kosync.somesh.dev → 838930b7-….cfargotunnel.com`. Managed via the `cf` CLI
  or the Zero Trust dashboard.
- **Tailscale** — `http://karmalab:7200` works from any tailnet device.
- No port forwarding; `cloudflared` connects outbound from karmalab.

To change or remove the public hostname later (using the `cf` CLI, signed in as
`somesh.kar@gmail.com`):

```bash
export CLOUDFLARE_ACCOUNT_ID=ac6767857b4428415d882181a3310a1c
TUN=838930b7-5642-453e-9ac8-dbb4e1ff41e4

# inspect / edit ingress (note: `update` REPLACES the whole list)
cf tunnels config get "$TUN"
cf tunnels config update "$TUN" --body @new-config.json --dry-run

# remove just the DNS record
cf dns records list --zone somesh.dev
cf dns records delete <record-id> --zone somesh.dev
```

> **Caution:** `cf tunnels config update` replaces the *entire* ingress list.
> Always `get` the current config, edit it, and `--dry-run` before applying —
> otherwise you can knock out the other 12 hostnames on that tunnel.

**Security note:** `kosync.somesh.dev` is publicly reachable, and
`REGISTRATION_DISABLED=true` prevents strangers creating accounts. Consider also
putting it behind a **Cloudflare Access** policy (email OTP) if you want to
require auth at the edge in addition to the KOSync credentials. If you do, note
that the e-ink readers can't complete a browser login — so an Access policy
would break them and you should use the LAN/Tailscale URL on those instead.

**Browser CORS:** Readest's *web* app (`web.readest.com`) talks to KOSync from
the browser, which requires CORS headers. Neither the official nor the
self-hosted KOSync server sends them, so Caddy adds them on `:7200` for an
allow-list of reader origins, and answers the `OPTIONS` preflight that the app
rejects with 405. Native apps (KOReader, Readest iOS/macOS/desktop) are
unaffected — CORS is a browser-only concept. To permit another browser reader,
add its origin to the `@corsOrigin` regexp in `modules/services/caddy.nix`.

## 4a. Reading statistics dashboard (KoInsight)

KoInsight charts your KOReader reading time, a calendar heatmap, per-book
progress and streaks:

```
LAN:       http://192.168.68.59:3005
Tailscale: http://karmalab:3005
```

Feed it data one of two ways:

- **Plugin (recommended):** in KOReader open **Tools → KoInsight**, configure
  the server URL, then **Sync**.
- **Manual:** copy `statistics.sqlite` from the device's `koreader/settings/`
  folder and use **Upload Statistics DB**.

Covers are not extracted automatically; add them once per book via the
**Cover Selector** tab.

> KoInsight *can* also act as a KOSync server, but this setup deliberately does
> not use that. `kosync-dotnet` (step 3) stays the single source of truth for
> reading *position*; two servers writing the same document hashes would fight
> over which is furthest.

## 4b. Reading on the web (MacBook, Omarchy, anywhere)

Two independent paths, both worth having:

1. **Readest web** — `https://web.readest.com`. Add KOSync under
   *Settings → Integrations → KOSync* with server `https://kosync.somesh.dev`,
   your username/password, and checksum **File Content**. Progress syncs with
   your Kobo/XTEINK. (This is what the CORS config above enables.)
2. **Calibre-Web in-browser reader** — `http://192.168.68.59:8083` (or
   `https://books.somesh.dev`) has a built-in EPUB reader and a **Kobo sync**
   feature. Log in as `somesh`.

Calibre-Web's own reader does **not** talk to KOSync, so its position is
separate — treat Readest-web as the true "read anywhere, resume anywhere"
surface, and Calibre-Web as the library/browse/download surface.

## 4d. Getting books onto each device (library delivery)

The library is **159 books / 128 authors** in
`/data/media/ebooks/calibre-library`, served by Calibre-Web. Calibre-Web's OPDS
feed is verified working at `https://books.somesh.dev/opds` (login required).

**Every device should pull from this same source** — that is what makes the
KOSync document hashes line up.

| Device | Method | URL / steps |
|--------|--------|-------------|
| Phone (Readest) | OPDS | Import Books → Online Library → `https://books.somesh.dev/opds` + Calibre-Web login |
| iPad / MacBook (Readest, KOReader) | OPDS | same catalog URL |
| Omarchy (KOReader/Readest) | OPDS | same catalog URL |
| XTEINK (CrossPoint) | OPDS | saved server (up to 8) in the OPDS browser |
| Kobo (KOReader) | OPDS | file browser → OPDS catalog → add `https://books.somesh.dev/opds` |
| Kobo (native) | Kobo sync | `https://books.somesh.dev/<auth_token>` — token from *your* Kobo-sync settings page |

Credentials for OPDS are your **Calibre-Web** login (`somesh` + the password you
set in Calibre-Web, which is separate from the KOSync reading password and the
sudo password). If you don't know it, reset it in Calibre-Web →
*Admin → Users → somesh*, or via a one-off shell.

> **Kobo native sync caveat:** Kobo's built-in sync carries **library contents**
> (so books appear on the device automatically) but **not reading position**.
> Position comes from KOReader + KOSync. So on the Kobo you get: books delivered
> by Calibre-Web, position synced by KOSync. Best of both.
>
> Also note Calibre-Web's OPDS serves *EPUB*; Kobo's native reader prefers KEPUB,
> which is why `enableKepubify = true` is set — Calibre-Web will serve the KEPUB
> variant to the device.

## 4c. Which device does what (and where books come from)

| Surface | Read here? | Syncs position? | Gets books from |
|---------|-----------|-----------------|-----------------|
| Kobo Libra Colour (KOReader) | ✅ e-ink | ✅ KOSync | OPDS from Calibre-Web |
| XTEINK X4 Pro (CrossPoint) | ✅ e-ink | ✅ KOSync | OPDS from Calibre-Web |
| Phone (Readest) | ✅ | ✅ KOSync | OPDS + WebDAV |
| iPad Pro (Readest) | ✅ | ✅ KOSync | OPDS + WebDAV |
| Readest web / MacBook | ✅ | ✅ KOSync | OPDS + WebDAV |
| Calibre-Web browser | ✅ | ❌ own reader only | library itself |
| KoInsight | ❌ stats only | n/a | uploads stats |
| Audiobookshelf app | ✅ audio | ✅ ABS (audio only) | audiobooks library |

**The one rule that makes it all work:** every book should come from the *same*
source (`/data/media/ebooks/calibre-library`) so the file bytes — and therefore
the KOSync document hash — match on every device. If two devices hold
differently-modified copies of the same EPUB, KOSync sees two different books.

## 5. Verify sync

Pick one book that exists on two devices:

1. Read a few pages on device A, trigger **Sync Progress**.
2. On device B, open the same book and sync. It should offer to jump to the new
   position.
3. Confirm the server saw it:

```bash
sudo docker exec kosync ls -la /app/data            # Kosync.db is present
sudo journalctl -u docker-kosync -f                 # watch live
sudo kosync-user documents somesh                   # per-user synced docs
```

## 6. Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| `User could not be found` after creating a user | The user was created with a pre-hashed value. Re-add with `sudo kosync-user add <name> <plain-password>` (the helper hashes it for you). |
| Books never line up between two apps | **Document matching disagrees.** Set KOReader/CrossPoint to *Binary* and Readest to *File Content* on every device. |
| `Document hash [...] not found for user [...]` on first sync | The server has no record yet. Push progress from one device first (the plugin does this when you tap Sync); afterwards it works normally. |
| Container restarts every 10s | Missing `/etc/nixos/secrets/kosync.env`. Create it (see step 1). |
| Port 7200 unreachable from the LAN | Check `systemctl status caddy docker-kosync`; the module opens 7200 in the firewall. |
| `/healthcheck` returns OK but the device can't log in | Verify the URL has no trailing path and starts with `http://` (LAN) or `https://` (tunnel), and that the username/password match exactly. |
| Changed the password on one device only | Run `sudo kosync-user passwd <name> <new-password>`, then update every device. |
| Phone/app can't reach an OPDS URL with a `192.168.x.x` address | iOS blocks LAN addresses without the Local Network permission. Use `https://books.somesh.dev/opds` instead, or grant Settings → Privacy & Security → Local Network → Readest. |
| Readest web shows a CORS error | Only allow-listed origins send CORS headers. Add the origin to the `@corsOrigin` regexp in `modules/services/caddy.nix`. |
| Phone syncs position but the book won't download | OPDS needs a Calibre-Web login (`somesh` / `Index.calibre1`, *not* the KOSync password). |
| Two devices never line up on the same book | They hold *differently-modified* copies, so the file hashes differ. Re-download both from the same OPDS/library source. |
| KoInsight shows no data | It reads KOReader's `statistics.sqlite`, which nothing uploads automatically — use Tools → KoInsight → Sync, or Upload Statistics DB. |

## 7. Backup & maintenance

Reading state is protected three ways:

1. **KOSync DB on ZFS.** `/var/lib/kosync` is the `storagepool/services/kosync`
   dataset and carries `com.sun:auto-snapshot=true`, so it is captured by the
   ZFS auto-snapshot timers (15-min/hourly/daily/weekly/monthly).
2. **Nightly copy on the pool.** `kosync-backup.timer` copies
   `/var/lib/kosync` and `/var/lib/koinsight` to
   `/data/media/ebooks/.backups/<utc-timestamp>/` — also on ZFS, so those copies
   are themselves snapshotted. Keeps the newest 14.
3. **Manual (optional):** `sudo cp /var/lib/kosync/Kosync.db /somewhere/backup/`.

Verify / run on demand:

```bash
sudo systemctl start kosync-backup.service    # run now
sudo systemctl list-timers kosync-backup.timer
sudo ls /data/media/ebooks/.backups/

sudo zfs list -t snapshot | grep services/kosync
```

Restore:

```bash
sudo systemctl stop docker-kosync
sudo cp /data/media/ebooks/.backups/<stamp>/kosync/Kosync.db /var/lib/kosync/Kosync.db
sudo chown 1000:100 /var/lib/kosync/Kosync.db
sudo systemctl start docker-kosync
```

Other maintenance:

- **Update the server:** change `services.kosync.image` in
  `modules/services/kosync.nix`, then `sudo nixos-rebuild switch`. The unit
  pulls the new image on start.
- **Add/remove users:** `sudo kosync-user add <name> <password>` /
  `sudo kosync-user delete <name>`.
- **Raw API:** `sudo kosync-user raw GET /manage/users` (run `kosync-user` with
  no arguments for the full command list).

> **Caution:** never run `caddy validate` as root. Caddy's config creates log
> files under `/var/log/caddy` owned by its own user; a root-owned log file
> makes Caddy fail to start with `permission denied`. Validate via
> `nixos-rebuild build` instead, or delete the stray log file afterwards.
