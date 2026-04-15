# notifications.nix
#
# Notification daemon (SwayNC), OSD (SwayOSD), blue-light filter,
# and airplane mode control. All Wayland-compositor-agnostic.
#
# Provides:
#   swaynotificationcenter   notification daemon + control center
#   swayosd                  volume/brightness OSD popup
#   bluelight-ctl            wlsunset wrapper with persistent state
#   airplane-ctl             rfkill wrapper with waybar JSON output
#
# Systemd units:
#   swayosd                  OSD server (picks up matugen CSS on restart)
#
# Place at: /etc/nixos/notifications.nix
# Import in: configuration.nix

{ config, pkgs, lib, ... }:

let
  username = config.global.user;

  # ── bluelight-ctl ──────────────────────────────────────────────────────────
  bluelight-ctl = pkgs.writeShellScriptBin "bluelight-ctl" ''
    STATE_DIR="/home/${username}/.local/share/bluelight"
    STATE_FILE="$STATE_DIR/state"
    TEMP_MIN=2500
    TEMP_MAX=6500
    TEMP_STEP=100

    mkdir -p "$STATE_DIR"

    if [ -f "$STATE_FILE" ]; then
      ENABLED=$(grep '^enabled=' "$STATE_FILE" | cut -d= -f2)
      TEMP=$(grep    '^temp='    "$STATE_FILE" | cut -d= -f2)
    fi
    ENABLED=''${ENABLED:-0}
    TEMP=''${TEMP:-3400}

    save_state() { printf 'enabled=%s\ntemp=%s\n' "$ENABLED" "$TEMP" > "$STATE_FILE"; }

    apply() {
      pkill -x wlsunset 2>/dev/null || true
      if [ "$ENABLED" = "1" ]; then
        ${pkgs.wlsunset}/bin/wlsunset -t "$TEMP" -T "$((TEMP + 1))" &
        disown
      fi
    }

    case "''${1:-status}" in
      restore) [ "$ENABLED" = "1" ] && apply || true ;;
      toggle)
        if [ "$ENABLED" = "1" ]; then ENABLED=0; else ENABLED=1; fi
        save_state; apply ;;
      on)   ENABLED=1; save_state; apply ;;
      off)  ENABLED=0; save_state; apply ;;
      up)
        TEMP=$(( TEMP + TEMP_STEP ))
        [ "$TEMP" -gt "$TEMP_MAX" ] && TEMP=$TEMP_MAX
        save_state
        [ "$ENABLED" = "1" ] && apply ;;
      down)
        TEMP=$(( TEMP - TEMP_STEP ))
        [ "$TEMP" -lt "$TEMP_MIN" ] && TEMP=$TEMP_MIN
        save_state
        [ "$ENABLED" = "1" ] && apply ;;
      status)
        if [ "$ENABLED" = "1" ]; then
          ICON="󰛨"; CLASS="active"; LABEL="$ICON ''${TEMP}K"
        else
          ICON="󰛩"; CLASS="inactive"; LABEL="$ICON"
        fi
        printf '{"text":"%s","tooltip":"Blue light filter: %s\\nTemp: %sK\\nScroll to adjust, click to toggle","class":"%s"}\n' \
          "$LABEL" \
          "$([ "$ENABLED" = "1" ] && echo "on" || echo "off")" \
          "$TEMP" "$CLASS"
        ;;
      *) echo "Usage: bluelight-ctl [toggle|on|off|up|down|restore|status]" >&2; exit 1 ;;
    esac
  '';

  # ── airplane-ctl ───────────────────────────────────────────────────────────
  airplane-ctl = pkgs.writeShellScriptBin "airplane-ctl" ''
    STATE_DIR="/home/${username}/.local/share/airplane"
    mkdir -p "$STATE_DIR"
    LOCKFILE="$STATE_DIR/lock"

    get_status() {
      if ${pkgs.util-linux}/bin/rfkill list | grep -q "Soft blocked: no"; then
        echo "off"
      else
        echo "on"
      fi
    }

    case "''${1:-status}" in
      toggle)
        (
          flock -x 200
          STATUS=$(get_status)
          if [ "$STATUS" = "on" ]; then
            ${pkgs.util-linux}/bin/rfkill unblock all
            notify-send -u low -t 1500 "Airplane Mode" "Off (radios enabled)"
          else
            ${pkgs.util-linux}/bin/rfkill block all
            notify-send -u low -t 1500 "Airplane Mode" "On (all radios disabled)"
          fi
        ) 200>"$LOCKFILE"
        ;;
      on)
        ${pkgs.util-linux}/bin/rfkill block all
        notify-send -u low -t 1500 "Airplane Mode" "On"
        ;;
      off)
        ${pkgs.util-linux}/bin/rfkill unblock all
        notify-send -u low -t 1500 "Airplane Mode" "Off"
        ;;
      status)
        STATUS=$(get_status)
        if [ "$STATUS" = "on" ]; then
          printf '{"text":"✈","tooltip":"Airplane mode is ON","class":"airplane-on"}\n'
        else
          printf '{"text":"✈","tooltip":"Airplane mode is OFF","class":"airplane-off"}\n'
        fi
        ;;
      *) echo "Usage: airplane-ctl [toggle|on|off|status]" >&2; exit 1 ;;
    esac
  '';

in
{
  environment.systemPackages = with pkgs; [
    swaynotificationcenter
    libnotify
    swayosd
    wlsunset
    util-linux
    bluelight-ctl
    airplane-ctl
  ];

  # ── SwayOSD systemd service ────────────────────────────────────────────────
  # Reads its CSS from the matugen cache so colours update with each wallpaper.
  systemd.user.services.swayosd = {
    description = "SwayOSD — volume/brightness OSD";
    wantedBy    = [ "graphical-session.target" ];
    partOf      = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart  = "${pkgs.swayosd}/bin/swayosd-server --style /home/${username}/.cache/matugen/swayosd.css";
      Restart    = "on-failure";
      RestartSec = 1;
    };
  };
}
