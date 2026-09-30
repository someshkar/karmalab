# modules/services/koinsight.nix
# ============================================================================
# KOINSIGHT - READING STATISTICS DASHBOARD
# ============================================================================
#
# KoInsight turns KOReader reading statistics into a web dashboard: daily
# reading time, a calendar heatmap, per-book progress, streaks and insights.
# It also implements the KOSync protocol, but we deliberately run it as a
# stats dashboard ONLY and keep modules/services/kosync.nix as the single
# source of truth for reading *position*. Two servers writing the same
# document hashes would fight over "furthest progress".
#
# Data flow:
#   KOReader device  --(koinsight.koplugin)-->  KoInsight  (statistics.sqlite)
#
# Why the dashboard needs a plugin / file rather than the sync server:
#   KOSync carries only position (percentage + xpointer). Reading *time* lives
#   in KOReader's local statistics.sqlite, which must be uploaded explicitly.
#
# Networking:
#   - LAN:       http://192.168.68.59:3005
#   - Tailscale: http://karmalab:3005
#
# Storage:
#   - Config/DB/uploads: /var/lib/koinsight (on NVMe root; small)
#   - Included in the nightly reading-state backup timer (see kosync-backup)
#
# Setup:
#   1. Open the dashboard and upload statistics.sqlite once (Settings folder on
#      the device), or install the KoInsight KOReader plugin to sync.
#   2. Covers are not auto-extracted; add them via the "Cover Selector" tab.
#
# ============================================================================

{ config, lib, pkgs, ... }:

let
  cfg = config.services.koinsight;
in
{
  options.services.koinsight = {
    enable = lib.mkEnableOption "KoInsight reading statistics dashboard";

    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/ko-insight/koinsight:latest";
      description = "Container image for KoInsight.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3005;
      description = "Public port for the dashboard, served by Caddy.";
    };

    internalPort = lib.mkOption {
      type = lib.types.port;
      default = 13005;
      description = ''
        Loopback port the container listens on. Must differ from `port`,
        because Caddy (which serves `port`) binds all interfaces including
        loopback.
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/koinsight";
      description = "Directory holding the KoInsight database and uploads.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.docker-koinsight = {
      description = "KoInsight - KOReader reading statistics dashboard";

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
        ${pkgs.docker_29}/bin/docker rm -f koinsight 2>/dev/null || true
      '';

      script = ''
        ${pkgs.docker_29}/bin/docker run \
          --name=koinsight \
          --rm \
          -p 127.0.0.1:${toString cfg.internalPort}:3000 \
          -v ${cfg.dataDir}:/app/data \
          -e HOSTNAME=0.0.0.0 \
          -e PORT=3000 \
          -e MAX_FILE_SIZE_MB=200 \
          --user 1000:1000 \
          ${cfg.image}
      '';

      preStop = ''
        ${pkgs.docker_29}/bin/docker stop koinsight 2>/dev/null || true
      '';
      postStop = ''
        ${pkgs.docker_29}/bin/docker rm -f koinsight 2>/dev/null || true
      '';
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 1000 100 -"
    ];

    # ------------------------------------------------------------------------
    # FIREWALL
    # ------------------------------------------------------------------------
    # Caddy serves the dashboard on cfg.port across all interfaces; the
    # container only listens on loopback (cfg.internalPort).
    networking.firewall = {
      allowedTCPPorts = [ cfg.port ];
      interfaces."tailscale0".allowedTCPPorts = [ cfg.port ];
    };
  };
}
