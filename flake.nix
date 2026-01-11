{
  description = "NixOS configuration for the ASUS NUC Homelab - Media Server Stack";

  inputs = {
    # Nix Packages - using 25.11 stable (released November 30, 2025)
    # Note: Intel N150 Quick Sync works on stable with linuxPackages_latest
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    # Declarative disk partitioning (for NVMe boot disk only)
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, disko, ... }@inputs: {
    nixosConfigurations = {
      nuc-server = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        
        # Pass flake inputs to all modules
        specialArgs = { inherit inputs; };
        
        modules = [
          # Disko for NVMe disk management
          disko.nixosModules.disko
          
          # Main configuration (imports all other modules)
          ./configuration.nix
        ];
      };
    };
    
    # Convenience outputs for deployment
    # Usage: nix build .#nixosConfigurations.nuc-server.config.system.build.toplevel
  };
}
