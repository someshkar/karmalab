# disko-config.nix
# ============================================================================
# DISK PARTITIONING CONFIGURATION
# ============================================================================
#
# This file manages ONLY the NVMe boot/root disk via disko.
# The 20TB USB HDD ZFS pool is managed separately via boot.zfs.extraPools
# in modules/storage.nix for better resilience with hot-pluggable drives.
#
# Why not manage USB HDD here?
# - USB devices have slow enumeration (can take 10-30s to appear)
# - disko expects disks to be available at boot time
# - ZFS pool import failures cause boot failures with disko
# - boot.zfs.extraPools handles this gracefully with timeouts
#
# ============================================================================

{ lib, ... }:

{
  disko.devices = {
    disk = {
      # OS Disk (NVMe) - Boot and root filesystem only
      nvme0 = {
        # --- IMPORTANT ---
        # Replace with the actual ID of your NVMe drive
        # Find with: ls -la /dev/disk/by-id/ | grep nvme
        device = "/dev/disk/by-id/nvme-eui.e8238fa6bf530001001b448b47ee6f6a";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            # EFI System Partition for systemd-boot
            boot = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            # Root filesystem (ext4 for simplicity on boot drive)
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
                mountOptions = [ "noatime" "errors=remount-ro" ];
              };
            };
          };
        };
      };
      
      # NOTE: 20TB USB HDD (storagepool) is NOT managed by disko.
      # See modules/storage.nix for ZFS pool configuration.
      # One-time manual setup required - see SETUP.md
    };
    
    # NOTE: ZFS pools are NOT managed by disko for USB drives.
    # The storagepool ZFS pool is imported via boot.zfs.extraPools
    # with proper timeout handling for slow USB enumeration.
  };
}
