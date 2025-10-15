{ config, pkgs, inputs,... }:

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
