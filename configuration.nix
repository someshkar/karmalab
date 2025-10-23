{ config, pkgs, inputs, lib, ... }:

{
  imports = [
   ./hardware-configuration.nix
   ./disko-config.nix
  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # --- IMPORTANT ---
  # Set your hostname
  networking.hostName = "nuc-server";

  # Set a unique hostId for ZFS, which is mandatory.
  networking.hostId = "b291ad23";

  # --- ZFS Configuration ---
  # 1. Enable ZFS support in the kernel and initrd.
  boot.supportedFilesystems = [ "zfs" ];

  # 2. Automatically import the non-root ZFS pool on boot.
  #    "storagepool" is the name you defined in disko-config.nix.
  boot.zfs.extraPools = [ "storagepool" ];
  # Force import behavior for non-root pool
  boot.zfs.forceImportRoot = false;
  boot.zfs.forceImportAll = false;

  # Specify device search path
  boot.zfs.devNodes = "/dev/disk/by-id";


  # 3. (Recommended) Ensure kernel compatibility with the ZFS module.
  #    This prevents breakages from kernel updates.
  boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;

  # 4. (Recommended) Enable automatic weekly scrubbing for data integrity.
  services.zfs.autoScrub.enable = true;
  # Mount ZFS dataset with legacy mountpoint
  fileSystems."/data" = {
    device = "storagepool/data";
    fsType = "zfs";
    options = [
      "zfsutil"
      "nofail"                           # Allow boot to continue if mount fails
      "x-systemd.device-timeout=30"      # Wait 30s for USB device
      "x-systemd.mount-timeout=30"       # Wait 30s for mount operation
      "x-systemd.requires=zfs-import-storagepool.service"  # Explicit dependency
    ];
  };


  # Set your time zone.
  time.timeZone = "Asia/Kolkata";

  # Enable the OpenSSH server.
  services.openssh.enable = true;

  # Define a user account.
  # --- IMPORTANT ---
  # Replace 'your-username' with your desired username.
  # Set a password for the user account after the first boot by running `passwd`
  users.users.somesh = {
    isNormalUser = true;
    extraGroups = [ "wheel" ]; # Enable 'sudo' for the user.
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Enable flakes and the new nix command
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  system.stateVersion = "23.11"; # Or whatever version is current
}