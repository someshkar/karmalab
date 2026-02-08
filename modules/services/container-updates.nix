# modules/services/container-updates.nix
# ============================================================================
# CONTAINER UPDATE CHECKER - Automated version monitoring
# ============================================================================
#
# Checks GitHub releases for version-pinned containers and reports updates
# via Beszel custom metrics and Homepage dashboard widget.
#
# Tracked Services:
# - Immich (ghcr.io/immich-app/immich-server)
# - immich-go (GitHub releases)
# - OpenCloud (Docker image, version-pinned)
#
# Integration:
# - Writes Prometheus-compatible metrics to Beszel agent custom metrics dir
# - Writes JSON for Homepage widget at /var/lib/beszel-agent/custom-metrics/updates.json
# - Serves via Caddy at /updates.json
# - Runs daily at 6:00 AM via systemd timer
#
# Output Locations:
# - Prometheus: /var/lib/beszel-agent/custom-metrics/update-status.prom
# - JSON: /var/lib/beszel-agent/custom-metrics/updates.json
#
# ============================================================================

{ config, lib, pkgs, ... }:

let
  # Paths
  metricsDir = "/var/lib/beszel-agent/custom-metrics";
  configDir = "/home/somesh/karmalab";
  
  # Update checker script
  updateCheckerScript = pkgs.writeShellScriptBin "container-update-checker" ''
    #!/usr/bin/env bash
    set -euo pipefail
    
    # Configuration
    METRICS_FILE="${metricsDir}/update-status.prom"
    JSON_FILE="${metricsDir}/updates.json"
    TEMP_FILE="$(mktemp)"
    JSON_TEMP="$(mktemp)"
    
    # Initialize JSON array
    echo '{"last_check":"'$(date -Iseconds)'","services":[' > "$JSON_TEMP"
    FIRST_SERVICE=true
    
    # GitHub API helper function with retry
    get_github_latest_release() {
      local repo="$1"
      local api_url="https://api.github.com/repos/$repo/releases/latest"
      local max_retries=3
      local retry_count=0
      local result=""
      
      while [[ $retry_count -lt $max_retries ]]; do
        # Fetch latest release (anonymous API - 60 req/hour limit)
        result=$(curl -sL --max-time 10 "$api_url" 2>/dev/null | ${pkgs.jq}/bin/jq -r '.tag_name // empty' 2>/dev/null || echo "")
        
        if [[ -n "$result" ]]; then
          echo "$result"
          return 0
        fi
        
        retry_count=$((retry_count + 1))
        if [[ $retry_count -lt $max_retries ]]; then
          echo "[DEBUG] GitHub API call failed for $repo, retrying ($retry_count/$max_retries)..." >&2
          sleep 2
        fi
      done
      
      echo "[DEBUG] Failed to fetch version for $repo after $max_retries attempts" >&2
      echo ""
    }
    
    # Parse current Immich version from docker-compose.yml
    # Version is in comment: "# Version: v2.5.2 (pinned for stability)"
    get_current_immich_version() {
      local compose_file="${configDir}/docker/immich/docker-compose.yml"
      if [[ -f "$compose_file" ]]; then
        # Extract version from comment line (handles "v2.5.2" or "v2.5.2 (pinned for stability)")
        grep -oP '^# Version:\s*\K[^\s]+' "$compose_file" 2>/dev/null | head -1 || echo "unknown"
      else
        echo "unknown"
      fi
    }
    
    # Parse current immich-go version from immich-go.nix
    get_current_immich_go_version() {
      local nix_file="${configDir}/modules/immich-go.nix"
      if [[ -f "$nix_file" ]]; then
        grep -oP 'version = "\K[^"]+' "$nix_file" 2>/dev/null | head -1 || echo "unknown"
      else
        echo "unknown"
      fi
    }
    
    # Parse current OpenCloud version from running container
    get_current_opencloud_version() {
      # Get version from running opencloud container
      local version=$(docker exec opencloud opencloud --version 2>/dev/null | grep -oP '\K[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "")
      if [[ -n "$version" ]]; then
        echo "$version"
      else
        # Fallback to .env file if container not running
        local env_file="/var/lib/opencloud/.env"
        if [[ -f "$env_file" ]]; then
          grep -oP '^OC_VERSION=\K[^\s]+' "$env_file" 2>/dev/null | head -1 || echo "latest"
        else
          echo "latest"
        fi
      fi
    }
    
    # Normalize version string (remove 'v' prefix if present)
    normalize_version() {
      echo "$1" | sed 's/^v//'
    }
    
    # Write metric to temp file and JSON
    write_metric() {
      local service="$1"
      local current="$2"
      local latest="$3"
      local update_available=0
      
      # Normalize versions for comparison (remove 'v' prefix)
      local current_norm=$(normalize_version "$current")
      local latest_norm=$(normalize_version "$latest")
      
      # Compare normalized versions
      if [[ "$current_norm" != "$latest_norm" && "$latest" != "unknown" && "$current" != "unknown" && "$latest" != "" ]]; then
        update_available=1
      fi
      
      # Write Prometheus metric
      echo "# HELP update_available Whether an update is available for $service" >> "$TEMP_FILE"
      echo "# TYPE update_available gauge" >> "$TEMP_FILE"
      echo "update_available{service=\"$service\",current=\"$current\",latest=\"$latest\"} $update_available" >> "$TEMP_FILE"
      
      # Write JSON entry
      if [[ "$FIRST_SERVICE" == "false" ]]; then
        echo "," >> "$JSON_TEMP"
      fi
      FIRST_SERVICE=false
      echo "{\"name\":\"$service\",\"current\":\"$current\",\"latest\":\"$latest\",\"update_available\":$update_available,\"display\":\"$current → $latest\"}" >> "$JSON_TEMP"
    }
    
    # Write Prometheus header
    echo "# Container Update Check - $(date -Iseconds)" > "$TEMP_FILE"
    echo "" >> "$TEMP_FILE"
    
    # Check Immich
    echo "Checking Immich..." >&2
    IMMICH_CURRENT=$(get_current_immich_version)
    IMMICH_LATEST=$(get_github_latest_release "immich-app/immich")
    write_metric "immich" "$IMMICH_CURRENT" "$IMMICH_LATEST"
    
    # Check immich-go
    echo "Checking immich-go..." >&2
    IMMICH_GO_CURRENT=$(get_current_immich_go_version)
    IMMICH_GO_LATEST=$(get_github_latest_release "simulot/immich-go")
    write_metric "immich-go" "$IMMICH_GO_CURRENT" "$IMMICH_GO_LATEST"
    
    # Check OpenCloud
    echo "Checking OpenCloud..." >&2
    OPENCLOUD_CURRENT=$(get_current_opencloud_version)
    OPENCLOUD_LATEST=$(get_github_latest_release "opencloud-eu/opencloud")
    write_metric "opencloud" "$OPENCLOUD_CURRENT" "$OPENCLOUD_LATEST"
    
    # Close JSON and write files
    echo ']}' >> "$JSON_TEMP"
    mv "$TEMP_FILE" "$METRICS_FILE"
    mv "$JSON_TEMP" "$JSON_FILE"
    chmod 644 "$METRICS_FILE" "$JSON_FILE"
    
    # Log results
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Update check complete:" >&2
    echo "  Immich: $IMMICH_CURRENT (current) -> $IMMICH_LATEST (latest)" >&2
    echo "  immich-go: $IMMICH_GO_CURRENT (current) -> $IMMICH_GO_LATEST (latest)" >&2
    echo "  OpenCloud: $OPENCLOUD_CURRENT (current) -> $OPENCLOUD_LATEST (latest)" >&2
  '';
in
{
  # ============================================================================
  # SYSTEMD SERVICE - Update Checker
  # ============================================================================
  
  systemd.services.container-update-checker = {
    description = "Container Update Checker";
    
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${updateCheckerScript}/bin/container-update-checker";
      User = "root";
      
      # Security hardening
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ metricsDir ];
      ReadOnlyPaths = [ configDir "/var/lib/opencloud" ];
      
      # Network access needed for GitHub API
      PrivateNetwork = false;
      
      # Docker access needed to read OpenCloud version
      ExecStartPre = "${pkgs.docker}/bin/docker ps";
    };
    
    # Run after Beszel agent to ensure metrics dir exists
    after = [ "docker-beszel-agent.service" "docker.service" ];
    wants = [ "docker-beszel-agent.service" "docker.service" ];
  };
  
  # ============================================================================
  # SYSTEMD TIMER - Daily at 6:00 AM
  # ============================================================================
  
  systemd.timers.container-update-checker = {
    description = "Run container update checker daily";
    wantedBy = [ "timers.target" ];
    
    timerConfig = {
      OnCalendar = "06:00:00";
      Persistent = true;  # Run immediately if missed (e.g., system was off)
      RandomizedDelaySec = 300;  # Random delay up to 5 minutes to avoid thundering herd
    };
  };
  
  # ============================================================================
  # DIRECTORY SETUP
  # ============================================================================
  
  systemd.tmpfiles.rules = [
    # Ensure Beszel agent custom metrics directory exists
    "d ${metricsDir} 0755 root root -"
  ];
  
  # ============================================================================
  # PACKAGES
  # ============================================================================
  
  environment.systemPackages = with pkgs; [
    curl
    jq
    docker
    updateCheckerScript  # Make script available for manual runs
  ];
}
