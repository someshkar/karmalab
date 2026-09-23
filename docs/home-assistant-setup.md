# Home Assistant Setup

Home Assistant runs **natively** on karmalab (no Docker Supervisor) via
`modules/services/home-assistant.nix`, pinned to nixpkgs-unstable so it tracks
the current release.

## Access

| Where | URL |
|---|---|
| LAN | http://192.168.68.59:8123 |
| Tailscale | http://karmalab:8123 |
| Dashboard | Homepage → Smart Home → Home Assistant |
| Public | `https://home.somesh.dev` (Cloudflare Tunnel — Phase 2, not yet enabled) |

Firewall currently opens 8123 on the LAN and on `tailscale0` only.

## Data & operations

- All state lives in `/var/lib/hass` (config, `homeassistant.db`, `.storage`).
- This directory is on the **root ext4 filesystem, not the ZFS pool**, so it is
  **not** covered by ZFS snapshots. Back it up manually if you care about it.
- `configuration.yaml` is copied from the Nix module on every service start
  (`configWritable = true`). **Edit `modules/services/home-assistant.nix`, not
  the YAML**, or your change will be overwritten on restart.
- UI-managed state (dashboards, user accounts, integration entries) lives in
  `/var/lib/hass/.storage` and is untouched by the module.

```bash
# status / logs
systemctl status home-assistant
journalctl -u home-assistant -f
```

## Initial setup

1. Open http://192.168.68.59:8123 and complete the onboarding wizard
   (create the owner account, set your location, finish the tour).
2. Add integrations from **Settings → Devices & services → Add integration**.

## Zebronics ZEB-SP110 smart plug (Tuya, local control)

The plug is a Tuya-protocol device (MAC vendor `d0:82:eb` = Tuya Smart Inc.;
TCP/6668 open). It is controlled through the **Tuya Local** custom component,
which talks to the device directly on your LAN — no cloud round-trip.

The component is provided by nixpkgs as
`home-assistant-custom-components.tuya_local` and symlinked into
`/var/lib/hass/custom_components/` automatically.

### 1. Get the device's local key

Tuya Local needs the device **ID** and **local key**. The key is generated at
pairing time and does **not** come out of the app UI; pick one of:

**Option A — cloud-assisted wizard (easiest).**
The integration's setup wizard can fetch the key for you, but that requires a
free Tuya IoT developer account:

1. Create an account at https://iot.tuya.com and create a Cloud project
   (data centre: **India**). Note the **Access ID** / **Access Secret**.
2. In the project, link your app account using the **User Code** from the
   ZEB-Home (or Tuya Smart / Smart Life) app:
   *Me → ⚙️ → Account and Security → User Code*.
3. In HA: **Settings → Devices & services → Add integration → Tuya Local**,
   choose the cloud-assisted path, select the plug, and it fills in the
   device ID / local key / IP.

> Note: Tuya now limits IoT developer access to some APIs to a trial period,
> so do this while the trial is active.

**Option B — extract the key locally (no Tuya account).**
Use a key-extraction tool such as `tinytuya`'s wizard (`python -m tinytuya
wizard`) or the standard `tuya-cli`/`tuya-local` key extraction flow. This
reads the key from the app's network traffic during pairing.

> ⚠️ Re-pairing the device in the app **rotates the local key**. If control
> stops working, re-extract the key.

### 2. Add the device in Home Assistant

1. **Settings → Devices & services → Add integration → Tuya Local**.
2. Enter host `192.168.68.50`, the device ID and local key.
3. When prompted for a device type, choose the generic **smart plug / switch**
   profile that matches the entities your plug exposes (usually a single
   on/off switch).
4. Finish the wizard and give it a name (e.g. "Zebronics Plug").

### Troubleshooting

- **Device not discovered by a broadcast scan** is normal for many Tuya
  firmwares — add it manually by IP.
- Only **one** local connection is allowed to many Tuya devices. Close the
  ZEB-Home app and make sure `localtuya` is not also pointed at the same device.
- Protocol mismatch → try a different Tuya protocol version (3.3, 3.4, …) in
  the device's settings.

## HomeMate IR Control Hub (planned)

The HomeMate Wi-Fi IR Control Hub (Amazon `B07N2WFGKZ`) is also a Tuya device,
but Home Assistant's official Tuya integration **cannot control IR/remote
devices**. Two viable paths, to be done later:

- **A.** `localtuya_rc` community integration (local, but its author no longer
  maintains it), or
- **B. recommended:** flash the Tuya module with **ESPHome** and use the
  `remote_transmitter` component — fast, reliable, cloud-free. nixpkgs already
  ships `home-assistant-custom-components.smartir` for ready-made IR codes.

## Remote access for others (planned)

For family access, create a **non-admin HA user** for each person
(*Settings → People → Users → Add user*), then grant access either:

- **Tailscale** (most private): share the `karmalab` node with them and have
  them sign in at http://karmalab:8123, or
- **Cloudflare Tunnel**: add a `home.somesh.dev` hostname, then set
  `http.trusted_proxies` / `http.use_x_forwarded_for` in the module and enable
  MFA before exposing publicly.

## Rollback

- Service/config: `sudo nixos-rebuild switch --rollback` (previous generation).
- Data: restore `/var/lib/hass` from backup (see `~/backups/`).
