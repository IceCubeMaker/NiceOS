# niri-setup.nix
#
# Niri Wayland compositor setup.
# DE-agnostic pieces have been split out:
#   wallpaper.nix      — wp-change, wp-tag, wp-bank, swaylock-themed, etc.
#   matugen.nix        — colour templates + matugen/config.toml
#   theming.nix        — GTK, icons, cursors, fonts, Thunar
#   notifications.nix  — swaync, swayosd, bluelight-ctl, airplane-ctl
#
# This file contains only what is genuinely niri-specific:
#   niri package (with optional blur fork)
#   niri-sidebar, nirimap, niri-single-max, niri-steam-notif
#   ndrop, taskcli-sidebar-launch, waybar-wrapper
#   niri-session-manager
#   xwayland-satellite, XDG portals
#   niri KDL config + stasis idle config
#   waybar JSON config + kitty config
#   ASUS asusd + wp-rgb-boot service
#   Disable GNOME/GDM
#
# Place at: /etc/nixos/niri-setup.nix
# Import in: configuration.nix

{ config, pkgs, lib, ... }:

let
  username = config.global.user;
  isNiri   = config.global.default_desktop_environment == "niri";
  blur     = config.global.niriBlur;

  # ── niri-blur-fork: Naxdy's niri fork with blur + KDE protocol support ────
  niri-blur-fork = pkgs.niri.overrideAttrs (old: {
    pname   = "niri-blur-fork";
    version = "0-unstable-naxdy";
    src = pkgs.fetchFromGitHub {
      owner = "Naxdy";
      repo  = "niri";
      rev   = "main";
      hash  = "sha256-UzihXqWLm9Oa2cdI6tIGiyOtwAmlPqUJONi6PlACWQw=";
    };
    cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
      src = pkgs.fetchFromGitHub {
        owner = "Naxdy";
        repo  = "niri";
        rev   = "main";
        hash  = "sha256-UzihXqWLm9Oa2cdI6tIGiyOtwAmlPqUJONi6PlACWQw=";
      };
      hash = "sha256-A36LHa5lJ80JOujwEMPm9sdSh+r9xAeXzpbUpJfGXsY=";
    };
  });

  niri-pkg = if blur then niri-blur-fork else pkgs.niri;

  # ── niri-sidebar ───────────────────────────────────────────────────────────
  niri-sidebar = pkgs.rustPlatform.buildRustPackage {
    pname   = "niri-sidebar";
    version = "0.2.0";
    src = pkgs.fetchFromGitHub {
      owner = "Vigintillionn";
      repo  = "niri-sidebar";
      rev   = "v0.2.0";
      hash  = "sha256-u22NBdefbulqYbTjtljLHaLeA3V8z7G3QUwEeg7TIiE=";
    };
    cargoHash = "sha256-rryIZ8TuKJ0yLoBNmC5/8ja7eSmW3cnVegu7odvw5p8=";
    meta = {
      description = "Floating sidebar manager for the Niri window manager";
      homepage    = "https://github.com/Vigintillionn/niri-sidebar";
      license     = pkgs.lib.licenses.mit;
      mainProgram = "niri-sidebar";
    };
  };

  # ── nirimap ────────────────────────────────────────────────────────────────
  nirimap = pkgs.rustPlatform.buildRustPackage {
    pname   = "nirimap";
    version = "0-unstable-2025";
    src = pkgs.fetchFromGitHub {
      owner = "alexandergknoll";
      repo  = "nirimap";
      rev   = "main";
      hash  = "sha256-0LqLUKrX9hIWPyANmUr3mTqws+E9n1l1jffXz+LNwrQ=";
    };
    cargoHash        = "sha256-aDeMZ9WyuMNRcCgxGBmMJvPQeMqXd9Eppsesb+vUKZA=";
    nativeBuildInputs = with pkgs; [ pkg-config wrapGAppsHook4 ];
    buildInputs       = with pkgs; [ gtk4 gtk4-layer-shell ];
    meta = {
      description = "Workspace minimap overlay for the Niri Wayland compositor";
      homepage    = "https://github.com/alexandergknoll/nirimap";
      license     = pkgs.lib.licenses.mit;
      mainProgram = "nirimap";
    };
  };

  # ── niri-session-manager ───────────────────────────────────────────────────
  niri-session-manager = pkgs.rustPlatform.buildRustPackage {
    pname   = "niri-session-manager";
    version = "0-unstable-2025";
    src = pkgs.fetchFromGitHub {
      owner = "MTeaHead";
      repo  = "niri-session-manager";
      rev   = "main";
      hash  = "sha256-5itrK5V9ZHGKIjKODTcneAanvs021Bk0CBJxBYRPaMs=";
    };
    cargoHash = "sha256-79ynRnPJ1i+qRYJIa9Wmb6qKUbO2rDnLp7WcunX7y5U=";
    meta = {
      description = "Automatically save and restore windows in the Niri Wayland compositor";
      homepage    = "https://github.com/MTeaHead/niri-session-manager";
      license     = pkgs.lib.licenses.gpl3Only;
      mainProgram = "niri-session-manager";
    };
  };

  stasis = pkgs.stasis;

  # ── niri-single-max ────────────────────────────────────────────────────────
  niri-single-max = pkgs.writeShellScriptBin "niri-single-max" ''
    MAXIMIZED_WS=""
    OVERRIDE_DIR="''${XDG_RUNTIME_DIR:-/tmp}/niri-single-max-overrides"
    mkdir -p "$OVERRIDE_DIR"

    is_maximized()     { echo " $MAXIMIZED_WS " | grep -qF " $1 "; }
    mark_maximized()   { MAXIMIZED_WS="$MAXIMIZED_WS $1"; }
    unmark_maximized() { MAXIMIZED_WS=$(echo "$MAXIMIZED_WS" | tr ' ' '\n' | grep -vxF "$1" | tr '\n' ' '); }
    is_override()      { [ -f "$OVERRIDE_DIR/$1" ]; }
    set_override()     { touch "$OVERRIDE_DIR/$1"; }
    clear_override()   { rm -f "$OVERRIDE_DIR/$1"; }

    ${niri-pkg}/bin/niri msg --json event-stream | \
    ${pkgs.jq}/bin/jq --unbuffered -c '
      if has("WindowOpenedOrChanged") then
        { type: "change", window: .WindowOpenedOrChanged.window }
      elif has("WindowClosed") then
        { type: "close", id: .WindowClosed.id }
      else null end
    ' | while IFS= read -r event; do
      [ "$event" = "null" ] && continue

      TYPE=$(printf '%s' "$event" | ${pkgs.jq}/bin/jq -r '.type')

      if [ "$TYPE" = "change" ]; then
        WID=$(printf '%s'      "$event" | ${pkgs.jq}/bin/jq -r '.window.id')
        WSID=$(printf '%s'     "$event" | ${pkgs.jq}/bin/jq -r '.window.workspace_id // empty')
        FLOATING=$(printf '%s' "$event" | ${pkgs.jq}/bin/jq -r '.window.is_floating')

        [ -z "$WSID" ] && continue
        [ "$WSID" = "null" ] && continue
        [ "$FLOATING" = "true" ] && continue
        is_override "$WSID" && continue

        COUNT=$(${niri-pkg}/bin/niri msg --json windows \
          | ${pkgs.jq}/bin/jq --argjson ws "$WSID" \
            '[.[] | select(.workspace_id == $ws and (.is_floating == false))] | length')

        case "$COUNT" in
          1)
            if ! is_maximized "$WSID"; then
              ${niri-pkg}/bin/niri msg action maximize-column --id "$WID" 2>/dev/null || true
              mark_maximized "$WSID"
            fi
            ;;
          2)
            unmark_maximized "$WSID"
            clear_override "$WSID"
            ${niri-pkg}/bin/niri msg --json windows \
              | ${pkgs.jq}/bin/jq --argjson ws "$WSID" \
                '[.[] | select(.workspace_id == $ws and .is_floating == false) | .id][]' \
              | while IFS= read -r id; do
                  ${niri-pkg}/bin/niri msg action set-column-width --id "$id" "50%" 2>/dev/null || true
                done
            ;;
        esac

      elif [ "$TYPE" = "close" ]; then
        ${niri-pkg}/bin/niri msg --json windows \
          | ${pkgs.jq}/bin/jq -c '
              group_by(.workspace_id)
              | .[]
              | { ws: (.[0].workspace_id | tostring),
                  tiled: [.[] | select(.is_floating == false)] }
              | select((.tiled | length) == 1)
              | { ws: .ws, id: .tiled[0].id }
            ' \
          | while IFS= read -r ws_info; do
              LONE_WS=$(printf '%s' "$ws_info" | ${pkgs.jq}/bin/jq -r '.ws')
              LONE_ID=$(printf '%s' "$ws_info" | ${pkgs.jq}/bin/jq -r '.id')
              clear_override "$LONE_WS"
              if ! is_maximized "$LONE_WS"; then
                ${niri-pkg}/bin/niri msg action maximize-column --id "$LONE_ID" 2>/dev/null || true
                mark_maximized "$LONE_WS"
              fi
            done
      fi
    done
  '';

  # ── niri-steam-notif ───────────────────────────────────────────────────────
  niri-steam-notif = pkgs.writeShellScriptBin "niri-steam-notif" ''
    DELAY=6
    declare -A SEEN

    ${niri-pkg}/bin/niri msg --json event-stream | \
    ${pkgs.jq}/bin/jq --unbuffered -c '
      if has("WindowOpenedOrChanged") then
        .WindowOpenedOrChanged.window
        | select(.title != null and (.title | test("^notificationtoasts_[0-9]+_desktop$")))
        | { id: .id, title: .title }
      else null end
    ' | while IFS= read -r event; do
      [ "$event" = "null" ] && continue
      WID=$(printf '%s' "$event" | ${pkgs.jq}/bin/jq -r '.id')
      [ -z "$WID" ] && continue
      [ "''${SEEN[$WID]+x}" ] && continue
      SEEN[$WID]=1
      (
        sleep "$DELAY"
        ${niri-pkg}/bin/niri msg action close-window --id "$WID" 2>/dev/null || true
      ) &
    done
  '';

  # ── waybar-wrapper ─────────────────────────────────────────────────────────
  waybar-wrapper = pkgs.writeShellScriptBin "waybar-wrapper" ''
    ${pkgs.waybar}/bin/waybar "$@" &
    WAYBAR_PID=$!

    _stop() {
      OVERRIDE="$HOME/.config/waybar/fadeout-override.css"
      printf 'window#waybar { opacity: 0; transition: opacity 0.4s ease; }\n' > "$OVERRIDE"
      kill -SIGUSR2 "$WAYBAR_PID" 2>/dev/null || true
      sleep 0.15
      sleep 0.45
      rm -f "$OVERRIDE"
      kill "$WAYBAR_PID" 2>/dev/null || true
      wait "$WAYBAR_PID" 2>/dev/null || true
    }

    trap _stop TERM INT
    wait "$WAYBAR_PID"
  '';

  # ── taskcli-sidebar-launch ─────────────────────────────────────────────────
  taskcli-sidebar-launch = pkgs.writeShellScriptBin "taskcli-sidebar-launch" ''
    ${pkgs.kitty}/bin/kitty \
      --class taskcli-sidebar \
      --title "Task CLI" \
      --override background_opacity=0.88 \
      -e taskcli today &

    for i in $(seq 1 20); do
      ${niri-sidebar}/bin/niri-sidebar list-windows >/dev/null 2>&1 && break
      sleep 0.3
    done

    for i in $(seq 1 30); do
      WID=$(${niri-pkg}/bin/niri msg -j windows 2>/dev/null \
        | ${pkgs.jq}/bin/jq -r '.[] | select(.app_id == "taskcli-sidebar") | .id' \
        | head -1)
      [ -n "$WID" ] && break
      sleep 0.2
    done

    if [ -n "$WID" ]; then
      ${niri-pkg}/bin/niri msg action focus-window --id "$WID"
      sleep 0.1
      ${niri-sidebar}/bin/niri-sidebar toggle-window
    fi
  '';

  # ── ndrop ──────────────────────────────────────────────────────────────────
  ndrop = pkgs.writeShellScriptBin "ndrop" ''
    CLASS=""
    FOCUS_ONLY=false
    INSENSITIVE=false

    while [ "$#" -gt 0 ]; do
      case "$1" in
        -c|--class)      CLASS="$2"; shift 2 ;;
        -F|--focus)      FOCUS_ONLY=true; shift ;;
        -i|--insensitive) INSENSITIVE=true; shift ;;
        *) break ;;
      esac
    done

    CMD="$1"; shift
    [ -z "$CLASS" ] && CLASS="$CMD"

    if $INSENSITIVE; then
      WID=$(${niri-pkg}/bin/niri msg -j windows 2>/dev/null \
        | ${pkgs.jq}/bin/jq -r --arg c "$CLASS" \
          '.[] | select(.app_id | ascii_downcase | contains($c | ascii_downcase)) | .id' \
        | head -1)
    else
      WID=$(${niri-pkg}/bin/niri msg -j windows 2>/dev/null \
        | ${pkgs.jq}/bin/jq -r --arg c "$CLASS" \
          '.[] | select(.app_id == $c) | .id' \
        | head -1)
    fi

    CURRENT_WS=$(${niri-pkg}/bin/niri msg -j workspaces 2>/dev/null \
      | ${pkgs.jq}/bin/jq -r '.[] | select(.is_focused == true) | .name // (.idx | tostring)' \
      | head -1)

    if [ -n "$WID" ]; then
      WIN_WS=$(${niri-pkg}/bin/niri msg -j windows 2>/dev/null \
        | ${pkgs.jq}/bin/jq -r --argjson id "$WID" \
          '.[] | select(.id == $id) | .workspace_id | tostring' \
        | head -1)
      NDROP_WS_ID=$(${niri-pkg}/bin/niri msg -j workspaces 2>/dev/null \
        | ${pkgs.jq}/bin/jq -r '.[] | select(.name == "ndrop") | .id | tostring' \
        | head -1)

      if [ "$WIN_WS" = "$NDROP_WS_ID" ]; then
        ${niri-pkg}/bin/niri msg action move-window-to-workspace --id "$WID" "$CURRENT_WS" 2>/dev/null
        sleep 0.05
        ${niri-pkg}/bin/niri msg action focus-window --id "$WID" 2>/dev/null
      elif $FOCUS_ONLY; then
        ${niri-pkg}/bin/niri msg action focus-window --id "$WID" 2>/dev/null
      else
        ${niri-pkg}/bin/niri msg action move-window-to-workspace --id "$WID" ndrop 2>/dev/null
      fi
    else
      ${niri-pkg}/bin/niri msg action spawn -- "$CMD" "$@" 2>/dev/null
    fi
  '';

  nirimapConfigTemplate = pkgs.writeText "nirimap-config.toml" ''
    [display]
    height            = 36
    max_width_percent = 0.55
    anchor            = "bottom-center"
    margin_x          = 0
    margin_y          = 0

    [appearance]
    background         = "{{colors.surface.default.hex}}"
    window_color       = "{{colors.surface_variant.default.hex}}"
    focused_color      = "{{colors.primary.default.hex}}"
    border_color       = "{{colors.surface.default.hex}}"
    border_width       = 0
    border_radius      = 0
    gap                = 0
    background_opacity = 0.88

    [behavior]
    always_visible  = false
    hide_timeout_ms = 800

    [layer]
    shell_layer = "overlay"
  '';

  niriTemplate = pkgs.writeText "niri-template.kdl" ''
    layout {
      focus-ring {
        width 2
        active-gradient from="{{colors.primary.default.hex}}" to="{{colors.tertiary.default.hex}}" angle=45
        inactive-gradient from="{{colors.surface_variant.default.hex}}" to="{{colors.outline_variant.default.hex}}" angle=45
      }
      border {
        width 2
        active-gradient from="{{colors.primary.default.hex}}60" to="{{colors.tertiary.default.hex}}60" angle=45
        inactive-gradient from="{{colors.surface_variant.default.hex}}30" to="{{colors.outline_variant.default.hex}}30" angle=45
      }
    }
  '';

