### The Successful NixOS Installation Workflow: A Detailed Guide

This guide documents the exact sequence of steps that worked, including the critical directory changes and command syntax that resolved the errors.

#### **Phase 1: Preparation (Before Booting the Installer)**

This phase involves setting up the initial configuration files in a version-controlled repository.

1.  **Create a Git Repository:** On a separate machine, create a new Git repository. This will be the single source of truth for your server's configuration. In your case, this repository would be named something like `karmalab`.

2.  **Create the Initial Configuration Files:** Inside the repository, create the three essential files for the initial installation.

      * **`flake.nix`**: This file defines the system's dependencies, including the NixOS package set (`nixpkgs`) and the `disko` partitioning tool.

        ```nix
        # /flake.nix
        {
          description = "NixOS configuration for the ASUS NUC Homelab";

          inputs = {
            nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
            disko = {
              url = "github:nix-community/disko";
              inputs.nixpkgs.follows = "nixpkgs";
            };
          };

          outputs = { self, nixpkgs, disko,... }@inputs: {
            nixosConfigurations = {
              nuc-server = nixpkgs.lib.nixosSystem {
                system = "x88_64-linux";
                specialArgs = { inherit inputs; };
                modules = [
                 ./configuration.nix
                  disko.nixosModules.disko
                ];
              };
            };
          };
        }
        ```

      * **`disko-config.nix`**: This file declaratively defines the disk layout.

        ```nix
        # /disko-config.nix
        { lib,... }:
        {
          disko.devices = {
            disk = {
              nvme0 = {
                device = "/dev/disk/by-id/your-nvme-disk-id"; # Replaced with your actual ID
                type = "disk";
                content = {
                  type = "gpt";
                  partitions = {
                    boot = {
                      size = "1G";
                      type = "EF00";
                      content = { type = "filesystem"; format = "vfat"; mountpoint = "/boot"; };
                    };
                    root = {
                      size = "100%";
                      content = { type = "filesystem"; format = "ext4"; mountpoint = "/"; };
                    };
                  };
                };
              };
              sda = {
                device = "/dev/disk/by-id/your-20tb-hdd-id"; # Replaced with your actual ID
                type = "disk";
                content = { type = "zfs"; pool = "storagepool"; };
              };
            };
            zpool = {
              storagepool = {
                type = "zpool";
                datasets = { "data" = { type = "zfs_fs"; mountpoint = "/data"; }; };
                rootFsOptions = { compression = "lz4"; xattr = "sa"; acltype = "posixacl"; };
              };
            };
          };
        }
        ```

      * **`configuration.nix`**: The minimal system configuration needed for the first boot.

        ```nix
        # /configuration.nix
        { config, pkgs, inputs,... }:
        {
          imports = [./hardware-configuration.nix./disko-config.nix ];
          boot.loader.systemd-boot.enable = true;
          boot.loader.efi.canTouchEfiVariables = true;
          networking.hostName = "nuc-server";
          time.timeZone = "Asia/Kolkata";
          services.openssh.enable = true;
          users.users.your-username = {
            isNormalUser = true;
            extraGroups = [ "wheel" ];
          };
          nixpkgs.config.allowUnfree = true;
          nix.settings.experimental-features = [ "nix-command" "flakes" ];
          system.stateVersion = "23.11";
        }
        ```

3.  **Commit and Push:** Save these files, commit them to your Git repository, and push them.

#### **Phase 2: The Installation Process (On the Live USB)**

This is the sequence of commands run inside the NixOS installer environment.

1.  **Boot and Connect:** Boot the NUC from the NixOS installer USB and connect to the internet.

2.  **Clone Your Configuration:** Install Git and clone your repository into the home directory of the live user (`nixos`). This creates your working "environment".

    ```bash
    nix-shell -p git
    git clone <your-repo-url> /home/nixos/karmalab
    ```

3.  **The "Directory Quirk" - Change Directory:** This was the first critical fix. To avoid path ambiguity errors, you must navigate *into* your configuration directory before running `disko`.

    ```bash
    cd /home/nixos/karmalab
    ```

4.  **Run `disko` Correctly:** From inside your configuration directory, run `disko` using `.` to refer to the flake in the current directory. This was the second critical fix. This command wipes the specified disks, creates the partitions and filesystems, and mounts them under `/mnt`.

    ```bash
    sudo nix --experimental-features "nix-command flakes" run github:nix-community/disko -- --mode disko --flake.#nuc-server
    ```

5.  **Generate Hardware Configuration:** Create the hardware-specific configuration file. The `--no-filesystems` flag is essential because `disko` has already defined our filesystem layout.

    ```bash
    sudo nixos-generate-config --no-filesystems --root /mnt
    ```

6.  **The ZFS `hostId` Fix:** ZFS requires a unique machine ID.

      * Generate the ID:
        ```bash
        head -c 4 /dev/urandom | od -A n -t x4 | tr -d ' '
        ```
      * Add it to your source configuration file (still in `/home/nixos/karmalab`) using `nano`:
        ```bash
        nano /home/nixos/karmalab/configuration.nix
        ```
        Add the line `networking.hostId = "your-generated-id";` to the file and save it.

7.  **The Final Copy:** This was the final crucial step. The `nixos-install` script needs your configuration to be present on the target system's drive (`/mnt`). Copy your entire, now-corrected configuration into place.

    ```bash
    sudo cp -r /home/nixos/karmalab/* /mnt/etc/nixos/
    ```

8.  **Run `nixos-install`:** Execute the installation command, pointing it to the flake you just copied onto the target drive.

    ```bash
    sudo nixos-install --flake /mnt/etc/nixos#nuc-server
    ```

9.  **Set Passwords:** The installer will prompt you to set a password for the `root` user.

10. **Success\!** The process completes with the `installation finished!` message, as shown in your screenshot.

11. **Reboot:**

    ```bash
    reboot
    ```

    Remember to remove the USB drive as the system restarts. Your server is now successfully installed and ready for the next phase of configuration.
