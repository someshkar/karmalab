# modules/immich-go.nix
# ============================================================================
# IMMICH-GO PACKAGE DERIVATION
# ============================================================================
#
# immich-go is a Go-based tool for uploading photos to Immich servers.
# It's especially useful for Google Photos Takeout migration with:
# - Automatic duplicate detection (SHA-1 checksums)
# - Metadata preservation (albums, dates, GPS from JSON sidecars)
# - Burst photo stacking and RAW+JPEG pairing
# - Resume capability for interrupted uploads
#
# Usage:
#   immich-go upload from-google-photos \
#     --server=http://localhost:2283 \
#     --api-key=YOUR_API_KEY \
#     /path/to/takeout-*.zip
#
# Documentation: https://github.com/simulot/immich-go
#
# ============================================================================

{ config, lib, pkgs, ... }:

let
  # immich-go binary package
  immich-go = pkgs.stdenv.mkDerivation rec {
    pname = "immich-go";
    version = "0.31.0";
    
    src = pkgs.fetchurl {
      url = "https://github.com/simulot/immich-go/releases/download/v${version}/immich-go_Linux_x86_64.tar.gz";
      sha256 = "sha256-ZoNuZNt+5SGbvFWYr+CQ2JlbAj8O/gBJjukrsFOL5hA=";
    };
    
    # No build required - just extract the binary
    dontBuild = true;
    dontConfigure = true;
    
    # Required for extracting tar.gz
    nativeBuildInputs = [ pkgs.gnutar pkgs.gzip ];
    
    unpackPhase = ''
      tar xzf $src
    '';
    
    installPhase = ''
      mkdir -p $out/bin
      cp immich-go $out/bin/
      chmod +x $out/bin/immich-go
    '';
    
    meta = with lib; {
      description = "Upload photos to Immich server, especially Google Photos Takeout";
      homepage = "https://github.com/simulot/immich-go";
      license = licenses.agpl3Only;
      platforms = [ "x86_64-linux" ];
      maintainers = [];
    };
  };
in
{
  # Add immich-go to system packages
  environment.systemPackages = [ immich-go ];
}