in
{
  # Conditionally import DE‑agnostic modules
  imports = [
    ../../../wallpaper-manager/wallpaper.nix
    ../../../other/wayland/matugen.nix
    ../../../other/theming.nix
    ../../../notifications/notifications.nix
    ../../../lock-screen/swaylock.nix
  ];

  config = lib.mkIf isNiri {

    # ── niri package ─────────────────────────────────────────────────────────
    programs.niri.enable  = true;
    programs.niri.package = niri-pkg;

    # ── XWayland (required for Steam, Discord, many games) ───────────────────
    programs.xwayland.enable = true;

    systemd.user.services.xwayland-satellite = {
      description = "Standalone XWayland server for niri";
      wantedBy    = [ "graphical-session.target" ];
      partOf      = [ "graphical-session.target" ];
      after       = [ "graphical-session.target" ];
      serviceConfig = {
        Type         = "notify";
        NotifyAccess = "all";
        ExecStart    = "${pkgs.xwayland-satellite}/bin/xwayland-satellite :0";
        Restart      = "on-failure";
        RestartSec   = "2s";
        ExecStartPost = [
          "${pkgs.systemd}/bin/systemctl --user set-environment DISPLAY=:0"
          "${pkgs.dbus}/bin/dbus-update-activation-environment --systemd DISPLAY=:0"
        ];
      };
    };

    # ── XDG portals ──────────────────────────────────────────────────────────
    xdg.portal = {
      enable       = true;
      extraPortals = [ pkgs.xdg-desktop-portal-gnome ];
      config.common.default = "*";
    };

    services.dbus.enable = true;

    systemd.user.services.stasis = {
      description = "Stasis — media-aware Wayland idle manager";
      wantedBy    = [ "graphical-session.target" ];
      partOf      = [ "graphical-session.target" ];
      after       = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart  = "${stasis}/bin/stasis --config /etc/stasis/stasis.rune";
        Restart    = "on-failure";
        RestartSec = 2;
      };
    };

    # ── niri-steam-notif ──────────────────────────────────────────────────────
    systemd.user.services.niri-steam-notif = {
      description = "Auto-close Steam friend notification popups";
      wantedBy    = [ "graphical-session.target" ];
      partOf      = [ "graphical-session.target" ];
      after       = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart  = "${niri-steam-notif}/bin/niri-steam-notif";
        Restart    = "on-failure";
        RestartSec = 2;
      };
    };

    # ── niri-session-manager ──────────────────────────────────────────────────
    systemd.user.services.niri-session-manager = {
      description = "Niri session manager — periodic save and restore on login";
      wantedBy    = [ "graphical-session.target" ];
      partOf      = [ "graphical-session.target" ];
      after       = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart  = "${niri-session-manager}/bin/niri-session-manager --save-interval 15 --max-backup-count 5";
        Restart    = "on-failure";
        RestartSec = 3;
      };
    };

    # ── ASUS laptop support ───────────────────────────────────────────────────
    services.asusd = lib.mkIf config.global.asusLaptop {
      enable            = true;
      enableUserService = true;
    };

    systemd.user.services.wp-rgb-boot = lib.mkIf config.global.asusLaptop {
      description = "Apply ASUS keyboard RGB from current wallpaper";
      wantedBy    = [ "graphical-session.target" ];
      after       = [ "graphical-session.target" ];
      serviceConfig = {
        Type      = "oneshot";
        ExecStart = pkgs.writeShellScript "wp-rgb-boot" ''
          LAST_WP_FILE="/home/${username}/.local/share/last_wallpaper.txt"
          [ -f "$LAST_WP_FILE" ] || exit 0
          read -r WP _ < "$LAST_WP_FILE"
          [ -f "$WP" ] || exit 0
          exec wp-rgb "$WP"
        '';
      };
    };

    # ── Disable GNOME / GDM ───────────────────────────────────────────────────
    services.desktopManager.gnome.enable  = lib.mkForce false;
    services.displayManager.gdm.enable    = lib.mkForce false;
    gtk.iconCache.enable = false; # makes rebuilds faster

    # ── niri-sidebar config ───────────────────────────────────────────────────
    environment.etc."xdg/niri-sidebar/config.toml".text = ''
      [geometry]
      width  = 420
      height = 800
      gap    = 10

      [margins]
      top   = 50
      right = 10

      [interaction]
      peek       = 2
      focus_peek = 430
    '';

    # ── Matugen: niri-specific template entries (appended to matugen.nix base) ─
    environment.etc."matugen/templates/niri.kdl".source            = niriTemplate;
    environment.etc."matugen/templates/nirimap-config.toml".source = nirimapConfigTemplate;

    # ── Activation: niri-session-manager default config ───────────────────────
    system.activationScripts.niri-session-manager-config = {
      text = ''
        NSM_CFG="/home/${username}/.config/niri-session-manager/config.toml"
        if [ ! -f "$NSM_CFG" ]; then
          mkdir -p "$(dirname "$NSM_CFG")"
          cat > "$NSM_CFG" << 'EOF'
# niri-session-manager configuration

[single_instance_apps]
apps = [ "firefox", "zen", "org.mozilla.firefox" ]

[skip_apps]
apps = [ "taskcli-sidebar", "nirimap" ]

[app_mappings]
"org.kde.dolphin"       = ["dolphin"]
"org.kde.konsole"       = ["kitty"]
"com.mitchellh.ghostty" = ["ghostty"]
EOF
          chown ${username}:users "$NSM_CFG"
        fi
      '';
    };

    # ── Activation: niri matugen placeholder ──────────────────────────────────
    system.activationScripts.matugen-placeholder-niri = {
      text = ''
        mkdir -p /home/${username}/.cache/matugen
        if [ ! -f /home/${username}/.cache/matugen/niri-colors.kdl ]; then
          echo "// Placeholder" > /home/${username}/.cache/matugen/niri-colors.kdl
          chown ${username}:users /home/${username}/.cache/matugen/niri-colors.kdl
        fi
        mkdir -p /home/${username}/.config/nirimap
        if [ ! -f /home/${username}/.config/nirimap/config.toml ]; then
          echo "" > /home/${username}/.config/nirimap/config.toml
          chown -R ${username}:users /home/${username}/.config/nirimap
        fi
      '';
    };

    # ── Packages ──────────────────────────────────────────────────────────────
    environment.systemPackages = with pkgs; [
      niri-sidebar
      nirimap
      niri-single-max
      niri-steam-notif
      niri-session-manager
      taskcli-sidebar-launch
      ndrop
      waybar-wrapper
      waybar
      xwayland-satellite
      xdg-desktop-portal-gnome
      stasis
      fastfetch
      networkmanagerapplet
      pavucontrol
      brightnessctl
      pamixer
      htop
      grim
    ];

    environment.sessionVariables = {
      NIXOS_OZONE_WL = "1";
      XCURSOR_THEME  = "Bibata-Modern-Classic";
      XCURSOR_SIZE   = "24";
      DISPLAY        = ":0";
    };

    # ── Waybar config ─────────────────────────────────────────────────────────
    environment.etc."xdg/waybar/config".text = builtins.toJSON {
      layer    = "top";
      position = "bottom";
      height   = 36;
      exclusive-zone = 0;
      margin-top    = 5;
      margin-left   = 10;
      margin-right  = 10;
      margin-bottom = 5;
      spacing = 4;

      modules-left   = [ "niri/workspaces" "niri/window" ];
      modules-center = [ "clock" ];
      modules-right  = [ "cpu" "memory" "pulseaudio" "network" "custom/airplane" "battery" "custom/bluelight" "custom/mode" "custom/wallpaper" "tray" ];

      "niri/workspaces" = {
        format = "{icon}";
        format-icons = { default = "○"; active = "●"; urgent = "⬤"; };
        on-click = "activate";
      };

      "niri/window" = { max-length = 40; separate-outputs = true; };

      "clock" = {
        format     = "󰥔 {:%H:%M}";
        format-alt = "󰃭 {:%a, %d %b %Y}";
        actions    = { on-click-right = "mode"; on-scroll-up = "shift_up"; on-scroll-down = "shift_down"; };
      };

      "pulseaudio" = {
        format        = "{icon} {volume}%";
        format-muted  = "󰝟 muted";
        format-icons  = { default = [ "󰕿" "󰖀" "󰕾" ]; };
        on-click      = "${pkgs.pavucontrol}/bin/pavucontrol";
        on-scroll-up  = "${pkgs.pamixer}/bin/pamixer -i 2";
        on-scroll-down = "${pkgs.pamixer}/bin/pamixer -d 2";
        tooltip-format = "{desc}";
        scroll-step   = 2;
      };

      "network" = {
        format-wifi       = "󰤨 {essid}";
        format-ethernet   = "󰈀 {ifname}";
        format-disconnected = "󰤭 disconnected";
        tooltip-format-wifi = "󰤨 {essid}\nSignal: {signalStrength}%\nFreq: {frequency} GHz\n⬆ {bandwidthUpBits}  ⬇ {bandwidthDownBits}";
        tooltip-format-ethernet = "󰈀 {ifname}\n⬆ {bandwidthUpBits}  ⬇ {bandwidthDownBits}";
        tooltip-format-disconnected = "No network";
        interval = 5;
        on-click = "${pkgs.networkmanagerapplet}/bin/nm-connection-editor";
      };

      "custom/airplane" = {
        exec        = "airplane-ctl status";
        return-type = "json";
        interval    = 5;
        on-click    = "airplane-ctl toggle";
      };

      "battery" = {
        states         = { warning = 30; critical = 15; };
        format         = "{icon} {capacity}%";
        format-charging = "󰂄 {capacity}%";
        format-plugged  = "󰚥 {capacity}%";
        format-full     = "󰁹 full";
        format-icons    = [ "󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹" ];
        tooltip-format  = "{timeTo}\n{power}W";
      };

      "cpu" = {
        interval       = 3;
        format         = "󰻠 {usage}%";
        tooltip-format = "CPU: {usage}%\nLoad: {load}";
        on-click       = "${pkgs.kitty}/bin/kitty -e htop";
      };

      "memory" = {
        interval       = 10;
        format         = "󰍛 {percentage}%";
        tooltip-format = "RAM: {used:0.1f}G / {total:0.1f}G\nSwap: {swapUsed:0.1f}G / {swapTotal:0.1f}G";
        on-click       = "${pkgs.kitty}/bin/kitty -e htop";
      };

      "custom/bluelight" = {
        exec        = "bluelight-ctl status";
        return-type = "json";
        interval    = 2;
        on-click    = "bluelight-ctl toggle";
        on-scroll-up   = "bluelight-ctl up";
        on-scroll-down = "bluelight-ctl down";
      };

      "custom/mode" = {
        exec        = "wp-mode status";
        return-type = "json";
        interval    = 5;
        on-click    = "wp-mode cycle";
        on-click-right = "wp-mode silent";
        tooltip     = true;
      };

      "tray" = { icon-size = 14; spacing = 6; show-passive-items = true; };
    };

    # ── Kitty config ──────────────────────────────────────────────────────────
    environment.etc."xdg/kitty/kitty.conf".text = ''
      font_family      JetBrainsMono Nerd Font
      font_size        13.0
      bold_font        auto
      italic_font      auto
      bold_italic_font auto

      window_padding_width 16

      background_opacity    0.82

      cursor_shape          beam
      cursor_blink_interval 0.5

      scrollback_lines      10000

      tab_bar_style         powerline
      tab_powerline_style   slanted
      tab_bar_edge          bottom

      hide_window_decorations yes
      confirm_os_window_close 0

      shell_integration enabled

      allow_remote_control yes
      listen_on unix:/tmp/kitty-matugen

      include /home/${username}/.config/kitty/colors.conf
    '';

    # ── GameMode ──────────────────────────────────────────────────────────────
    programs.gamemode.enable = true;

    # ── Niri KDL config ───────────────────────────────────────────────────────
    environment.etc."niri/config.kdl".text = ''
      include "/home/${username}/.cache/matugen/niri-colors.kdl"
      include "${./config/animations.kdl}"
      include "${./config/keybinds.kdl}"
      include "${./config/window-rules.kdl}"

      spawn-at-startup "${waybar-wrapper}/bin/waybar-wrapper"
      spawn-at-startup "${pkgs.swww}/bin/swww-daemon"
      spawn-sh-at-startup "bluelight-ctl restore"
      spawn-at-startup "swaync"
      spawn-at-startup "${pkgs.swayosd}/bin/swayosd-server"
      spawn-at-startup "${niri-sidebar}/bin/niri-sidebar" "listen"
      spawn-at-startup "${taskcli-sidebar-launch}/bin/taskcli-sidebar-launch"
      spawn-at-startup "${nirimap}/bin/nirimap"
      spawn-at-startup "${niri-single-max}/bin/niri-single-max"
      spawn-sh-at-startup "sh -c sleep 0.5 && niri msg action focus-workspace 1"

      input {
          touchpad {
              tap
              natural-scroll
          }
      }

      workspace "ndrop"

      layout {
          gaps 16
          background-color "transparent"

          struts {
              top    0
              left   4
              right  4
              bottom 0
          }

          preset-column-widths {
              proportion 0.33333
              proportion 0.5
              proportion 0.66667
          }

          default-column-width { proportion 0.5; }
      }

      layer-rule {
          match namespace="^swww-daemon$"
          place-within-backdrop true
      }

      layer-rule {
          match namespace="^launcher$"
          geometry-corner-radius 12
          ${if blur then "shadow { on softness 25 spread 4 offset x=0 y=6 color \"#00000055\" }" else ""}
      }

      layer-rule {
          match namespace="^nirimap$"
          geometry-corner-radius 10
          ${if blur then "shadow { on softness 20 spread 2 offset x=0 y=4 color \"#00000066\" }" else ""}
      }

      ${if blur then "window-rule { match app-id=\"^kitty$\"; opacity 1.0; draw-border-with-background false }" else ""}

      prefer-no-csd
    '';

  };
}
