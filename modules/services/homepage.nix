# modules/services/homepage.nix
# ============================================================================
# HOMEPAGE DASHBOARD WITH GLANCES
# ============================================================================
#
# Homepage is a modern, customizable dashboard for all homelab services.
# Glances provides system metrics displayed on the dashboard.
#
# Features:
# - Clean, Wolfgang-style UI with status indicators
# - Service categories: Media, Arr Stack, Downloads, Photos, Infrastructure
# - System metrics via Glances (CPU, memory, network, temperature)
# - Click-through to all services
#
# Access:
# - http://192.168.0.200 (via Caddy reverse proxy)
# - http://192.168.0.200:8082 (direct)
#
# ============================================================================

{ config, lib, pkgs, ... }:

let
  # Service URLs for homepage
  serverIP = "192.168.0.200";
in
{
  # ============================================================================
  # GLANCES - SYSTEM MONITORING
  # ============================================================================

  services.glances = {
    enable = true;
    port = 61208;  # Default Glances port
    openFirewall = false;  # Only accessed locally by Homepage
  };

  # ============================================================================
  # HOMEPAGE DASHBOARD
  # ============================================================================

  services.homepage-dashboard = {
    enable = true;
    listenPort = 8082;
    openFirewall = false;  # Accessed via Caddy on port 80

    # Allow access via various hostnames/IPs (required since NixOS 25.05)
    # This is a comma-separated string, not a list
    allowedHosts = "192.168.0.200,karmalab,karmalab.local,karmalab.tail*,localhost,127.0.0.1";

    # Dashboard settings
    settings = {
      title = "Karmalab";
      description = "Home Server Dashboard";
      theme = "dark";
      color = "slate";
      headerStyle = "clean";
      statusStyle = "dot";
      hideVersion = true;
      
      layout = {
        Media = {
          style = "column";
          icon = "mdi-play-circle";
        };
        "Arr Stack" = {
          style = "column";
          icon = "mdi-download";
        };
        Downloads = {
          style = "column";
          icon = "mdi-cloud-download";
        };
        Photos = {
          style = "column";
          icon = "mdi-image";
        };
        Infrastructure = {
          style = "column";
          icon = "mdi-server";
        };
        System = {
          style = "row";
          columns = 4;
        };
      };
    };

    # Custom CSS for Wolfgang-style look
    customCSS = ''
      body, html {
        font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif !important;
      }
      .font-medium {
        font-weight: 700 !important;
      }
      .font-light {
        font-weight: 500 !important;
      }
      .font-thin {
        font-weight: 400 !important;
      }
      #information-widgets {
        padding-left: 1.5rem;
        padding-right: 1.5rem;
      }
      div#footer {
        display: none;
      }
    '';

    # Service definitions
    services = [
      # Media Services
      {
        "Media" = [
          {
            "Jellyfin" = {
              icon = "jellyfin.svg";
              description = "Media streaming server";
              href = "http://${serverIP}:8096";
              siteMonitor = "http://${serverIP}:8096";
              widget = {
                type = "jellyfin";
                url = "http://${serverIP}:8096";
                key = "{{HOMEPAGE_VAR_JELLYFIN_API_KEY}}";
                enableBlocks = true;
                enableNowPlaying = true;
              };
            };
          }
          {
            "Jellyseerr" = {
              icon = "jellyseerr.svg";
              description = "Media request manager";
              href = "http://${serverIP}:5055";
              siteMonitor = "http://${serverIP}:5055";
              widget = {
                type = "jellyseerr";
                url = "http://${serverIP}:5055";
                key = "{{HOMEPAGE_VAR_JELLYSEERR_API_KEY}}";
              };
            };
          }
        ];
      }

      # Arr Stack
      {
        "Arr Stack" = [
          {
            "Radarr" = {
              icon = "radarr.svg";
              description = "Movie automation";
              href = "http://${serverIP}:7878";
              siteMonitor = "http://${serverIP}:7878";
              widget = {
                type = "radarr";
                url = "http://${serverIP}:7878";
                key = "{{HOMEPAGE_VAR_RADARR_API_KEY}}";
              };
            };
          }
          {
            "Sonarr" = {
              icon = "sonarr.svg";
              description = "TV show automation";
              href = "http://${serverIP}:8989";
              siteMonitor = "http://${serverIP}:8989";
              widget = {
                type = "sonarr";
                url = "http://${serverIP}:8989";
                key = "{{HOMEPAGE_VAR_SONARR_API_KEY}}";
              };
            };
          }
          {
            "Bazarr" = {
              icon = "bazarr.svg";
              description = "Subtitle automation";
              href = "http://${serverIP}:6767";
              siteMonitor = "http://${serverIP}:6767";
              widget = {
                type = "bazarr";
                url = "http://${serverIP}:6767";
                key = "{{HOMEPAGE_VAR_BAZARR_API_KEY}}";
              };
            };
          }
          {
            "Prowlarr" = {
              icon = "prowlarr.svg";
              description = "Indexer manager";
              href = "http://${serverIP}:9696";
              siteMonitor = "http://${serverIP}:9696";
              widget = {
                type = "prowlarr";
                url = "http://${serverIP}:9696";
                key = "{{HOMEPAGE_VAR_PROWLARR_API_KEY}}";
              };
            };
          }
        ];
      }

      # Downloads
      {
        "Downloads" = [
          {
            "Deluge" = {
              icon = "deluge.svg";
              description = "Torrent client (VPN)";
              href = "http://${serverIP}:8112";
              siteMonitor = "http://${serverIP}:8112";
              widget = {
                type = "deluge";
                url = "http://${serverIP}:8112";
                password = "{{HOMEPAGE_VAR_DELUGE_PASSWORD}}";
              };
            };
          }
          {
            "aria2" = {
              icon = "ariang.svg";
              description = "HTTP/FTP download manager";
              href = "http://${serverIP}:6880";
              siteMonitor = "http://${serverIP}:6800/jsonrpc";
            };
          }
        ];
      }

      # Photos
      {
        "Photos" = [
          {
            "Immich" = {
              icon = "immich.svg";
              description = "Photo management";
              href = "http://${serverIP}:2283";
              siteMonitor = "http://${serverIP}:2283";
              widget = {
                type = "immich";
                url = "http://${serverIP}:2283";
                key = "{{HOMEPAGE_VAR_IMMICH_API_KEY}}";
              };
            };
          }
        ];
      }

      # Infrastructure
      {
        "Infrastructure" = [
          {
            "Uptime Kuma" = {
              icon = "uptime-kuma.svg";
              description = "Service monitoring";
              href = "http://${serverIP}:3001";
              siteMonitor = "http://${serverIP}:3001";
              widget = {
                type = "uptimekuma";
                url = "http://${serverIP}:3001";
                slug = "karmalab";
              };
            };
          }
          {
            "Syncthing" = {
              icon = "syncthing.svg";
              description = "File synchronization";
              href = "http://${serverIP}:8384";
              siteMonitor = "http://${serverIP}:8384";
            };
          }
          {
            "Forgejo" = {
              icon = "forgejo.svg";
              description = "Git server";
              href = "http://${serverIP}:3030";
              siteMonitor = "http://${serverIP}:3030";
            };
          }
          {
            "Time Machine" = {
              icon = "mdi-apple-finder";
              description = "macOS backup server";
              href = "smb://${serverIP}/timemachine";
            };
          }
        ];
      }

      # System metrics via Glances
      {
        "System" = [
          {
            "Info" = {
              widget = {
                type = "glances";
                url = "http://localhost:61208";
                metric = "info";
                chart = false;
                version = 4;
              };
            };
          }
          {
            "CPU" = {
              widget = {
                type = "glances";
                url = "http://localhost:61208";
                metric = "cpu";
                chart = false;
                version = 4;
              };
            };
          }
          {
            "Memory" = {
              widget = {
                type = "glances";
                url = "http://localhost:61208";
                metric = "memory";
                chart = false;
                version = 4;
              };
            };
          }
          {
            "Network" = {
              widget = {
                type = "glances";
                url = "http://localhost:61208";
                metric = "network:enp1s0";
                chart = false;
                version = 4;
              };
            };
          }
        ];
      }
    ];

    # Bookmarks for quick external links
    bookmarks = [
      {
        "External Access" = [
          {
            "Jellyfin (External)" = [
              {
                icon = "jellyfin.svg";
                href = "https://jellyfin.somesh.dev";
              }
            ];
          }
          {
            "Immich (External)" = [
              {
                icon = "immich.svg";
                href = "https://immich.somesh.dev";
              }
            ];
          }
          {
            "Forgejo (External)" = [
              {
                icon = "forgejo.svg";
                href = "https://git.somesh.dev";
              }
            ];
          }
          {
            "Jellyseerr (External)" = [
              {
                icon = "jellyseerr.svg";
                href = "https://request.somesh.dev";
              }
            ];
          }
        ];
      }
      {
        "Management" = [
          {
            "Tailscale Admin" = [
              {
                icon = "tailscale.svg";
                href = "https://login.tailscale.com/admin/machines";
              }
            ];
          }
          {
            "Cloudflare Dashboard" = [
              {
                icon = "cloudflare.svg";
                href = "https://one.dash.cloudflare.com";
              }
            ];
          }
          {
            "GitHub Repo" = [
              {
                icon = "github.svg";
                href = "https://github.com/someshkar/karmalab";
              }
            ];
          }
        ];
      }
    ];

    # Widget definitions
    widgets = [
      {
        resources = {
          cpu = true;
          memory = true;
          disk = "/";
        };
      }
      {
        resources = {
          label = "Storage Pool";
          disk = "/storagepool";
        };
      }
      {
        datetime = {
          text_size = "xl";
          format = {
            dateStyle = "long";
            timeStyle = "short";
            hour12 = false;
          };
        };
      }
    ];
  };

  # ============================================================================
  # ENVIRONMENT FILE FOR API KEYS
  # ============================================================================

  # Homepage reads API keys from environment variables
  # Create /etc/nixos/secrets/homepage.env with:
  # HOMEPAGE_VAR_JELLYFIN_API_KEY=your-key
  # HOMEPAGE_VAR_JELLYSEERR_API_KEY=your-key
  # HOMEPAGE_VAR_RADARR_API_KEY=your-key
  # HOMEPAGE_VAR_SONARR_API_KEY=your-key
  # HOMEPAGE_VAR_BAZARR_API_KEY=your-key
  # HOMEPAGE_VAR_PROWLARR_API_KEY=your-key
  # HOMEPAGE_VAR_DELUGE_PASSWORD=your-password
  # HOMEPAGE_VAR_IMMICH_API_KEY=your-key

  systemd.services.homepage-dashboard.serviceConfig = {
    EnvironmentFile = lib.mkIf (builtins.pathExists "/etc/nixos/secrets/homepage.env") 
      "/etc/nixos/secrets/homepage.env";
  };
}
