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
| iPad Pro | Readest | Built-in KOReader integration |
| MacBook | Readest, or KOReader desktop | Same account |
| Omarchy (Arch) | KOReader desktop, Readest AppImage, or any device's browser | Same account |

Instead of trusting the public `sync.koreader.rocks` server, karmalab runs your
own. Your reading history stays on your hardware and is included in ZFS
snapshots.

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
| `modules/services/kosync.nix` | Container, data dir, firewall, `kosync-user` helper |
| `modules/services/caddy.nix` | `http://:7200` → container loopback |
| `modules/services/homepage.nix` | "KOSync" entry in the Books group |
| `configuration.nix` | Imports the module and enables `services.kosync` |

Default port: **7200**. Data: **`/var/lib/kosync`** (LiteDB).

## 1. Deploy

On karmalab:

```bash
cd ~/karmalab
git pull                 # or: git checkout main && git pull   (after merge)
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

The KOSync protocol sends `md5(password)` as the auth key, and the server
stores `md5(what you send)`. So the account must be created with
`md5(password)` as its value. The helper does this for you:

```bash
sudo kosync-user add somesh 'your-reading-password'
sudo kosync-user list
```

Use the **same username + password** on every device. (Optional: add a second
account for a family member.)

## 3. Set up each device

Use the **same server URL** everywhere:

- **At home (LAN):** `http://192.168.68.59:7200`
- **Anywhere (Tailscale):** `http://karmalab:7200` or `http://<tailnet-ip>:7200`
- **Public (if you add a tunnel hostname):** `https://kosync.somesh.dev`

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
  current position, or the Readest web app.

## 4. Optional: reach it from anywhere

The server is already reachable on the LAN and over Tailscale. For browser-only
or non-Tailscale devices, add a Cloudflare Tunnel hostname in the Zero Trust
dashboard (e.g. `kosync.somesh.dev` → `http://localhost:7200`) — the same pattern
used for `books.somesh.dev`. No firewall changes are required.

## 5. Verify sync

Pick one book that exists on two devices:

1. Read a few pages on device A, trigger **Sync Progress**.
2. On device B, open the same book and sync. It should offer to jump to the new
   position.
3. Confirm the server saw it:

```bash
sudo docker exec kosync sh -c 'ls -la /app/data'   # Kosync.db is growing
# or watch live:
sudo journalctl -u docker-kosync -f
```

## 6. Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| `User could not be found` right after creating a user | The account was created with the plain password instead of `md5(password)`. Delete and re-add with `sudo kosync-user add`. |
| Books never line up between two apps | **Document matching disagrees.** Set KOReader/CrossPoint to *Binary* and Readest to *File Content* on every device. |
| `Document hash [...] not found for user [...]` on first sync | The server has no record yet. Push progress from one device first (or `PUT /syncs/progress` once); afterwards it works normally. |
| Container restarts every 10s | Missing `/etc/nixos/secrets/kosync.env`. Create it (see step 1). |
| Port 7200 unreachable from the LAN | Check `systemctl status caddy docker-kosync` and that `networking.firewall` includes 7200 (it does via the module). |
| `curl /healthcheck` returns OK but the device can't log in | Verify the URL has no trailing path and starts with `http://` (LAN) or `https://` (tunnel). |

## 7. Maintenance

- **Database:** `/var/lib/kosync/Kosync.db` (a few KB–MB). Included in ZFS
  snapshots if you snapshot the NVMe root, or copy the file for a manual backup:
  `sudo cp /var/lib/kosync/Kosync.db /somewhere/backup/`.
- **Update the server:** change `services.kosync.image` in
  `modules/services/kosync.nix`, then `sudo nixos-rebuild switch`. The unit
  pulls the new image on start.
- **Add/remove users:** `sudo kosync-user add <name> <password>` /
  `sudo kosync-user delete <name>`.
- **Raw API:** `sudo kosync-user raw GET /manage/users` (see
  `kosync-user` help for the full set).
