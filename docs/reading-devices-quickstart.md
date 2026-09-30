# Reading Setup — Device-by-Device Steps

Follow these in order. **Start with the iPad** (lowest friction, no flashing) and
prove the sync works before touching the Kobo or XTEINK.

## What you need (same everywhere)

| Thing | Value |
|-------|-------|
| KOSync server (home Wi-Fi) | `http://192.168.68.59:7200` |
| KOSync server (away / mobile data) | `https://kosync.somesh.dev` |
| KOSync server (Tailscale) | `http://karmalab:7200` |
| **KOSync username** | `somesh` |
| **KOSync password** | `Index.kosync1` |
| **Document matching** | **Binary** (KOReader/CrossPoint) = **File Content** (Readest) |
| OPDS catalog (books) | `https://books.somesh.dev/opds` |
| OPDS login | Calibre-Web user `somesh` + *your Calibre-Web password* |
| Reading stats dashboard | `http://192.168.68.59:3005` |

> **The one setting that breaks everything:** document matching. If KOReader says
> *Binary* and Readest says *Filename* (or vice-versa), sync will look like it
> works but never line up. Set it explicitly on every device.

Right now the library holds **one book — _The Selfish Gene_ (Richard Dawkins)** —
so it's the perfect single book to test with.

---

## 1. iPad Pro (do this first)

1. Install **Readest** from the App Store.
2. **Settings → Integrations → KOSync** (labelled "KOReader sync"):
   - Server URL: `https://kosync.somesh.dev`
   - Username: `somesh`
   - Password: `Index.kosync1`
   - Checksum method: **File Content**
3. Get the book onto the iPad:
   - **Library → + (Import Books) → Online Library**
   - Add catalog: `https://books.somesh.dev/opds`
   - Username `somesh`, password = **your Calibre-Web password**
   - Browse → download *The Selfish Gene*
4. Open the book, read a few pages.
5. **Test:** open the same book, sync (`Sync now`). Repeat on the phone later —
   it should offer to jump to where you stopped.

## 2. Phone (iOS or Android)

Same app, same steps as the iPad — install **Readest**, then Settings →
Integrations → KOSync with `https://kosync.somesh.dev` / `somesh` /
`Index.kosync1` / **File Content**, and add the same OPDS catalog.

- **Android alternative:** install **KOReader** from F-Droid/Play. Open a book →
  menu → **Plugins → Progress sync → Custom sync server** →
  `https://kosync.somesh.dev`, Register/Login, then set **Document matching =
  Binary**.
- **Audiobooks:** install the **Audiobookshelf** app, server
  `https://abs.somesh.dev` (separate account from KOSync).

Add the **Readest home-screen widget** — it shows recent books with progress, so
resuming is one tap. This is the "pick up and read" experience.

## 3. MacBook

Two options; **Readest** gives sync, so use that:

1. Install **Readest** (macOS build).
2. **Settings → Integrations → KOSync** → `https://kosync.somesh.dev`, `somesh`,
   `Index.kosync1`, **File Content**.
3. Import the book via OPDS (same catalog as above) or drag the EPUB in.
4. Want to read in a browser instead? `https://web.readest.com` works with the
   same KOSync settings (CORS is already configured for it).

**KOReader desktop** also works if you prefer: Plugins → Progress sync → Custom
sync server → **Binary**.

## 4. Kobo Libra Colour

This one needs KOReader installed (there's no other way to run KOSync on a Kobo).

1. **Install KOReader** using the *One-Click Install Package* from the MobileRead
   forum (installs Kfmon + NickelMenu + KOReader). Follow its instructions to
   copy the files to the Kobo over USB.
2. Eject, unplug, and let the Kobo restart. You'll get a KOReader entry in
   NickelMenu.
3. Launch **KOReader** → open any book (the progress plugin only appears while
   reading a book) → menu → **Plugins → Progress sync**.
4. Tap **Custom sync server** → enter `https://kosync.somesh.dev`
   (on home Wi-Fi you can use `http://192.168.68.59:7200`).
5. Tap **Register / Login** → `somesh` / `Index.kosync1`.
6. Set **Document matching = Binary**.
7. Get the book: KOReader's file browser → menu → **OPDS catalog** → add
   `https://books.somesh.dev/opds` (username `somesh`, password = Calibre-Web
   password) → download *The Selfish Gene*.
8. Open it, read, then **Sync progress**.

> **Note:** Kobo's *native* sync (Niagara) can deliver books automatically but
> does **not** carry reading position — KOReader + KOSync is what gives you
> "resume where I left off".

## 5. XTEINK X4 Pro

1. Flash **CrossPoint** firmware: connect USB-C, go to
   `https://crosspointreader.com/#flash-tools`, pick **Xteink X4Pro**, choose an
   official release, and flash. *(If it was bought from AliExpress it may be
   USB-locked — use the Xteink Unlocker link on that page first. Direct from
   xteink.com units are not locked.)*
2. Join your Wi-Fi (STA mode).
3. Easiest: open the device's **web settings UI** in a browser, go to
   **KOReader Sync**, and enter:
   - Server: `https://kosync.somesh.dev`
   - Username `somesh`, Password `Index.kosync1`
   - Matching: **binary**
   *(Or set it on-device: Settings → System → KOReader Sync.)*
4. Save, then tap **Authenticate**.
5. Add the OPDS server (up to 8 saved) pointing at
   `https://books.somesh.dev/opds` and download the book.
6. Open the book → **Sync Progress**.

## 6. Omarchy desktop (where you are now)

- **Readest** AppImage → same KOSync settings, or
- **KOReader desktop** → Progress sync → Custom sync server → **Binary**, or
- **Browser** → `https://web.readest.com` or `http://192.168.68.59:8083`.

---

## Reading statistics (after any device has read something)

KOReader keeps local reading time; KoInsight charts it:

1. On a KOReader device: **Tools → KoInsight** → set server URL
   `https://kosync.somesh.dev` *(or `http://192.168.68.59:3005`)* → **Sync**.
2. Open `http://192.168.68.59:3005` to see the dashboard.

Covers aren't auto-extracted — add them once via the **Cover Selector** tab.

---

## The 2-minute end-to-end test

1. On the **iPad**, open *The Selfish Gene* and read a few pages. Sync.
2. On the **phone** (or any KOReader device), open the same book and sync.
3. It should offer to jump to the new position. ✅ You're done — every device
   from here is the same pattern.

If it doesn't line up, the answer is almost always **document matching**
(must be Binary / File Content everywhere), or the two devices hold
*different copies* of the file — always download from the OPDS catalog so the
bytes are identical.

## Troubleshooting quick reference

| Symptom | Fix |
|---------|-----|
| "User could not be found" on device | Password is `Index.kosync1`. If you changed it, update every device. |
| Syncs but position never matches | Document matching differs between devices → set Binary / File Content everywhere. |
| OPDS download fails / 401 | Use your **Calibre-Web** password (not the KOSync one). Reset it in Calibre-Web → Admin → Users → somesh. |
| iOS can't reach a `192.168.x.x` OPDS URL | iOS Local Network permission. Use `https://books.somesh.dev/opds` instead. |
| CrossPoint can't authenticate | Set matching to **binary** and re-check the URL has no trailing slash. |
