# modules/services/karmes.nix
# Native Karmes/Hermes deployment for karmalab.
# - Hermes runs as native systemd services (gateway + dashboard)
# - Camoufox runs as dedicated native systemd service
# - Docker is only used by Hermes as an optional terminal/code sandbox backend

{ config, lib, pkgs, ... }:

let
  karmesRoot = "/srv/karmes";
  hermesSrc = "${karmesRoot}/hermes-src";
  hermesVenv = "${karmesRoot}/hermes-venv";
  hermesData = "${karmesRoot}/hermes-data";
  secretsEnv = "${karmesRoot}/secrets/hermes.env";
  camoufoxNpm = "${karmesRoot}/browser/npm";

  browserLibPath = lib.makeLibraryPath (with pkgs; [
    stdenv.cc.cc.lib
    glib
    gtk3
    nss
    nspr
    dbus
    at-spi2-core
    cups
    libdrm
    mesa
    libxkbcommon
    xorg.libX11
    xorg.libXcomposite
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXrandr
    xorg.libxcb
    xorg.libXi
    xorg.libXtst
    xorg.libXcursor
    xorg.libXrender
    pango
    cairo
    alsa-lib
    expat
    fontconfig
    freetype
    zlib
  ]);
in
{
  # Arbitrary downloaded browser binaries (Camoufox) need FHS dynamic linker
  # compatibility on NixOS plus common browser runtime libraries.
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib
      glib
      gtk3
      nss
      nspr
      dbus
      at-spi2-core
      cups
      libdrm
      mesa
      libxkbcommon
      xorg.libX11
      xorg.libXcomposite
      xorg.libXdamage
      xorg.libXext
      xorg.libXfixes
      xorg.libXrandr
      xorg.libxcb
      xorg.libXi
      xorg.libXtst
      xorg.libXcursor
      xorg.libXrender
      pango
      cairo
      alsa-lib
      expat
      fontconfig
      freetype
      zlib
    ];
  };

  # Browser-heavy workloads can spike; zram protects the homelab from OOMs.
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  users.groups.karmes = {};
  users.users.karmes = {
    isSystemUser = true;
    group = "karmes";
    home = karmesRoot;
    createHome = true;
    extraGroups = [ "docker" ];
  };

  systemd.tmpfiles.rules = [
    "d ${karmesRoot} 0750 karmes karmes -"
    "d ${hermesSrc} 0750 karmes karmes -"
    "d ${hermesVenv} 0750 karmes karmes -"
    "d ${hermesData} 0750 karmes karmes -"
    "d ${karmesRoot}/mcp-servers 0750 karmes karmes -"
    "d ${karmesRoot}/secrets 0750 karmes karmes -"
    "d ${karmesRoot}/browser 0750 karmes karmes -"
    "d ${karmesRoot}/browser/home 0750 karmes karmes -"
    "d ${karmesRoot}/browser/cache 0750 karmes karmes -"
    "d ${karmesRoot}/browser/npm 0750 karmes karmes -"
    "d ${karmesRoot}/browser/npm-cache 0750 karmes karmes -"
    "d ${karmesRoot}/browser/profiles 0750 karmes karmes -"
    "d ${karmesRoot}/browser/logs 0750 karmes karmes -"
    "d ${karmesRoot}/workspace 0750 karmes karmes -"
  ];

  environment.systemPackages = with pkgs; [
    uv
    git
    nodejs_22
    python3
    docker
  ];

  systemd.services.karmes-camoufox-setup = {
    description = "Prepare Karmes Camoufox browser server";
    before = [ "karmes-camoufox.service" ];
    wantedBy = [ "multi-user.target" ];

    path = with pkgs; [
      bash
      coreutils
      nodejs_22
      python3
      gcc
      gnumake
      pkg-config
    ];

    environment = {
      HOME = "${karmesRoot}/browser/home";
      NPM_CONFIG_CACHE = "${karmesRoot}/browser/npm-cache";
      PYTHON = "${pkgs.python3}/bin/python3";
    };

    serviceConfig = {
      Type = "oneshot";
      User = "karmes";
      Group = "karmes";
      WorkingDirectory = camoufoxNpm;
    };

    script = ''
      set -euo pipefail
      npm install --no-audit --no-fund @askjo/camofox-browser
    '';
  };

  systemd.services.karmes-camoufox = {
    description = "Karmes Camoufox browser server";
    after = [ "network-online.target" "karmes-camoufox-setup.service" ];
    wants = [ "network-online.target" ];
    requires = [ "karmes-camoufox-setup.service" ];
    wantedBy = [ "multi-user.target" ];

    path = with pkgs; [
      bash
      coreutils
      nodejs_22
      xorg.xorgserver
      procps
    ];

    environment = {
      HOME = "${karmesRoot}/browser/home";
      XDG_CACHE_HOME = "${karmesRoot}/browser/cache";
      NPM_CONFIG_CACHE = "${karmesRoot}/browser/npm-cache";
      LD_LIBRARY_PATH = browserLibPath;
      CAMOFOX_HOST = "127.0.0.1";
      HOST = "127.0.0.1";
      CAMOFOX_PORT = "9377";
      CAMOFOX_HEADLESS = "true";
      TZ = "Asia/Kolkata";
    };

    serviceConfig = {
      User = "karmes";
      Group = "karmes";
      WorkingDirectory = camoufoxNpm;
      ExecStart = "${pkgs.nodejs_22}/bin/node ${camoufoxNpm}/node_modules/@askjo/camofox-browser/server.js";
      Restart = "always";
      RestartSec = "5s";
    };
  };

  systemd.services.karmes-hermes-setup = {
    description = "Prepare Hermes source and venv for Karmes";
    before = [ "karmes-dashboard.service" "karmes-gateway.service" ];
    wantedBy = [ "multi-user.target" ];

    path = with pkgs; [
      bash
      coreutils
      git
      uv
      python3
      gcc
      gnumake
      pkg-config
    ];

    environment = {
      HOME = karmesRoot;
      UV_PROJECT_ENVIRONMENT = hermesVenv;
      UV_CACHE_DIR = "${karmesRoot}/.uv-cache";
    };

    serviceConfig = {
      Type = "oneshot";
      User = "karmes";
      Group = "karmes";
      WorkingDirectory = karmesRoot;
      TimeoutStartSec = "30min";
    };

    script = ''
      set -euo pipefail
      if [ ! -d ${hermesSrc}/.git ]; then
        rm -rf ${hermesSrc}
        git clone --depth=1 https://github.com/NousResearch/hermes-agent.git ${hermesSrc}
      else
        cd ${hermesSrc}
        git pull --ff-only
      fi

      cd ${hermesSrc}
      uv sync \
        --extra web \
        --extra messaging \
        --extra mcp \
        --extra cli \
        --extra pty \
        --extra google \
        --extra youtube \
        --extra honcho
    '';
  };

  systemd.services.karmes-dashboard = {
    description = "Karmes Hermes Dashboard";
    after = [ "network-online.target" "karmes-hermes-setup.service" ];
    wants = [ "network-online.target" ];
    requires = [ "karmes-hermes-setup.service" ];
    wantedBy = [ "multi-user.target" ];

    path = with pkgs; [ bash coreutils git uv python3 nodejs_22 docker ];

    environment = {
      HOME = karmesRoot;
      HERMES_HOME = hermesData;
      CAMOFOX_URL = "http://127.0.0.1:9377";
      TZ = "Asia/Kolkata";
    };

    unitConfig.ConditionPathExists = [ secretsEnv "${hermesData}/config.yaml" ];

    serviceConfig = {
      User = "karmes";
      Group = "karmes";
      WorkingDirectory = hermesData;
      EnvironmentFile = secretsEnv;
      ExecStart = "${hermesVenv}/bin/hermes dashboard --port 18789 --host 0.0.0.0 --insecure --no-open";
      Restart = "always";
      RestartSec = "10s";
    };
  };

  systemd.services.karmes-gateway = {
    description = "Karmes Hermes Gateway";
    after = [ "network-online.target" "docker.service" "karmes-hermes-setup.service" "karmes-camoufox.service" ];
    wants = [ "network-online.target" ];
    requires = [ "karmes-hermes-setup.service" "karmes-camoufox.service" ];
    wantedBy = [ "multi-user.target" ];

    path = with pkgs; [ bash coreutils git uv python3 nodejs_22 docker ];

    environment = {
      HOME = karmesRoot;
      HERMES_HOME = hermesData;
      HERMES_ACCEPT_HOOKS = "1";
      HERMES_ALLOW_ROOT_GATEWAY = "0";
      CAMOFOX_URL = "http://127.0.0.1:9377";
      TZ = "Asia/Kolkata";
    };

    unitConfig.ConditionPathExists = [ secretsEnv "${hermesData}/config.yaml" ];

    serviceConfig = {
      User = "karmes";
      Group = "karmes";
      WorkingDirectory = hermesData;
      EnvironmentFile = secretsEnv;
      ExecStart = "${hermesVenv}/bin/hermes gateway run --accept-hooks";
      Restart = "always";
      RestartSec = "10s";
    };
  };
}
