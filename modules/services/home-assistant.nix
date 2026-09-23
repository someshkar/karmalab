# modules/services/home-assistant.nix
# ============================================================================
# HOME ASSISTANT - SMART HOME HUB
# ============================================================================
#
# Home Assistant is a local-first smart home platform. This module runs it
# natively (no Docker) on the NUC.
#
# Why native: Home Assistant's own NixOS module gives us a managed service,
# strict systemd sandboxing, declarative components and a stable data dir.
# The Docker "Supervisor" install is upstream's supported path, but it is a
# much heavier, less Nix-idiomatic setup; native is the right fit here.
#
# Version: pinned to nixpkgs-unstable (see `haPackage`) because nixos-25.11
# ships Home Assistant 2025.11.x while unstable tracks the current release.
# This mirrors the Jellyfin pin in configuration.nix.
#
# Integrations:
# - tuya_local  (custom component) - LOCAL control of Tuya-based plugs,
#                 e.g. the Zebronics ZEB-SP110 (see docs/home-assistant-setup.md)
# - tuya        (core)             - cloud fallback; the official Tuya
#                 integration cannot control IR remotes (see docs)
# - esphome     (core)             - for future ESPHome devices (IR blaster)
#
# Data:
# - /var/lib/hass   - config, database and all state (owned by `hass`)
#
# Access:
# - Local:     http://192.168.68.59:8123
# - Tailscale: http://karmalab:8123
# - Public:    https://home.somesh.dev via Cloudflare Tunnel (Phase 2)
#
# NOTE: `config` below is managed by Nix and re-applied on every service
# start. The UI-managed parts of config live in /var/lib/hass/.storage and
# are NOT touched by this module. Edit this file, not configuration.yaml.
#
# ============================================================================

{ config, lib, pkgs, inputs, ... }:

let
  # Home Assistant package from nixpkgs-unstable (tracks the current release).
  haPackage = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};

  haPort = 8123;
in
{
  # ============================================================================
  # HOME ASSISTANT SERVICE
  # ============================================================================

  services.home-assistant = {
    enable = true;

    # Use the newer package set for both the server and its custom component.
    package = haPackage.home-assistant;

    # Allow the UI to write configuration.yaml. Without this the module would
    # symlink it read-only into the Nix store on every start. The managed
    # config is still re-copied on each service start (see file header).
    configWritable = true;

    # Core integrations whose Python dependencies are bundled into the package.
    # (The module already adds default_config, met and esphome by default.)
    extraComponents = [
      "default_config"
      "met"          # weather / location metadata for onboarding
      "esphome"      # for future ESPHome/IR devices
      "tuya"         # official cloud integration (fallback for Tuya devices)
      "ffmpeg"       # media/camera streams
    ];

    # Custom components packaged in nixpkgs. tuya_local gives LOCAL control of
    # Tuya devices (no cloud round-trip) and is what the ZEB-SP110 uses.
    customComponents = [
      haPackage.home-assistant-custom-components.tuya_local
    ];

    # Declarative configuration.yaml. `default_config` pulls in the frontend,
    # history, energy, backups and friends. Secrets are provided via onboarding.
    config = {
      homeassistant = {
        name = "Karmalab";
        unit_system = "metric";
        time_zone = config.time.timeZone;
      };

      http = {
        server_port = haPort;
      };

      # The UI (Lovelace) is managed from the browser and stored in .storage.
      lovelace.mode = "storage";

      # Sensible defaults for a small home setup.
      recorder = {
        purge_keep_days = 30;
      };
    };
  };

  # ============================================================================
  # FIREWALL
  # ============================================================================
  #
  # Local network + Tailscale only. Public access (Cloudflare Tunnel) is added
  # in a later phase once the proxy headers are configured.

  networking.firewall.allowedTCPPorts = [ haPort ];
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ haPort ];

  # ============================================================================
  # BACKUP NOTE
  # ============================================================================
  #
  # All Home Assistant state lives in /var/lib/hass, which is on the root
  # ext4 filesystem (NOT the ZFS pool), so it is not covered by ZFS snapshots.
  # To roll back: restore /var/lib/hass from a backup, or roll back the NixOS
  # generation to revert the service itself.
}
