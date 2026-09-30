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
| Omarchy (Arch) | KOReader desktop, Readest AppImage, or a browser | Same account |

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
> - iPad/MacBook/Omarchy with Tailscale → `http://karmalab:7200` anywhere.
>
> All three URLs share one account and database, so mixing them is fine — two
> devices only need the *same username/password*, not the same URL.

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

## 7. Maintenance

- **Database:** `/var/lib/kosync/Kosync.db` (a few KB–MB). Included in ZFS
  snapshots if you snapshot the NVMe root, or copy the file for a manual backup:
  `sudo cp /var/lib/kosync/Kosync.db /somewhere/backup/`.
- **Update the server:** change `services.kosync.image` in
  `modules/services/kosync.nix`, then `sudo nixos-rebuild switch`. The unit
  pulls the new image on start.
- **Add/remove users:** `sudo kosync-user add <name> <password>` /
  `sudo kosync-user delete <name>`.
- **Raw API:** `sudo kosync-user raw GET /manage/users` (run `kosync-user` with
  no arguments for the full command list).
