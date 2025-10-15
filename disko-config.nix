{ lib,... }:

{
  disko.devices = {
    disk = {
      # OS Disk (NVMe)
      nvme0 = {
        # --- IMPORTANT ---
        # Replace with the actual ID of your NVMe drive
        device = "/dev/disk/by-id/nvme-eui.e8238fa6bf530001001b448b47ee6f6a";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1G";
              type = "EF00"; # EFI System Partition
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
      # Data Disk (20TB HDD)
      sda = {
        # --- IMPORTANT ---
        # Replace with the actual ID of your 20TB HDD
        device = "/dev/disk/by-id/usb-Seagate_Expansion_HDD_00000000NT17VP0M-0:0";
        type = "disk";
        content = {
          type = "zfs";
          pool = "storagepool";
        };
      };
    };
    zpool = {
      storagepool = {
        type = "zpool";
        # We will create a simple root dataset for now.
        # More datasets for services will be added later.
        datasets = {
          "data" = {
            type = "zfs_fs";
            mountpoint = "/data";
          };
        };
        # Recommended ZFS pool options for performance and compatibility
        rootFsOptions = {
          compression = "lz4";
          xattr = "sa";
          acltype = "posixacl";
        };
      };
    };
  };
}
