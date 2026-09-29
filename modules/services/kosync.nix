# modules/services/kosync.nix
# ============================================================================
# KOSYNC - SELF-HOSTED READING PROGRESS SYNC SERVER
# ============================================================================
#
# KOSync is the de-facto open protocol for cross-device ebook reading
# progress sync. It stores, per user and per document hash, the furthest
# reading position (percentage + CFI/xpointer) and last known device. Every
# device that speaks the protocol pulls/pushes through the same account, so
# you can start a book on one device and resume on another.
#
# Protocol clients (all interoperate through this one server):
#   - KOReader "Progress sync" plugin (Kobo, Kindle, PocketBook, Android, Linux)
#   - CrossPoint / Crossing firmware (XTEINK X3 / X4 / X4 Pro)
#   - Readest (iOS/iPadOS, macOS, Windows, Linux, Android, Web) KOReader plugin
#   - BookOrbit, Calibre-Web-Automated, Kavita and others also speak it
#
# Why kosync-dotnet?
#   The official koreader/kosync image ships a self-signed HTTPS certificate
#   and has no user-management API. kosync-dotnet speaks the exact same
#   protocol over plain HTTP (handy behind a reverse proxy / tunnel), stores
#   everything in a single LiteDB file, and adds a small management API and a
#   registration toggle. It is API-compatible, so all clients above work.
#
# Architecture:
#
#   Kobo (KOReader) ─┐
#   XTEINK (CrossPoint) ─┤      ┌────────────────────────────┐
#   iPad/MacBook (Readest) ─┼──▶│ Caddy :7200  (LAN URL)      │
#   Omarchy/desktop (KOReader/Readest) ─┘  └──▶ 127.0.0.1:17200 │
#                                          │  kosync-dotnet container │
#                                          │  /var/lib/kosync (LiteDB)│
#                                          └────────────────────────────┘
#
# Networking:
#   - LAN:        http://192.168.68.59:7200          (Caddy -> container)
#   - Tailscale:  http://karmalab:7200 or http://<tailnet-ip>:7200
#   - Internet:   point any Cloudflare Tunnel hostname (e.g. kosync.somesh.dev)
#                 at http://localhost:7200. No public port forwarding needed.
#
# Storage:
#   - Database: /var/lib/kosync/Kosync.db (single LiteDB file, tiny)
#   - Backups:  covered by ZFS snapshots of the NVMe root, or copy the file
#
# Setup:
#   1. Create the admin env file (outside git):
#        printf 'ADMIN_PASSWORD=%s\n' "$(openssl rand -base64 24)" \
#          | sudo tee /etc/nixos/secrets/kosync.env
#        sudo chmod 600 /etc/nixos/secrets/kosync.env
#   2. Deploy the NixOS configuration.
#   3. Create your reading account:
#        sudo kosync-user add somesh '<your-reading-password>'
#   4. Enter the server URL + those credentials on every device.
#
# IMPORTANT (KOSync password quirk):
#   The KOSync protocol transmits md5(password) as the x-auth-key header. The
#   management API used by `kosync-user add` hashes the plaintext it is given,
#   so the stored value is md5(password) — exactly what devices send. Just pass
#   your normal password on the command line; do not pre-hash it.
#
# ============================================================================

{ config, lib, pkgs, ... }:

let
  cfg = config.services.kosync;
