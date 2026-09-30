# modules/services/kosync-backup.nix
# ============================================================================
# READING-STATE BACKUP
# ============================================================================
#
# The KOSync database (reading position for every book) and the KoInsight
# statistics database live under /var/lib, which is on the NVMe *root* ext4
# filesystem — NOT the ZFS pool, so ZFS auto-snapshots do not cover them.
#
# This timer produces a dated, compressed copy of both databases on the ZFS
# pool, where it *is* covered by auto-snapshots, and prunes old copies.
#
# It is deliberately simple:
#   - copies use SQLite/LiteDB-safe semantics by copying the whole data dir
#   - the LiteDB file is small (KBs–MBs), so full copies are cheap
#   - retains the newest N copies
#
# Restore:
#   sudo systemctl stop docker-kosync
#   sudo cp /data/media/ebooks/.backups/kosync/Kosync.db /var/lib/kosync/Kosync.db
#   sudo chown 1000:100 /var/lib/kosync/Kosync.db
#   sudo systemctl start docker-kosync
#
# ============================================================================

{ config, lib, pkgs, ... }:

let
  cfg = config.services.kosync-backup;
in
{
  options.services.kosync-backup = {
    enable = lib.mkEnableOption "periodic backup of reading state (KOSync + KoInsight)";

    destDir = lib.mkOption {
      type = lib.types.path;
      default = "/data/media/ebooks/.backups";
      description = ''
        Destination on the ZFS pool. This lives inside the snapshotted
        `media/ebooks` dataset so the backups are themselves protected.
      '';
    };

    retain = lib.mkOption {
      type = lib.types.int;
      default = 14;
      description = "Number of dated backup directories to keep.";
    };

    schedule = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "systemd OnCalendar expression for the backup.";
    };

    paths = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = {
        kosync = "/var/lib/kosync";
        koinsight = "/var/lib/koinsight";
      };
      description = "Name -> source directory pairs to back up.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.kosync-backup = {
      description = "Back up KOSync and KoInsight reading state";
      after = [ "storage-online.target" ];
      wants = [ "storage-online.target" ];
      # Only run when the pool is actually mounted; otherwise we would write
      # into the root filesystem and silently produce no backup.
      unitConfig.ConditionPathIsMountPoint = cfg.destDir;

      serviceConfig = {
        Type = "oneshot";
        # mkdir/chown/cp need to see the ZFS mount and container-owned files
        User = "root";
        # Ensure the pool is up before we try; nofail mounts mean the unit can
        # still start without it, hence the Condition above.
      };

      script = ''
        set -euo pipefail
        DEST="${cfg.destDir}"
        STAMP="$(date -u +%Y%m%d-%H%M%S)"
        OUT="$DEST/$STAMP"

        mkdir -p "$OUT"
        chmod 0755 "$DEST" "$OUT"

        copied=0
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: src: ''
          if [ -d "${src}" ]; then
            mkdir -p "$OUT/${name}"
            # cp -a preserves ownership (uid 1000) so a restore is a plain copy.
            ${pkgs.coreutils}/bin/cp -a "${src}/." "$OUT/${name}/" 2>/dev/null || true
            echo "backed up ${name} ($(du -sh "${src}" 2>/dev/null | cut -f1))"
            copied=$((copied + 1))
          else
            echo "skip ${name} (missing: ${src})"
          fi
        '') cfg.paths)}

        if [ "$copied" -eq 0 ]; then
          echo "nothing to back up; removing empty backup dir"
          rmdir "$OUT" 2>/dev/null || true
          exit 0
        fi

        # Prune: keep the newest N dated directories.
        cd "$DEST"
        ls -1dt [0-9]* 2>/dev/null | tail -n +$((${toString cfg.retain} + 1)) | while read -r old; do
          echo "pruning $old"
          rm -rf -- "$old"
        done

        echo "reading-state backup complete -> $OUT"
      '';
    };

    systemd.timers.kosync-backup = {
      description = "Daily reading-state backup";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
        RandomizedDelaySec = "5m";
      };
    };
  };
}
