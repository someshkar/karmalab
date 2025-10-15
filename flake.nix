{
  description = "NixOS configuration for the ASUS NUC Homelab";

  inputs = {
    # Nix Packages collection, using unstable for latest hardware support
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Declarative disk partitioning tool
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, disko,... }@inputs: {
    nixosConfigurations = {
      # --- IMPORTANT ---
      # Replace 'nuc-server' with your desired hostname
      nuc-server = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; }; # Pass flake inputs to modules
        modules = [
         ./configuration.nix
          disko.nixosModules.disko
        ];
      };
    };
  };
}