in
{
  options.services.kosync = {
    enable = lib.mkEnableOption "self-hosted KOSync reading-progress sync server";

    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/jberlyn/kosync-dotnet:latest";
      description = "Container image for the KOSync server.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 7200;
      description = ''
        Public port that devices connect to. Served by Caddy, which proxies to
        the container over loopback.
      '';
    };

    internalPort = lib.mkOption {
      type = lib.types.port;
      default = 17200;
      description = "Loopback port the container listens on.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/kosync";
      description = "Directory holding the KOSync LiteDB database.";
    };

    adminEnvFile = lib.mkOption {
      type = lib.types.path;
      default = "/etc/nixos/secrets/kosync.env";
      description = ''
        Environment file containing the admin password, in the form
        `ADMIN_PASSWORD=...`. Read by the container and by `kosync-user`.
      '';
    };

    registrationDisabled = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Disable self-registration. Keep true for a private server: create
        accounts with `sudo kosync-user add <name> <password>` instead.
      '';
    };

    trustedProxies = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1, ::1, 172.16.0.0/12";
      description = "Trusted reverse-proxy addresses for X-Forwarded-For logging.";
    };
  };

  config = lib.mkIf cfg.enable {
    # ------------------------------------------------------------------------
    # CONTAINER
    # ------------------------------------------------------------------------
    systemd.services.docker-kosync = {
      description = "KOSync - KOReader/Readest reading progress sync server";

      after = [ "docker.service" "network-online.target" ];
      requires = [ "docker.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "10s";
        TimeoutStartSec = "0";
        TimeoutStopSec = "60";
      };

      preStart = ''
        ${pkgs.docker_29}/bin/docker pull ${cfg.image} || true
        ${pkgs.docker_29}/bin/docker rm -f kosync 2>/dev/null || true
      '';

      # Plain HTTP on loopback; Caddy (or a tunnel) terminates for devices.
      script = ''
        ${pkgs.docker_29}/bin/docker run \
          --name=kosync \
          --rm \
          --env-file ${cfg.adminEnvFile} \
          -p 127.0.0.1:${toString cfg.internalPort}:8080 \
          -v ${cfg.dataDir}:/app/data \
          -e ASPNETCORE_HTTP_PORTS=8080 \
          -e REGISTRATION_DISABLED=${if cfg.registrationDisabled then "true" else "false"} \
          -e TRUSTED_PROXIES="${cfg.trustedProxies}" \
          --user 1000:1000 \
          ${cfg.image}
      '';

      preStop = ''
        ${pkgs.docker_29}/bin/docker stop kosync 2>/dev/null || true
      '';
      postStop = ''
        ${pkgs.docker_29}/bin/docker rm -f kosync 2>/dev/null || true
      '';
    };

    # Database directory, owned by somesh (uid 1000) for easy inspection.
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 1000 100 -"
    ];

    # ------------------------------------------------------------------------
    # USER MANAGEMENT HELPER
    # ------------------------------------------------------------------------
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "kosync-user";
        runtimeInputs = [ pkgs.curl pkgs.coreutils pkgs.gnugrep pkgs.gnused ];
        text = ''
          SERVER="''${KOSYNC_URL:-http://127.0.0.1:${toString cfg.internalPort}}"
          ENV_FILE="${cfg.adminEnvFile}"
          ADMIN_USER="''${KOSYNC_ADMIN_USER:-admin}"

          if [ ! -r "$ENV_FILE" ]; then
            echo "error: cannot read $ENV_FILE (run as root, e.g. sudo kosync-user ...)" >&2
            exit 1
          fi

          ADMIN_PASSWORD="$(sed -n 's/^ADMIN_PASSWORD=//p' "$ENV_FILE" | head -n1)"
          if [ -z "$ADMIN_PASSWORD" ]; then
            echo "error: ADMIN_PASSWORD is not set in $ENV_FILE" >&2
            exit 1
          fi
          ADMIN_KEY="$(printf %s "$ADMIN_PASSWORD" | md5sum | cut -d' ' -f1)"

          usage() {
            cat <<USAGE
          Usage: kosync-user <command> [args]

          Commands:
            list                       List registered users
            add <username> <password>  Create a user that KOReader/Readest can log into
            passwd <username> <password>  Change a user's reading password
            delete <username>          Delete a user and their reading progress
            documents <username>       List a user's synced documents
            raw <METHOD> <path> [json] Send a raw request to the management API

          Server: $SERVER   (override with KOSYNC_URL)
          USAGE
          }

          admin_curl() {
            curl -fsS -H "x-auth-user: $ADMIN_USER" -H "x-auth-key: $ADMIN_KEY" "$@"
          }

          cmd="''${1:-}"
          case "$cmd" in
            list)
              admin_curl "$SERVER/manage/users"
              echo
              ;;
            add)
              if [ "$#" -ne 3 ]; then usage; exit 2; fi
              # The management API hashes the password it is given, so pass the
              # plaintext here. The stored value then matches the md5 x-auth-key
              # that KOReader/Readest send at login.
              admin_curl -X POST -H 'Content-Type: application/json' \
                -d "{\"username\":\"$2\",\"password\":\"$3\"}" \
                "$SERVER/manage/users"
              echo
              ;;
            passwd)
              if [ "$#" -ne 3 ]; then usage; exit 2; fi
              admin_curl -X PUT -H 'Content-Type: application/json' \
                -d "{\"password\":\"$3\"}" \
                "$SERVER/manage/users/password?username=$2"
              echo
              ;;
            delete)
              if [ "$#" -ne 2 ]; then usage; exit 2; fi
              admin_curl -X DELETE "$SERVER/manage/users?username=$2"
              echo
              ;;
            documents)
              if [ "$#" -ne 2 ]; then usage; exit 2; fi
              admin_curl "$SERVER/manage/users/documents?username=$2"
              echo
              ;;
            raw)
              shift
              METHOD="''${1:-GET}"; PATH_="''${2:-/manage/users}"; shift || true
              if [ "$#" -gt 0 ]; then
                admin_curl -X "$METHOD" -H 'Content-Type: application/json' \
                  -d "$1" "$SERVER$PATH_"
              else
                admin_curl -X "$METHOD" "$SERVER$PATH_"
              fi
              echo
              ;;
            *)
              usage
              exit 2
              ;;
          esac
        '';
      })
    ];

    # ------------------------------------------------------------------------
    # FIREWALL
    # ------------------------------------------------------------------------
    networking.firewall = {
      allowedTCPPorts = [ cfg.port ];
      interfaces."tailscale0".allowedTCPPorts = [ cfg.port ];
    };
  };
}
