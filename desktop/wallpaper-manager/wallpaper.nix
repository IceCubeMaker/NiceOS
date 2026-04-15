# wallpaper.nix
#
# Self-contained wallpaper management system.
# Works under any Wayland compositor (niri, sway, Hyprland, etc.).
#
# Provides:
#   wp-change        context-aware wallpaper picker (weather + time + colour prefs)
#   wp-bank          bank viewing duration on session end
#   wp-analyze       extract colour metadata from wallpaper images
#   wp-tag           AI-tag a single wallpaper with WD14 tagger
#   wp-tag-untagged  batch-tag all untagged wallpapers
#   wp-fetch         download wallpapers from Wallhaven (preference-guided)
#   wp-prefs         show learned preference summary
#   wp-mode          cycle system mode (silent / balanced / performance)
#   wp-sync-greeter  sync current wallpaper + matugen palette to greeter cache
#   wp-rgb           set ASUS TUF keyboard RGB from matugen primary color
#   swaylock-themed  themed swaylock-effects wrapper (catppuccin mocha)
#
# Systemd units:
#   wallpaper-banker         banks duration on logout (oneshot, RemainAfterExit)
#   wallpaper-banker-timer   periodic bank every 1h
#   wp-tag-untagged          daily batch tagger
#   wp-tag-watcher           inotify watcher — tags new wallpapers immediately
#
# NOTE: wp-change calls `niri msg action load-config-file` and
#       `niri msg action power-off/on-monitors`. Those are safe no-ops if niri
#       isn't running (the binary simply returns an error that is suppressed).
#       If you run this under a different compositor, replace those calls
#       with the equivalent for your WM.

{ config, pkgs, lib, ... }:

let
  username = config.global.user;

  # ── WD14 tagger model + labels ─────────────────────────────────────────────
  wd14-labels = pkgs.fetchurl {
    url  = "https://huggingface.co/SmilingWolf/wd-v1-4-vit-tagger-v2/resolve/main/selected_tags.csv";
    hash = "sha256-jIdQYA2zYjOhsnSsiL1GKJ5YizOCGMLkxiu8nytRY2g=";
  };

  wd14-model = pkgs.stdenv.mkDerivation {
    name = "wd14-tagger-model";
    src  = pkgs.fetchurl {
      url  = "https://huggingface.co/SmilingWolf/wd-v1-4-vit-tagger-v2/resolve/main/model.onnx";
      hash = "sha256-iiHK3R+IoJUJTK+//jAow8w9l/TVjFQ0TFmUvPSOJKw=";
    };
    dontUnpack   = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp "$src" "$out/model.onnx"
      runHook postInstall
    '';
  };

  # ── wp-tag ─────────────────────────────────────────────────────────────────
  wp-tag = let
    pythonEnv = pkgs.python3.withPackages (ps: with ps; [
      numpy onnxruntime pillow
    ]);
  in pkgs.writeShellScriptBin "wp-tag" ''
    exec ${pythonEnv}/bin/python3 -c '
    import sys, os, csv
    import numpy as np
    from PIL import Image
    import onnxruntime as ort

    MODEL_PATH  = "${wd14-model}/model.onnx"
    LABELS_PATH = "${wd14-labels}"
    TAG_FILE    = os.path.expanduser("~/.local/share/wallpaper_tags.tsv")

    def load_labels():
        with open(LABELS_PATH, "r") as f:
            reader = csv.reader(f)
            next(reader)
            return [row for row in reader]

    def preprocess(image_path):
        img = Image.open(image_path).convert("RGB")
        img = img.resize((448, 448), Image.LANCZOS)
        img = np.array(img).astype(np.float32)
        return np.expand_dims(img, axis=0)

    def get_tags(image_path, threshold=0.25):
        session    = ort.InferenceSession(MODEL_PATH, providers=["CPUExecutionProvider"])
        input_name = session.get_inputs()[0].name
        all_labels = load_labels()
        img_tensor = preprocess(image_path)
        probs      = session.run(None, {input_name: img_tensor})[0][0]
        tags = {}
        for i, prob in enumerate(probs):
            if i < len(all_labels) and all_labels[i][2] in ["0", "9"] and prob >= threshold:
                tags[all_labels[i][1]] = float(prob)
        return tags

    def update_tag_file(image_path, tags):
        os.makedirs(os.path.dirname(TAG_FILE), exist_ok=True)
        abs_path = os.path.abspath(image_path)
        existing = []
        if os.path.exists(TAG_FILE):
            with open(TAG_FILE, "r") as f:
                for line in f:
                    if not line.startswith(abs_path + "\t") and line.rstrip("\n") != abs_path:
                        existing.append(line)
        line_parts = [abs_path]
        for tag, conf in tags.items():
            line_parts.extend([tag, f"{conf:.4f}"])
        existing.append("\t".join(line_parts) + "\n")
        with open(TAG_FILE, "w") as f:
            f.writelines(existing)

    if __name__ == "__main__":
        if len(sys.argv) < 2:
            sys.exit(1)
        img_path = sys.argv[1]
        if os.path.exists(img_path):
            detected = get_tags(img_path)
            update_tag_file(img_path, detected)
            print(f"Tagged {os.path.basename(img_path)} with {len(detected)} tags")
    ' "$@"
  '';

  # ── wp-tag-untagged ────────────────────────────────────────────────────────
  wp-tag-untagged = pkgs.writeShellScriptBin "wp-tag-untagged" ''
    TAGS_FILE="/home/${username}/.local/share/wallpaper_tags.tsv"
    WP_DIR="/home/${username}/Pictures/Wallpapers"

    mkdir -p "$(dirname "$TAGS_FILE")"
    touch "$TAGS_FILE"

    TMPLIST=$(mktemp)
    find "$WP_DIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
      | sort > "$TMPLIST"

    TOTAL=$(wc -l < "$TMPLIST")
    DONE=0
    SKIPPED=0

    while IFS= read -r IMG; do
      if ${pkgs.gawk}/bin/awk -v p="$IMG" 'index($0,p)==1{found=1;exit} END{exit !found}' "$TAGS_FILE" 2>/dev/null; then
        SKIPPED=$(( SKIPPED + 1 ))
        continue
      fi
      DONE=$(( DONE + 1 ))
      echo "Tagging ($DONE/$(( TOTAL - SKIPPED ))): $(basename "$IMG")" >&2
      nice -n 19 ${pkgs.util-linux}/bin/ionice -c 3 \
        ${wp-tag}/bin/wp-tag "$IMG"
    done < "$TMPLIST"

    rm -f "$TMPLIST"
    echo "Done. Tagged $DONE images, skipped $SKIPPED already-tagged." >&2
  '';

  # ── wp-analyze ─────────────────────────────────────────────────────────────
  wp-analyze = pkgs.writeShellScriptBin "wp-analyze" ''
    META_FILE="/home/${username}/.local/share/wallpaper_meta.tsv"
    WP_DIR="/home/${username}/Pictures/Wallpapers"
    mkdir -p "$(dirname "$META_FILE")"
    touch "$META_FILE"

    if [ "$1" = "--all" ]; then
        COUNT=0
        find "$WP_DIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) | while read -r IMG; do
            "$0" "$IMG" "$2"
            COUNT=$((COUNT+1))
        done
        ${pkgs.libnotify}/bin/notify-send -u low -t 3000 "Wallpaper Analyzer" "Analysis complete."
        exit 0
    fi

    if [ -n "$1" ]; then
        TARGET="$1"
    elif [ -f "/home/${username}/.local/share/last_wallpaper.txt" ]; then
        read -r TARGET _ < "/home/${username}/.local/share/last_wallpaper.txt"
    else
        echo "wp-analyze: no image specified and no current wallpaper found" >&2
        exit 1
    fi

    [ -f "$TARGET" ] || { echo "wp-analyze: file not found: $TARGET" >&2; exit 1; }

    if [ "$2" != "--force" ] && ${pkgs.gawk}/bin/awk -v p="$TARGET" '$1==p{found=1;exit} END{exit !found}' "$META_FILE"; then
        exit 0
    fi

    RAW=$(${pkgs.imagemagick}/bin/convert "$TARGET" -resize 64x64\! -colorspace HSL -channel R -separate +channel -format "%[fx:mean*360]" info: 2>/dev/null)
    HUE_DEG=$(printf '%.0f' "''${RAW:-180}")

    RAW=$(${pkgs.imagemagick}/bin/convert "$TARGET" -resize 64x64\! -colorspace HSL -channel G -separate +channel -format "%[fx:mean*100]" info: 2>/dev/null)
    SAT_PCT=$(printf '%.0f' "''${RAW:-50}")

    RAW=$(${pkgs.imagemagick}/bin/convert "$TARGET" -resize 64x64\! -colorspace HSL -channel B -separate +channel -format "%[fx:mean*100]" info: 2>/dev/null)
    BRIGHT_PCT=$(printf '%.0f' "''${RAW:-50}")

    RAW=$(${pkgs.imagemagick}/bin/convert "$TARGET" -resize 64x64\! -format "%[fx:(100*(channel.r.standard_deviation+channel.g.standard_deviation+channel.b.standard_deviation)/3)]" info: 2>/dev/null)
    COLORFUL_PCT=$(printf '%.0f' "''${RAW:-30}")
    [ "$COLORFUL_PCT" -lt 0 ] 2>/dev/null && COLORFUL_PCT=0
    [ "$COLORFUL_PCT" -gt 100 ] 2>/dev/null && COLORFUL_PCT=100

    ${pkgs.gnused}/bin/sed -i "\|^$TARGET\t|d" "$META_FILE"
    printf '%s\t%s\t%s\t%s\t%s\n' \
        "$TARGET" "$HUE_DEG" "$SAT_PCT" "$BRIGHT_PCT" "$COLORFUL_PCT" \
        >> "$META_FILE"
  '';

  # ── wp-prefs ───────────────────────────────────────────────────────────────
  wp-prefs = pkgs.writeShellScriptBin "wp-prefs" ''
    PREFS_FILE="/home/${username}/.local/share/wallpaper_prefs.txt"
    STATS_FILE="/home/${username}/.local/share/wallpaper_durations.txt"
    META_FILE="/home/${username}/.local/share/wallpaper_meta.tsv"
    TAG_PREFS_FILE="/home/${username}/.local/share/tag_prefs.txt"

    P_HUE=$(grep      '^pref_hue='      "$PREFS_FILE" 2>/dev/null | tail -1 | cut -d= -f2); P_HUE=''${P_HUE:-"(not yet learned)"}
    P_SAT=$(grep      '^pref_sat='      "$PREFS_FILE" 2>/dev/null | tail -1 | cut -d= -f2); P_SAT=''${P_SAT:-"(not yet learned)"}
    P_BRIGHT=$(grep   '^pref_bright='   "$PREFS_FILE" 2>/dev/null | tail -1 | cut -d= -f2); P_BRIGHT=''${P_BRIGHT:-"(not yet learned)"}
    P_COLORFUL=$(grep '^pref_colorful=' "$PREFS_FILE" 2>/dev/null | tail -1 | cut -d= -f2); P_COLORFUL=''${P_COLORFUL:-"(not yet learned)"}
    P_WEIGHT=$(grep   '^pref_weight='   "$PREFS_FILE" 2>/dev/null | tail -1 | cut -d= -f2); P_WEIGHT=''${P_WEIGHT:-0}
    AVG_SESSION=$(grep '^avg_session='  "$PREFS_FILE" 2>/dev/null | tail -1 | cut -d= -f2); AVG_SESSION=''${AVG_SESSION:-120}

    hue_name() {
        local h=$1
        if [ "$h" -lt 15 ] || [ "$h" -ge 345 ]; then echo "Red"
        elif [ "$h" -lt 45 ]; then echo "Orange"
        elif [ "$h" -lt 75 ]; then echo "Yellow"
        elif [ "$h" -lt 150 ]; then echo "Green"
        elif [ "$h" -lt 195 ]; then echo "Cyan"
        elif [ "$h" -lt 255 ]; then echo "Blue"
        elif [ "$h" -lt 285 ]; then echo "Violet"
        elif [ "$h" -lt 345 ]; then echo "Pink/Magenta"
        else echo "Unknown"; fi
    }

    AVG_MIN=$(${pkgs.gawk}/bin/awk -v s="$AVG_SESSION" 'BEGIN{printf "%.0f",s/60}')
    TOTAL_WP=$(wc -l < "$STATS_FILE" 2>/dev/null || echo 0)
    ANALYZED=$(wc -l < "$META_FILE"  2>/dev/null || echo 0)

    TOP5=$(${pkgs.gawk}/bin/awk 'NF>=12 && $12>0 {printf "%.0f %s (%dx)\n",$1/$12,$2,$12}' \
        "$STATS_FILE" 2>/dev/null | sort -rn | head -5 | \
        ${pkgs.gawk}/bin/awk '{printf "  %ds avg — %s %s\n",$1,$2,$3}')
    BOT5=$(${pkgs.gawk}/bin/awk 'NF>=12 && $12>=3 {printf "%.0f %s\n",$1/$12,$2}' \
        "$STATS_FILE" 2>/dev/null | sort -n | head -5 | \
        ${pkgs.gawk}/bin/awk '{printf "  %ds avg — %s\n",$1,$2}')

    TAG_COUNT=0; TOP_TAGS=""; BOT_TAGS=""
    if [ -s "$TAG_PREFS_FILE" ]; then
        TOP_TAGS=$(${pkgs.gawk}/bin/awk -F= 'index($1,"ctx_")==0 && $2+0>0 {printf "%+.2f %s\n",$2+0,$1}' \
            "$TAG_PREFS_FILE" | sort -rn | head -5)
        BOT_TAGS=$(${pkgs.gawk}/bin/awk -F= 'index($1,"ctx_")==0 && $2+0<0 {printf "%+.2f %s\n",$2+0,$1}' \
            "$TAG_PREFS_FILE" | sort -n  | head -5)
        TAG_COUNT=$(${pkgs.gawk}/bin/awk -F= 'index($1,"ctx_")==0' "$TAG_PREFS_FILE" | wc -l)
    fi

    CTX_SUMMARY=$(${pkgs.gawk}/bin/awk '
        /^ctx_.*_pref_weight=/ {
            n=index($0,"="); v=substr($0,n+1)+0; if(v==0) next
            key=$0; gsub(/=.*/,"",key); gsub(/^ctx_/,"",key); gsub(/_pref_weight$/,"",key)
            printf "    %-22s %d events\n", key, v
        }' "$PREFS_FILE" 2>/dev/null | sort)

    echo "══════════════════════════════════════════"
    echo "  Wallpaper Preference Profile"
    echo "  (learned passively from viewing time)"
    echo "══════════════════════════════════════════"
    echo "  Global learning events : $P_WEIGHT"
    echo "  Global avg session     : ~''${AVG_MIN}min"
    echo "  Tracked                : $TOTAL_WP wallpapers ($ANALYZED analysed)"
    echo ""
    echo "  ── Global colour preferences ──────────"
    echo "  Hue        : ''${P_HUE}° ($(hue_name ''${P_HUE%.*} 2>/dev/null || echo n/a))"
    echo "  Saturation : ''${P_SAT}%   (0=grey → 100=vivid)"
    echo "  Brightness : ''${P_BRIGHT}%   (0=dark → 100=bright)"
    echo "  Colorful   : ''${P_COLORFUL}%   (0=monotone → 100=varied)"
    echo ""
    echo "  ── Contextual slots ───────────────────"
    if [ -n "$CTX_SUMMARY" ]; then
        echo "$CTX_SUMMARY"
        echo "  Tip: run  wp-prefs <slot>  for detail"
        echo "       e.g. wp-prefs morning_clear"
    else
        echo "    None yet — keep using it!"
    fi
    echo ""
    echo "  ── Most-kept (avg view time) ──────────"
    echo "$TOP5"
    echo ""
    echo "  ── Most-skipped (>=3 shows) ───────────"
    echo "$BOT5"
    echo ""
    echo "  ── Global tag preferences (''${TAG_COUNT} tags) ──"
    if [ -n "$TOP_TAGS" ]; then
        echo "    Liked:";    echo "$TOP_TAGS" | while read -r line; do echo "      $line"; done
    fi
    if [ -n "$BOT_TAGS" ]; then
        echo "    Disliked:"; echo "$BOT_TAGS" | while read -r line; do echo "      $line"; done
    fi
    [ "$TAG_COUNT" -eq 0 ] && echo "    No tag preferences yet."
    echo ""
    echo "  ── How it works ───────────────────────"
    echo "    Keep a wallpaper longer than usual → prefs move TOWARD its look & tags"
    echo "    Skip it quickly                    → prefs move AWAY"
    echo "    Each tod×weather combo learns its  → own separate preference vector"
    echo "    own taste independently            → (morning_clear, night_rain, ...)"
    echo "    No buttons. Just use it."
    echo "══════════════════════════════════════════"

    if [ -n "$1" ]; then
        CTX_ARG="$1"
        C_WEIGHT=$(grep "^ctx_''${CTX_ARG}_pref_weight="   "$PREFS_FILE" 2>/dev/null | tail -1 | cut -d= -f2)
        C_AVG=$(grep    "^ctx_''${CTX_ARG}_avg_session="   "$PREFS_FILE" 2>/dev/null | tail -1 | cut -d= -f2)
        C_HUE=$(grep    "^ctx_''${CTX_ARG}_pref_hue="      "$PREFS_FILE" 2>/dev/null | tail -1 | cut -d= -f2)
        C_SAT=$(grep    "^ctx_''${CTX_ARG}_pref_sat="      "$PREFS_FILE" 2>/dev/null | tail -1 | cut -d= -f2)
        C_BRIGHT=$(grep "^ctx_''${CTX_ARG}_pref_bright="   "$PREFS_FILE" 2>/dev/null | tail -1 | cut -d= -f2)
        C_COLORFUL=$(grep "^ctx_''${CTX_ARG}_pref_colorful=" "$PREFS_FILE" 2>/dev/null | tail -1 | cut -d= -f2)
        C_AVG_MIN=$(${pkgs.gawk}/bin/awk -v s="''${C_AVG:-120}" 'BEGIN{printf "%.0f",s/60}')
        echo ""
        echo "  ── Context: $CTX_ARG ──────────────────"
        echo "  Events       : ''${C_WEIGHT:-0}"
        echo "  Avg session  : ~''${C_AVG_MIN}min"
        echo "  Hue          : ''${C_HUE:-(inheriting global)}°"
        echo "  Saturation   : ''${C_SAT:-(inheriting global)}%"
        echo "  Brightness   : ''${C_BRIGHT:-(inheriting global)}%"
        echo "  Colorful     : ''${C_COLORFUL:-(inheriting global)}%"
        echo "  Top ctx tags :"
        ${pkgs.gawk}/bin/awk -v pfx="ctx_''${CTX_ARG}:" -F= '
            substr($1,1,length(pfx))==pfx && $2+0>0 {
                printf "    %+.2f  %s\n", $2+0, substr($1,length(pfx)+1)
            }' "$TAG_PREFS_FILE" 2>/dev/null | sort -rn | head -8
        echo "  Bot ctx tags :"
        ${pkgs.gawk}/bin/awk -v pfx="ctx_''${CTX_ARG}:" -F= '
            substr($1,1,length(pfx))==pfx && $2+0<0 {
                printf "    %+.2f  %s\n", $2+0, substr($1,length(pfx)+1)
            }' "$TAG_PREFS_FILE" 2>/dev/null | sort -n | head -5
        echo "══════════════════════════════════════════"
    fi
  '';

  # ── wp-fetch ───────────────────────────────────────────────────────────────
  wp-fetch = pkgs.writeShellScriptBin "wp-fetch" ''
    WP_DIR="/home/${username}/Pictures/Wallpapers"
    TAG_PREFS="/home/${username}/.local/share/tag_prefs.txt"
    mkdir -p "$WP_DIR"

    LIKED_TAGS=""
    DISLIKED_TAGS=""
    if [ -f "$TAG_PREFS" ]; then
        LIKED_TAGS=$(${pkgs.gawk}/bin/awk -F= 'index($1,"ctx_")!=1 && $2+0 > 0.5 {printf "%s(%s)\n", $1, $2+0}' "$TAG_PREFS" \
            | sort -t'(' -k2 -rn | head -3 | sed 's/(.*//' | tr '\n' ' ')
        DISLIKED_TAGS=$(${pkgs.gawk}/bin/awk -F= 'index($1,"ctx_")!=1 && $2+0 < -0.5 {printf "%s(%s)\n", $1, $2+0}' "$TAG_PREFS" \
            | sort -t'(' -k2 -n | head -2 | sed 's/(.*//' | sed 's/^/-/' | tr '\n' ' ')
    fi

    QUERY_STR=""
    if [ -n "$LIKED_TAGS" ]; then
        LIKED=$(echo "$LIKED_TAGS" | ${pkgs.gawk}/bin/awk '{for(i=1;i<=NF;i++) printf "%s%s",$i,(i<NF?"+":""); print ""}')
        QUERY_STR="q=$LIKED"
        if [ -n "$DISLIKED_TAGS" ]; then
            DISLIKED=$(echo "$DISLIKED_TAGS" | ${pkgs.gawk}/bin/awk '{for(i=1;i<=NF;i++) printf "%s%s",$i,(i<NF?"+":""); print ""}')
            [ -n "$DISLIKED" ] && QUERY_STR="$QUERY_STR+$DISLIKED"
        fi
        QUERY_STR="$QUERY_STR&"
    fi

    SEED=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 6)
    API_URL="https://wallhaven.cc/api/v1/search?''${QUERY_STR}sort=random&seed=$SEED&categories=111&purity=100&resolutions=1920x1080,2560x1440,3840x2160&ratios=16x9"

    DOWNLOAD_URL=$(${pkgs.curl}/bin/curl -s "$API_URL" | ${pkgs.jq}/bin/jq -r '.data[0].path')

    if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
        ${pkgs.libnotify}/bin/notify-send -u critical "Wallhaven Error" "No wallpaper matched your tag preferences. Falling back to random."
        API_URL="https://wallhaven.cc/api/v1/search?sort=random&seed=$SEED&categories=111&purity=100&resolutions=1920x1080,2560x1440,3840x2160&ratios=16x9"
        DOWNLOAD_URL=$(${pkgs.curl}/bin/curl -s "$API_URL" | ${pkgs.jq}/bin/jq -r '.data[0].path')
        if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
            ${pkgs.libnotify}/bin/notify-send -u critical "Wallhaven Error" "Failed to fetch any wallpaper."
            exit 1
        fi
    fi

    FILENAME=$(basename "$DOWNLOAD_URL" | sed 's/^full-//')
    FILEPATH="$WP_DIR/$FILENAME"

    ${pkgs.curl}/bin/curl -s -o "$FILEPATH" "$DOWNLOAD_URL"

    if [ $? -eq 0 ] && [ -s "$FILEPATH" ]; then
        ${pkgs.libnotify}/bin/notify-send -u low -t 3000 "Wallhaven Download" "Downloaded: $FILENAME"
        wp-analyze "$FILEPATH"
        wp-tag "$FILEPATH" &
    else
        ${pkgs.libnotify}/bin/notify-send -u critical "Download Failed" "Could not download wallpaper from Wallhaven."
        exit 1
    fi
  '';

  # ── wp-mode ────────────────────────────────────────────────────────────────
  wp-mode = pkgs.writeShellScriptBin "wp-mode" ''
    MODE_FILE="/home/${username}/.local/share/wp_mode"
    mkdir -p "$(dirname "$MODE_FILE")"

    current() { cat "$MODE_FILE" 2>/dev/null || echo "balanced"; }

    set_mode() {
        local m="$1"
        case "$m" in
            silent|balanced|performance) ;;
            *) echo "Usage: wp-mode [silent|balanced|performance|status]" >&2; exit 1 ;;
        esac
        echo "$m" > "$MODE_FILE"
        case "$m" in
            silent)
                systemctl --user stop  wp-auto-switch.timer 2>/dev/null || true
                systemctl --user stop  wp-tag-untagged.timer 2>/dev/null || true
                ${pkgs.libnotify}/bin/notify-send -u low -t 3000 "Wallpaper Mode" "Silent — no switching, no AI tagging"
                ;;
            balanced)
                systemctl --user start wp-auto-switch.timer 2>/dev/null || true
                systemctl --user start wp-tag-untagged.timer 2>/dev/null || true
                ${pkgs.libnotify}/bin/notify-send -u low -t 3000 "Wallpaper Mode" "Balanced — normal operation"
                ;;
            performance)
                systemctl --user start wp-auto-switch.timer 2>/dev/null || true
                systemctl --user start wp-tag-untagged.timer 2>/dev/null || true
                ${pkgs.libnotify}/bin/notify-send -u low -t 3000 "Wallpaper Mode" "Performance — eager analysis & prefetch"
                wp-analyze --all --force 2>/dev/null &
                ;;
        esac
        pkill -SIGUSR2 waybar 2>/dev/null || true
    }

    case "''${1:-status}" in
        status)
            MODE=$(current)
            case "$MODE" in
                silent)      echo '{"text":"󰖜","tooltip":"Mode: Silent (no switching)","class":"mode-silent"}' ;;
                balanced)    echo '{"text":"󰊠","tooltip":"Mode: Balanced","class":"mode-balanced"}' ;;
                performance) echo '{"text":"󱐋","tooltip":"Mode: Performance (eager)","class":"mode-performance"}' ;;
                *)           echo '{"text":"󰊠","tooltip":"Mode: Balanced","class":"mode-balanced"}' ;;
            esac
            ;;
        cycle)
            MODE=$(current)
            case "$MODE" in
                balanced)    set_mode performance ;;
                performance) set_mode silent ;;
                *)           set_mode balanced ;;
            esac
            ;;
        silent|balanced|performance) set_mode "$1" ;;
        *) echo "Usage: wp-mode [silent|balanced|performance|cycle|status]" >&2; exit 1 ;;
    esac
  '';

  # ── wp-bank ────────────────────────────────────────────────────────────────
  wp-bank = pkgs.writeShellScriptBin "wp-bank" ''
    STATS_FILE="/home/${username}/.local/share/wallpaper_durations.txt"
    LAST_WP_FILE="/home/${username}/.local/share/last_wallpaper.txt"
    META_FILE="/home/${username}/.local/share/wallpaper_meta.tsv"
    PREFS_FILE="/home/${username}/.local/share/wallpaper_prefs.txt"
    NOW=$(date +%s)
    HOUR=$(date +%H)

    CURRENT_WEATHER=$(${pkgs.curl}/bin/curl -s "wttr.in?format=%C" | tr '[:upper:]' '[:lower:]' || echo "clear")

    if [ -s "$LAST_WP_FILE" ]; then
        read -r LAST_PATH LAST_START < "$LAST_WP_FILE"
        if [ -f "$LAST_PATH" ]; then
            DURATION=$(( NOW - LAST_START ))
            if [ "$DURATION" -gt 10 ]; then
                COL_T=5; [[ $HOUR -ge 6 && $HOUR -lt 12 ]] && COL_T=3; [[ $HOUR -ge 12 && $HOUR -lt 18 ]] && COL_T=4
                COL_W=10
                [[ "$CURRENT_WEATHER" == *"clear"* ]] && COL_W=6
                [[ "$CURRENT_WEATHER" == *"rain"*  ]] && COL_W=7
                [[ "$CURRENT_WEATHER" == *"cloud"* ]] && COL_W=8
                [[ "$CURRENT_WEATHER" == *"snow"*  ]] && COL_W=9

                ${pkgs.gawk}/bin/awk -v path="$LAST_PATH" -v add="$DURATION" -v ct="$COL_T" -v cw="$COL_W" '
                    $2 == path {
                        $1 += add; $ct += add; $cw += add;
                        while (NF < 12) $(NF+1) = 0;
                        $12 = $12 + 1;
                        found=1
                    }
                    { print }
                    END { if (!found) {
                        printf "%d %s 0 0 0 0 0 0 0 0 0 1\n", add, path | "cat"
                    }}
                ' "$STATS_FILE" > "$STATS_FILE.tmp" && mv "$STATS_FILE.tmp" "$STATS_FILE"

                if [ "$DURATION" -ge 5 ]; then
                    META_ROW=$(${pkgs.gawk}/bin/awk -v p="$LAST_PATH" '$1==p{print $2,$3,$4,$5;exit}' "$META_FILE" 2>/dev/null)
                    if [ -n "$META_ROW" ]; then
                        read -r M_HUE M_SAT M_BRIGHT M_COLORFUL <<< "$META_ROW"
                        P_HUE=$(grep '^pref_hue=' "$PREFS_FILE" 2>/dev/null | cut -d= -f2); P_HUE=''${P_HUE:-180}
                        P_SAT=$(grep '^pref_sat=' "$PREFS_FILE" 2>/dev/null | cut -d= -f2); P_SAT=''${P_SAT:-50}
                        P_BRIGHT=$(grep '^pref_bright=' "$PREFS_FILE" 2>/dev/null | cut -d= -f2); P_BRIGHT=''${P_BRIGHT:-50}
                        P_COLORFUL=$(grep '^pref_colorful=' "$PREFS_FILE" 2>/dev/null | cut -d= -f2); P_COLORFUL=''${P_COLORFUL:-40}
                        P_WEIGHT=$(grep '^pref_weight=' "$PREFS_FILE" 2>/dev/null | cut -d= -f2); P_WEIGHT=''${P_WEIGHT:-0}
                        AVG_SESSION=$(grep '^avg_session=' "$PREFS_FILE" 2>/dev/null | cut -d= -f2); AVG_SESSION=''${AVG_SESSION:-120}

                        SENTIMENT=$(${pkgs.gawk}/bin/awk -v d="$DURATION" -v avg="$AVG_SESSION" \
                            'BEGIN { ratio=d/avg; x=(ratio-1.0)*1.5; e2x=exp(2*x); printf "%.4f",(e2x-1)/(e2x+1) }')
                        ALPHA=$(${pkgs.gawk}/bin/awk -v s="$SENTIMENT" \
                            'BEGIN { a=s<0?-s:s; a=a*0.12; if(a<0.005)a=0; printf "%.4f",a }')

                        if [ "$(${pkgs.gawk}/bin/awk -v a="$ALPHA" 'BEGIN{print (a>0)?1:0}')" = "1" ]; then
                            DIRECTION=$(${pkgs.gawk}/bin/awk -v s="$SENTIMENT" 'BEGIN{print (s>=0)?"toward":"away"}')
                            ANTI=$(${pkgs.gawk}/bin/awk -v a="$ALPHA" 'BEGIN{printf "%.4f",1-a}')

                            NEW_HUE=$(${pkgs.gawk}/bin/awk -v old="$P_HUE" -v wp="$M_HUE" -v dir="$DIRECTION" -v a="$ALPHA" -v anti="$ANTI" \
                                'BEGIN { tgt=wp; if(dir=="away"){diff=wp-old; if(diff>180)diff-=360; if(diff<-180)diff+=360; tgt=old-diff}
                                         diff=tgt-old; if(diff>180)diff-=360; if(diff<-180)diff+=360
                                         r=old+diff*a; r=((r%360)+360)%360; printf "%.1f",r }')
                            NEW_SAT=$(${pkgs.gawk}/bin/awk      -v old="$P_SAT"      -v wp="$M_SAT"      -v dir="$DIRECTION" -v a="$ALPHA" -v anti="$ANTI" \
                                'BEGIN { tgt=(dir=="toward")?wp:(2*old-wp); if(tgt<0)tgt=0; if(tgt>100)tgt=100; printf "%.1f",old*anti+tgt*a }')
                            NEW_BRIGHT=$(${pkgs.gawk}/bin/awk   -v old="$P_BRIGHT"   -v wp="$M_BRIGHT"   -v dir="$DIRECTION" -v a="$ALPHA" -v anti="$ANTI" \
                                'BEGIN { tgt=(dir=="toward")?wp:(2*old-wp); if(tgt<0)tgt=0; if(tgt>100)tgt=100; printf "%.1f",old*anti+tgt*a }')
                            NEW_COLORFUL=$(${pkgs.gawk}/bin/awk -v old="$P_COLORFUL" -v wp="$M_COLORFUL" -v dir="$DIRECTION" -v a="$ALPHA" -v anti="$ANTI" \
                                'BEGIN { tgt=(dir=="toward")?wp:(2*old-wp); if(tgt<0)tgt=0; if(tgt>100)tgt=100; printf "%.1f",old*anti+tgt*a }')
                            NEW_WEIGHT=$(( P_WEIGHT + 1 ))
                            NEW_AVG=$(${pkgs.gawk}/bin/awk -v old="$AVG_SESSION" -v d="$DURATION" 'BEGIN{printf "%.1f",old*0.9+d*0.1}')

                            ${pkgs.gawk}/bin/awk \
                                -v hue="$NEW_HUE" -v sat="$NEW_SAT" \
                                -v bright="$NEW_BRIGHT" -v colorful="$NEW_COLORFUL" \
                                -v weight="$NEW_WEIGHT" -v avg="$NEW_AVG" \
                                '!/^pref_hue=|^pref_sat=|^pref_bright=|^pref_colorful=|^pref_weight=|^avg_session=/{print}
                                 END{printf "pref_hue=%s\npref_sat=%s\npref_bright=%s\npref_colorful=%s\npref_weight=%s\navg_session=%s\n",
                                     hue,sat,bright,colorful,weight,avg}' \
                                "$PREFS_FILE" > "$PREFS_FILE.tmp" && mv "$PREFS_FILE.tmp" "$PREFS_FILE"
                        else
                            NEW_AVG=$(${pkgs.gawk}/bin/awk -v old="$AVG_SESSION" -v d="$DURATION" 'BEGIN{printf "%.1f",old*0.9+d*0.1}')
                            ${pkgs.gawk}/bin/awk -v avg="$NEW_AVG" \
                                '!/^avg_session=/{print} END{printf "avg_session=%s\n",avg}' \
                                "$PREFS_FILE" > "$PREFS_FILE.tmp" && mv "$PREFS_FILE.tmp" "$PREFS_FILE"
                        fi
                    fi
                fi

                echo "$LAST_PATH $NOW" > "$LAST_WP_FILE"
            fi
        fi
    fi
  '';

  # ── wp-rgb ─────────────────────────────────────────────────────────────────
  wp-rgb = pkgs.writeShellScriptBin "wp-rgb" ''
    WP="$1"
    SYSFS="/sys/class/leds/asus::kbd_backlight/kbd_rgb_mode"

    [ -w "$SYSFS" ] || exit 0
    [ -z "$WP" ] && exit 0
    [ -f "$WP"  ] || exit 0

    MATUGEN_JSON=$(matugen image "$WP" \
      --config /etc/matugen/config.toml \
      --json hex 2>/dev/null) || exit 0

    [ -z "$MATUGEN_JSON" ] && exit 0

    HEX=$(echo "$MATUGEN_JSON" | ${pkgs.jq}/bin/jq -r \
      ".colors.dark.primary // \"\"" 2>/dev/null | tr -d '#')

    [ -z "$HEX" ] || [ ''${#HEX} -ne 6 ] && exit 0

    R=$(( 16#''${HEX:0:2} ))
    G=$(( 16#''${HEX:2:2} ))
    B=$(( 16#''${HEX:4:2} ))

    echo "1 0 $R $G $B 0" > "$SYSFS"

    STATE_SYSFS="/sys/class/leds/asus::kbd_backlight/kbd_rgb_state"
    [ -w "$STATE_SYSFS" ] && echo "1 1 1 1 1" > "$STATE_SYSFS" || true
  '';

  # ── wp-sync-greeter ────────────────────────────────────────────────────────
  wp-sync-greeter = pkgs.writeShellScriptBin "wp-sync-greeter" ''
    WP="$1"
    GREETER_DIR="/var/cache/greeter-wallpaper"
    GREETER_WP="$GREETER_DIR/current"
    GREETER_CSS="$GREETER_DIR/style.css"
    PALETTE_SCRIPT="$GREETER_DIR/tty-palette.sh"

    [ -d "$GREETER_DIR" ] || exit 0
    [ -z "$WP" ]          && exit 0
    [ -f "$WP"  ]         || exit 0

    install -m 644 "$WP" "$GREETER_WP"

    printf 'window { background-image: url("file://%s"); background-size: cover; background-position: center; }\n' \
      "$GREETER_WP" > "$GREETER_CSS"
    chmod 644 "$GREETER_CSS"

    MATUGEN_JSON=$(matugen image "$WP" \
      --config /etc/matugen/config.toml \
      --json hex 2>/dev/null) || true

    if [ -n "$MATUGEN_JSON" ]; then
      _c()  { echo "$MATUGEN_JSON" | ${pkgs.jq}/bin/jq -r ".colors.light.$1 // .colors.dark.$1 // \"\"" 2>/dev/null | tr -d '#'; }
      _cd() { echo "$MATUGEN_JSON" | ${pkgs.jq}/bin/jq -r ".colors.dark.$1 // \"\""  2>/dev/null | tr -d '#'; }

      C0=$(_cd  "surface")            C1=$(_cd  "error")
      C2=$(_cd  "tertiary")           C3=$(_cd  "secondary")
      C4=$(_cd  "primary")            C5=$(_cd  "tertiary_container")
      C6=$(_cd  "secondary_container") C7=$(_cd "on_surface")
      C8=$(_cd  "surface_variant")    C9=$(_cd  "error_container")
      C10=$(_cd "on_tertiary")        C11=$(_cd "on_secondary")
      C12=$(_cd "primary_container")  C13=$(_cd "on_tertiary_container")
      C14=$(_cd "on_secondary_container") C15=$(_cd "on_surface_variant")

      cat > "$PALETTE_SCRIPT" << PALETTE
#!/bin/sh
printf '\e]P0'$C0
printf '\e]P1'$C1
printf '\e]P2'$C2
printf '\e]P3'$C3
printf '\e]P4'$C4
printf '\e]P5'$C5
printf '\e]P6'$C6
printf '\e]P7'$C7
printf '\e]P8'$C8
printf '\e]P9'$C9
printf '\e]PA'$C10
printf '\e]PB'$C11
printf '\e]PC'$C12
printf '\e]PD'$C13
printf '\e]PE'$C14
printf '\e]PF'$C15
clear
PALETTE
      chmod 755 "$PALETTE_SCRIPT"
    fi
  '';

  # ── swaylock-themed ────────────────────────────────────────────────────────
  swaylock-themed = pkgs.writeShellScriptBin "swaylock-themed" ''
    exec ${pkgs."swaylock-effects"}/bin/swaylock \
      --screenshots \
      --effect-blur 8x5 \
      --effect-vignette 0.4:0.6 \
      --fade-in 0.3 \
      --clock \
      --timestr "%H:%M" \
      --datestr "%A, %d %B" \
      --font "JetBrainsMono Nerd Font" \
      --indicator \
      --indicator-radius 120 \
      --indicator-thickness 10 \
      --indicator-caps-lock \
      --grace 1 \
      --grace-no-mouse \
      --show-failed-attempts \
      --color            1e1e2e \
      --inside-color     1e1e2e \
      --inside-clear-color     1e1e2e \
      --inside-caps-lock-color 1e1e2e \
      --inside-ver-color       1e1e2e \
      --inside-wrong-color     1e1e2e \
      --ring-color       313244 \
      --ring-clear-color f5e0dc \
      --ring-caps-lock-color   fab387 \
      --ring-ver-color         89b4fa \
      --ring-wrong-color       eba0ac \
      --line-color       00000000 \
      --line-clear-color       00000000 \
      --line-caps-lock-color   00000000 \
      --line-ver-color         00000000 \
      --line-wrong-color       00000000 \
      --separator-color  00000000 \
      --key-hl-color     a6e3a1 \
      --bs-hl-color      f5e0dc \
      --caps-lock-key-hl-color a6e3a1 \
      --caps-lock-bs-hl-color  f5e0dc \
      --text-color       cdd6f4 \
      --text-clear-color       f5e0dc \
      --text-caps-lock-color   fab387 \
      --text-ver-color         89b4fa \
      --text-wrong-color       eba0ac \
      --layout-bg-color        00000000 \
      --layout-border-color    00000000 \
      --layout-text-color      cdd6f4
  '';

  # ── wp-change (niri edition, context‑aware wallpaper picker) ───────────────
  wp-change = pkgs.writeShellScriptBin "wp-change" ''
    # ─────────────────────────────────────────────────────────────────────────
    # wp-change  —  context-aware + colour-preference-aware wallpaper picker
    # ─────────────────────────────────────────────────────────────────────────

    get_weather() {
        W_CACHE="/tmp/wp_weather"
        if [[ ! -f "$W_CACHE" || $(find "$W_CACHE" -mmin +30) ]]; then
            LOC=$(${pkgs.geoclue2}/bin/whereami | ${pkgs.gawk}/bin/awk '/Latitude:|Longitude:/ {print $2}' | tr '\n' ',' | sed 's/,$//')
            if [ -z "$LOC" ]; then
                ${pkgs.curl}/bin/curl -s "wttr.in?format=%C" | tr '[:upper:]' '[:lower:]' > "$W_CACHE"
            else
                ${pkgs.curl}/bin/curl -s "wttr.in/$LOC?format=%C" | tr '[:upper:]' '[:lower:]' > "$W_CACHE"
            fi
        fi
        cat "$W_CACHE"
    }

    CURRENT_WEATHER=$(get_weather)
    HOUR=$(date +%H)

    WP_DIR="/home/${username}/Pictures/Wallpapers"
    STATS_FILE="/home/${username}/.local/share/wallpaper_durations.txt"
    TAGS_FILE="/home/${username}/.local/share/wallpaper_tags.tsv"
    PREFS_TAG_FILE="/home/${username}/.local/share/tag_prefs.txt"
    LAST_WP_FILE="/home/${username}/.local/share/last_wallpaper.txt"
    DECAY_FILE="/home/${username}/.local/share/wallpaper_last_decay.txt"
    COOLDOWN_FILE="/home/${username}/.local/share/wallpaper_cooldowns.txt"
    META_FILE="/home/${username}/.local/share/wallpaper_meta.tsv"
    PREFS_FILE="/home/${username}/.local/share/wallpaper_prefs.txt"

    mkdir -p "$(dirname "$STATS_FILE")"
    touch "$STATS_FILE" "$LAST_WP_FILE" "$DECAY_FILE" "$COOLDOWN_FILE"
    touch "$META_FILE" "$PREFS_TAG_FILE"
    NOW=$(${pkgs.coreutils}/bin/date +%s)

    TOD="night"
    [[ $HOUR -ge 6  && $HOUR -lt 12 ]] && TOD="morning"
    [[ $HOUR -ge 12 && $HOUR -lt 19 ]] && TOD="afternoon"
    WEA="other"
    [[ "$CURRENT_WEATHER" == *"clear"*   || "$CURRENT_WEATHER" == *"sunny"*    ]] && WEA="clear"
    [[ "$CURRENT_WEATHER" == *"rain"*    || "$CURRENT_WEATHER" == *"drizzle"*  || "$CURRENT_WEATHER" == *"shower"*   ]] && WEA="rain"
    [[ "$CURRENT_WEATHER" == *"cloud"*   || "$CURRENT_WEATHER" == *"overcast"* ]] && WEA="cloud"
    [[ "$CURRENT_WEATHER" == *"snow"*    || "$CURRENT_WEATHER" == *"sleet"*    || "$CURRENT_WEATHER" == *"blizzard"* ]] && WEA="snow"

    DOW=$(date +%u)
    DAY_CTX="weekday"
    [ "$DOW" -ge 6 ] && DAY_CTX="weekend"

    CTX="''${TOD}_''${WEA}_''${DAY_CTX}"

    # niri-specific: detect focused app for context slot
    APP_CTX="other"
    FOCUSED_APP=$(niri msg --json focused-window 2>/dev/null \
        | ${pkgs.jq}/bin/jq -r '.app_id // .title // ""' 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "")
    if [[ "$FOCUSED_APP" == *"kitty"* || "$FOCUSED_APP" == *"alacritty"* || \
          "$FOCUSED_APP" == *"foot"*  || "$FOCUSED_APP" == *"neovim"*    || \
          "$FOCUSED_APP" == *"emacs"* || "$FOCUSED_APP" == *"code"*      || \
          "$FOCUSED_APP" == *"zed"*   ]]; then
        APP_CTX="coding"
    elif [[ "$FOCUSED_APP" == *"firefox"* || "$FOCUSED_APP" == *"chromium"* || \
            "$FOCUSED_APP" == *"brave"*   || "$FOCUSED_APP" == *"vivaldi"*  ]]; then
        APP_CTX="browser"
    elif [[ "$FOCUSED_APP" == *"steam"* || "$FOCUSED_APP" == *"lutris"* || \
            "$FOCUSED_APP" == *"heroic"* || "$FOCUSED_APP" == *"game"*   ]]; then
        APP_CTX="gaming"
    fi
    APP_CTX_SUFFIX=""
    [ "$APP_CTX" != "other" ] && APP_CTX_SUFFIX="_''${APP_CTX}"
    CTX_FULL="''${CTX}''${APP_CTX_SUFFIX}"

    P_HUE=$(grep      '^pref_hue='      "$PREFS_FILE" 2>/dev/null | tail -1 | cut -d= -f2); P_HUE=''${P_HUE:-180}
    P_SAT=$(grep      '^pref_sat='      "$PREFS_FILE" 2>/dev/null | tail -1 | cut -d= -f2); P_SAT=''${P_SAT:-50}
    P_BRIGHT=$(grep   '^pref_bright='   "$PREFS_FILE" 2>/dev/null | tail -1 | cut -d= -f2); P_BRIGHT=''${P_BRIGHT:-50}
    P_COLORFUL=$(grep '^pref_colorful=' "$PREFS_FILE" 2>/dev/null | tail -1 | cut -d= -f2); P_COLORFUL=''${P_COLORFUL:-40}
    P_WEIGHT=$(grep   '^pref_weight='   "$PREFS_FILE" 2>/dev/null | tail -1 | cut -d= -f2); P_WEIGHT=''${P_WEIGHT:-0}
    AVG_SESSION=$(grep '^avg_session='  "$PREFS_FILE" 2>/dev/null | tail -1 | cut -d= -f2); AVG_SESSION=''${AVG_SESSION:-120}

    _read_ctx() {
        local key="$1" default="$2"
        local v
        v=$(grep "^ctx_''${CTX_FULL}_''${key}=" "$PREFS_FILE" 2>/dev/null | tail -1 | cut -d= -f2)
        [ -z "$v" ] && v=$(grep "^ctx_''${CTX}_''${key}=" "$PREFS_FILE" 2>/dev/null | tail -1 | cut -d= -f2)
        echo "''${v:-$default}"
    }
    C_HUE=$(_read_ctx pref_hue "$P_HUE")
    C_SAT=$(_read_ctx pref_sat "$P_SAT")
    C_BRIGHT=$(_read_ctx pref_bright "$P_BRIGHT")
    C_COLORFUL=$(_read_ctx pref_colorful "$P_COLORFUL")
    C_WEIGHT=$(_read_ctx pref_weight "0")
    C_AVG=$(_read_ctx avg_session "$AVG_SESSION")
    LEARN_CTX="$CTX_FULL"

    WP_MODE=$(cat "/home/${username}/.local/share/wp_mode" 2>/dev/null || echo "balanced")

    MIN_AGE_DAYS=14
    MIN_SHOWS_PER_CTX=2
    KEEP_THRESHOLD_RATIO=0.5
    MIN_POOL=20

    if [ "$WP_MODE" != "silent" ]; then
        POOL_SIZE=$(find "$WP_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) | wc -l)

        if [ "$POOL_SIZE" -lt "$MIN_POOL" ]; then
            NEED=$(( MIN_POOL - POOL_SIZE ))
            ${pkgs.libnotify}/bin/notify-send -u low -t 3000 "Wallpaper Pool" \
                "Pool has $POOL_SIZE wallpapers (min $MIN_POOL). Fetching $NEED more."
            for _i in $(seq 1 "$NEED"); do
                ( sleep $(( _i * 2 )) ; wp-fetch ) &
            done
        fi

        find "$WP_DIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) | \
        while read -r FILE; do
            STATS_LINE=$(${pkgs.gawk}/bin/awk -v p="$FILE" '$2==p{print $0}' "$STATS_FILE")
            [ -z "$STATS_LINE" ] && continue

            FILE_AGE_DAYS=$(( (NOW - $(stat -c %Y "$FILE" 2>/dev/null || echo $NOW)) / 86400 ))
            [ "$FILE_AGE_DAYS" -lt "$MIN_AGE_DAYS" ] && continue

            TIMES_SHOWN=$(echo "$STATS_LINE" | ${pkgs.gawk}/bin/awk '{print $12+0}')
            [ "$TIMES_SHOWN" -lt $(( 8 * MIN_SHOWS_PER_CTX )) ] && continue

            EXPLICIT=$(echo "$STATS_LINE" | ${pkgs.gawk}/bin/awk '{print $11+0}')
            [ "$EXPLICIT" -gt 0 ] && continue

            SURVIVED=$(echo "$STATS_LINE" | ${pkgs.gawk}/bin/awk \
                -v thresh="$KEEP_THRESHOLD_RATIO" -v avg_s="$AVG_SESSION" '
                {
                    shown=$12+0; if(shown==0) { print 1; exit }
                    survived=0
                    for(i=3;i<=10;i++) {
                        rate=($i+0)/shown
                        if(avg_s > 0 && rate >= thresh * avg_s) { survived=1; break }
                    }
                    print survived
                }')
            [ "$SURVIVED" = "1" ] && continue

            rm -f "$FILE"
            ${pkgs.gawk}/bin/awk -v p="$FILE" '$2!=p' "$STATS_FILE" > "$STATS_FILE.tmp" && mv "$STATS_FILE.tmp" "$STATS_FILE"
            ${pkgs.gawk}/bin/awk -v p="$FILE" 'BEGIN{FS="\t"} $1!=p' "$META_FILE" > "$META_FILE.tmp" && mv "$META_FILE.tmp" "$META_FILE"
            ${pkgs.gawk}/bin/awk -v p="$FILE" 'BEGIN{FS="\t"} $1!=p' "/home/${username}/.local/share/wallpaper_tags.tsv" \
                > "/home/${username}/.local/share/wallpaper_tags.tsv.tmp" \
                && mv "/home/${username}/.local/share/wallpaper_tags.tsv.tmp" "/home/${username}/.local/share/wallpaper_tags.tsv"

            ${pkgs.libnotify}/bin/notify-send -u low -t 4000 -i "dialog-warning" \
                "Wallpaper Retired" "$(basename "$FILE") — weak in all contexts. Fetching replacement."

            FETCH_COUNT=1
            [ "$WP_MODE" = "performance" ] && FETCH_COUNT=2
            for _j in $(seq 1 "$FETCH_COUNT"); do
                ( sleep $(( RANDOM % 4 + _j )) ; wp-fetch ) &
            done
        done
    fi

    LAST_DECAY=$(cat "$DECAY_FILE" 2>/dev/null || echo 0)
    if [ $((NOW - LAST_DECAY)) -ge 86400 ]; then
        ${pkgs.gawk}/bin/awk '{
            $1 = int($1 * 0.99);
            for(i=3;i<=10;i++) $i = int($i * 0.99);
            if ($11 > 0) $11 = int($11 * 0.95);
            else if ($11 < 0) $11 = int($11 * 0.95);
            while (NF < 12) $(NF+1) = 0;
            print $0
        }' "$STATS_FILE" > "$STATS_FILE.tmp" && mv "$STATS_FILE.tmp" "$STATS_FILE"
        echo "$NOW" > "$DECAY_FILE"
    fi

    if [ -s "$LAST_WP_FILE" ]; then
        read -r LAST_PATH LAST_START < "$LAST_WP_FILE"
        if [ -f "$LAST_PATH" ]; then
            DURATION=$(( NOW - LAST_START ))

            IDLE_SINCE_FILE="/run/user/$(id -u)/swayidle_last_active"
            if [ -f "$IDLE_SINCE_FILE" ]; then
                LAST_ACTIVE=$(cat "$IDLE_SINCE_FILE" 2>/dev/null || echo "$NOW")
                ACTIVE_SECS=$(( LAST_ACTIVE - LAST_START ))
                if [ "$ACTIVE_SECS" -gt 60 ] && [ "$ACTIVE_SECS" -lt "$DURATION" ]; then
                    DURATION="$ACTIVE_SECS"
                fi
            fi

            COL_T=5; [[ $HOUR -ge 6 && $HOUR -lt 12 ]] && COL_T=3; [[ $HOUR -ge 12 && $HOUR -lt 18 ]] && COL_T=4
            COL_W=10
            [[ "$CURRENT_WEATHER" == *"clear"* ]] && COL_W=6
            [[ "$CURRENT_WEATHER" == *"rain"*  ]] && COL_W=7
            [[ "$CURRENT_WEATHER" == *"cloud"* ]] && COL_W=8
            [[ "$CURRENT_WEATHER" == *"snow"*  ]] && COL_W=9

            ${pkgs.gawk}/bin/awk -v path="$LAST_PATH" -v add="$DURATION" -v ct="$COL_T" -v cw="$COL_W" '
                $2 == path {
                    $1 += add; $ct += add; $cw += add;
                    while (NF < 12) $(NF+1) = 0;
                    $12 = $12 + 1;
                    found=1
                }
                { print }
                END { if (!found) {
                    printf "%d %s 0 0 0 0 0 0 0 0 0 1\n", add, path | "cat"
                }}
            ' "$STATS_FILE" > "$STATS_FILE.tmp" && mv "$STATS_FILE.tmp" "$STATS_FILE"

            if [ "$DURATION" -ge 5 ]; then
                META_ROW=$(${pkgs.gawk}/bin/awk -v p="$LAST_PATH" '$1==p{print $2,$3,$4,$5;exit}' "$META_FILE" 2>/dev/null)
                if [ -n "$META_ROW" ]; then
                    read -r M_HUE M_SAT M_BRIGHT M_COLORFUL <<< "$META_ROW"

                    SENTIMENT=$(${pkgs.gawk}/bin/awk \
                        -v d="$DURATION" -v avg="$C_AVG" \
                        'BEGIN {
                            ratio = d / avg
                            x = (ratio - 1.0) * 1.5
                            e2x = exp(2*x)
                            s = (e2x - 1) / (e2x + 1)
                            printf "%.4f", s
                        }')

                    ALPHA_G=$(${pkgs.gawk}/bin/awk -v s="$SENTIMENT" \
                        'BEGIN { a=s<0?-s:s; a=a*0.08; if(a<0.001)a=0; printf "%.4f",a }')
                    ALPHA_C=$(${pkgs.gawk}/bin/awk -v s="$SENTIMENT" \
                        'BEGIN { a=s<0?-s:s; a=a*0.12; if(a<0.001)a=0; printf "%.4f",a }')

                    SIGNAL_ACTIVE=$(${pkgs.gawk}/bin/awk -v a="$ALPHA_G" 'BEGIN{print (a>0)?1:0}')

                    if [ "$SIGNAL_ACTIVE" = "1" ]; then
                        DIR=$(${pkgs.gawk}/bin/awk -v s="$SENTIMENT" 'BEGIN{print (s>=0)?"toward":"away"}')

                        ema_linear() {
                            local old=$1 wp=$2 dir=$3 alpha=$4
                            ${pkgs.gawk}/bin/awk -v old="$old" -v wp="$wp" -v dir="$dir" -v a="$alpha" '
                                BEGIN {
                                    tgt = (dir=="toward") ? wp : (2*old - wp)
                                    if (tgt<0) tgt=0; if (tgt>100) tgt=100
                                    printf "%.1f", old*(1-a) + tgt*a
                                }'
                        }
                        ema_hue() {
                            local old=$1 wp=$2 dir=$3 alpha=$4
                            ${pkgs.gawk}/bin/awk -v old="$old" -v wp="$wp" -v dir="$dir" -v a="$alpha" '
                                BEGIN {
                                    if (dir=="toward") { tgt=wp } else {
                                        diff=wp-old
                                        if(diff>180)diff-=360; if(diff<-180)diff+=360
                                        tgt=old-diff; tgt=((tgt%360)+360)%360
                                    }
                                    diff=tgt-old
                                    if(diff>180)diff-=360; if(diff<-180)diff+=360
                                    r=old+diff*a; r=((r%360)+360)%360; printf "%.1f",r
                                }'
                        }

                        NEW_G_HUE=$(ema_hue        "$P_HUE"      "$M_HUE"      "$DIR" "$ALPHA_G")
                        NEW_G_SAT=$(ema_linear      "$P_SAT"      "$M_SAT"      "$DIR" "$ALPHA_G")
                        NEW_G_BRIGHT=$(ema_linear   "$P_BRIGHT"   "$M_BRIGHT"   "$DIR" "$ALPHA_G")
                        NEW_G_COLORFUL=$(ema_linear "$P_COLORFUL" "$M_COLORFUL" "$DIR" "$ALPHA_G")
                        NEW_G_WEIGHT=$(( P_WEIGHT + 1 ))
                        NEW_G_AVG=$(${pkgs.gawk}/bin/awk -v old="$AVG_SESSION" -v d="$DURATION" \
                            'BEGIN{printf "%.1f", old*0.9+d*0.1}')

                        NEW_C_HUE=$(ema_hue        "$C_HUE"      "$M_HUE"      "$DIR" "$ALPHA_C")
                        NEW_C_SAT=$(ema_linear      "$C_SAT"      "$M_SAT"      "$DIR" "$ALPHA_C")
                        NEW_C_BRIGHT=$(ema_linear   "$C_BRIGHT"   "$M_BRIGHT"   "$DIR" "$ALPHA_C")
                        NEW_C_COLORFUL=$(ema_linear "$C_COLORFUL" "$M_COLORFUL" "$DIR" "$ALPHA_C")
                        NEW_C_WEIGHT=$(( C_WEIGHT + 1 ))
                        NEW_C_AVG=$(${pkgs.gawk}/bin/awk -v old="$C_AVG" -v d="$DURATION" \
                            'BEGIN{printf "%.1f", old*0.9+d*0.1}')

                        ${pkgs.gawk}/bin/awk \
                            -v hue="$NEW_G_HUE" -v sat="$NEW_G_SAT" \
                            -v bright="$NEW_G_BRIGHT" -v colorful="$NEW_G_COLORFUL" \
                            -v weight="$NEW_G_WEIGHT" -v avg="$NEW_G_AVG" \
                            '!/^pref_hue=|^pref_sat=|^pref_bright=|^pref_colorful=|^pref_weight=|^avg_session=/{print}
                             END{
                               printf "pref_hue=%s\npref_sat=%s\npref_bright=%s\npref_colorful=%s\npref_weight=%s\navg_session=%s\n",
                                      hue,sat,bright,colorful,weight,avg
                             }' "$PREFS_FILE" > "$PREFS_FILE.tmp" && mv "$PREFS_FILE.tmp" "$PREFS_FILE"

                        ${pkgs.gawk}/bin/awk \
                            -v ctx="$LEARN_CTX" \
                            -v hue="$NEW_C_HUE" -v sat="$NEW_C_SAT" \
                            -v bright="$NEW_C_BRIGHT" -v colorful="$NEW_C_COLORFUL" \
                            -v weight="$NEW_C_WEIGHT" -v avg="$NEW_C_AVG" \
                            'BEGIN{ pfx="ctx_"ctx"_" }
                             $0 !~ ("^"pfx"pref_hue=|^"pfx"pref_sat=|^"pfx"pref_bright=|^"pfx"pref_colorful=|^"pfx"pref_weight=|^"pfx"avg_session=") {print}
                             END{
                               printf "%spref_hue=%s\n%spref_sat=%s\n%spref_bright=%s\n%spref_colorful=%s\n%spref_weight=%s\n%savg_session=%s\n",
                                      pfx,hue, pfx,sat, pfx,bright, pfx,colorful, pfx,weight, pfx,avg
                             }' "$PREFS_FILE" > "$PREFS_FILE.tmp" && mv "$PREFS_FILE.tmp" "$PREFS_FILE"
                    else
                        NEW_G_AVG=$(${pkgs.gawk}/bin/awk -v old="$AVG_SESSION" -v d="$DURATION" 'BEGIN{printf "%.1f",old*0.9+d*0.1}')
                        NEW_C_AVG=$(${pkgs.gawk}/bin/awk -v old="$C_AVG"       -v d="$DURATION" 'BEGIN{printf "%.1f",old*0.9+d*0.1}')
                        ${pkgs.gawk}/bin/awk \
                            -v gavg="$NEW_G_AVG" -v ctx="$LEARN_CTX" -v cavg="$NEW_C_AVG" \
                            'BEGIN{ cpat="^ctx_"ctx"_avg_session=" }
                             /^avg_session=/ { print "avg_session="gavg; next }
                             $0 ~ cpat       { print "ctx_"ctx"_avg_session="cavg; next }
                             { print }
                             END { if (!saw_ctx) print "ctx_"ctx"_avg_session="cavg }
                            ' "$PREFS_FILE" > "$PREFS_FILE.tmp" && mv "$PREFS_FILE.tmp" "$PREFS_FILE"
                        grep -q "^ctx_''${LEARN_CTX}_avg_session=" "$PREFS_FILE" 2>/dev/null \
                            || echo "ctx_''${LEARN_CTX}_avg_session=$NEW_C_AVG" >> "$PREFS_FILE"
                    fi
                fi
            fi
        fi
    fi

    INITIAL_HEAT=100; DECAY_PER_SWITCH=20; DECAY_PER_MINUTE=1; HARD_FLOOR=3
    L_COL_T=5; [[ $HOUR -ge 6 && $HOUR -lt 12 ]] && L_COL_T=3; [[ $HOUR -ge 12 && $HOUR -lt 18 ]] && L_COL_T=4
    L_COL_W=10
    [[ "$CURRENT_WEATHER" == *"clear"* ]] && L_COL_W=6
    [[ "$CURRENT_WEATHER" == *"rain"*  ]] && L_COL_W=7
    [[ "$CURRENT_WEATHER" == *"cloud"* ]] && L_COL_W=8
    [[ "$CURRENT_WEATHER" == *"snow"*  ]] && L_COL_W=9

    TAG_MAP_FILE="/tmp/wp_tag_map_$$"
    ${pkgs.gawk}/bin/awk '{
        path=$1; tags="";
        for(i=2;i<=NF;i+=2) {
            if(i+1<=NF) tags = tags sprintf("%s:%s,", $i, $(i+1));
        }
        gsub(/,$/,"",tags);
        print path "\t" tags;
    }' "$TAGS_FILE" > "$TAG_MAP_FILE"

    NEW_WP_FILE="/tmp/wp_new_$$"
    OLD_WP_FILE="/tmp/wp_old_$$"
    SENTINEL="/tmp/wp_sentinel_24h"
    CUTOFF=$(( NOW - 86400 ))
    touch -t "$(date -d "@$CUTOFF" +%Y%m%d%H%M.%S)" "$SENTINEL" 2>/dev/null || true
    find "$WP_DIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
        -newer "$SENTINEL" -print > "$NEW_WP_FILE" 2>/dev/null || true
    find "$WP_DIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
        \! -newer "$SENTINEL" -print > "$OLD_WP_FILE" 2>/dev/null || true

    WP=$(
      {
      ${pkgs.gawk}/bin/awk '{for(i=0;i<100;i++) print $0}' "$NEW_WP_FILE"

      ${pkgs.gawk}/bin/awk \
        -v stats="$STATS_FILE" \
        -v cooldowns="$COOLDOWN_FILE" \
        -v meta="$META_FILE" \
        -v tagmap="$TAG_MAP_FILE" \
        -v tagprefs="$PREFS_TAG_FILE" \
        -v now="$NOW" \
        -v ctx="$CTX" \
        -v ct="$L_COL_T" \
        -v cw="$L_COL_W" \
        -v floor="$HARD_FLOOR" \
        -v d_switch="$DECAY_PER_SWITCH" \
        -v d_min="$DECAY_PER_MINUTE" \
        -v p_hue="$P_HUE"       -v c_hue="$C_HUE" \
        -v p_sat="$P_SAT"       -v c_sat="$C_SAT" \
        -v p_bright="$P_BRIGHT" -v c_bright="$C_BRIGHT" \
        -v p_colorful="$P_COLORFUL" -v c_colorful="$C_COLORFUL" \
        -v p_weight="$P_WEIGHT" -v c_weight="$C_WEIGHT" \
        -v avg_session="$AVG_SESSION" -v c_avg="$C_AVG" \
      '
      function tanh(x,    e2x) { e2x = exp(2*x); return (e2x-1)/(e2x+1) }
      function clamp(v,lo,hi)  { return v<lo?lo:(v>hi?hi:v) }
      function colour_score(wp_hue,wp_sat,wp_bright,wp_colorful,
                            ph,ps,pb,pc,    hd,hs,sd,bd,cd) {
        hd = ph - wp_hue; if(hd<0)hd=-hd; if(hd>180)hd=360-hd
        hs = cos(hd * 3.14159265/180.0)
        sd = (ps - wp_sat)/100.0;      sd = 1-(sd<0?-sd:sd); sd=sd*2-1
        bd = (pb - wp_bright)/100.0;   bd = 1-(bd<0?-bd:bd); bd=bd*2-1
        cd = (pc - wp_colorful)/100.0; cd = 1-(cd<0?-cd:cd); cd=cd*2-1
        return clamp(bd*0.35 + sd*0.30 + cd*0.20 + hs*0.15, -1.0, 1.0)
      }
      BEGIN {
        CTX_FULL = 20
        ctx_conf = clamp(c_weight / CTX_FULL, 0, 1)
        while ((getline line < cooldowns) > 0) {
            n = split(line, f, " ")
            heat = f[1]+0; ts = f[n]+0
            path = ""; for (k=2; k<=n-1; k++) path = path (k>2?" ":"") f[k]
            h = heat - (now - ts)/60 * d_min
            if (h < floor && heat >= floor) h = floor
            h -= d_switch
            if (h > 0) active_cooldowns[path] = h
        }
        close(cooldowns)
        total_shows = 0
        while ((getline line < stats) > 0) {
            split(line, f, " ")
            for (i=1; i<=12; i++) data[f[2], i] = f[i]+0
            total_shows += f[12]+0
        }
        close(stats)
        while ((getline line < meta) > 0) {
            split(line, f, "\t")
            m_hue[f[1]]=f[2]+0; m_sat[f[1]]=f[3]+0
            m_bright[f[1]]=f[4]+0; m_colorful[f[1]]=f[5]+0
            has_meta[f[1]]=1
        }
        close(meta)
        tag_strong_g = 0; tag_strong_c = 0
        ctx_pfx = "ctx_" ctx ":"
        while ((getline line < tagprefs) > 0) {
            n = index(line, "="); k = substr(line,1,n-1); v = substr(line,n+1)+0
            if (substr(k,1,length(ctx_pfx)) == ctx_pfx) {
                tag_weight_c[substr(k, length(ctx_pfx)+1)] = v
                if (v>0.3 || v<-0.3) tag_strong_c++
            } else if (index(k,"ctx_") != 1) {
                tag_weight_g[k] = v
                if (v>0.3 || v<-0.3) tag_strong_g++
            }
        }
        close(tagprefs)
        while ((getline line < tagmap) > 0) {
            split(line, f, "\t"); tags_data[f[1]] = f[2]
        }
        close(tagmap)
        TICKET_SCALE = 40
      }
      {
        path = $0
        if (active_cooldowns[path] > 0) next
        times_shown = data[path, 12]
        s_implicit = 0.0
        if (times_shown > 0 && avg_session > 0) {
            avg_for_wp = data[path, 1] / times_shown
            s_implicit = tanh((avg_for_wp / avg_session - 1.0) * 1.5)
        }
        if (total_shows > 0) {
            ucb = clamp(sqrt(log(total_shows+1)/(times_shown+1)) * 0.25, 0, 0.5)
            s_implicit = clamp(s_implicit + ucb, -1.0, 1.0)
        }
        s_ctx_colour = 0.0; s_glob_colour = 0.0
        if (has_meta[path]) {
            if (p_weight+0 > 5)
                s_glob_colour = colour_score(m_hue[path],m_sat[path],m_bright[path],m_colorful[path],
                                             p_hue,p_sat,p_bright,p_colorful)
            if (c_weight+0 > 3)
                s_ctx_colour  = colour_score(m_hue[path],m_sat[path],m_bright[path],m_colorful[path],
                                             c_hue,c_sat,c_bright,c_colorful)
        }
        s_colour = s_ctx_colour * ctx_conf + s_glob_colour * (1 - ctx_conf)
        s_ctx_tag = 0.0; s_glob_tag = 0.0
        if (path in tags_data && length(tags_data[path]) > 0) {
            score_g=0; conf_sum_g=0; score_c=0; conf_sum_c=0
            split(tags_data[path], pairs, ",")
            for (idx in pairs) {
                split(pairs[idx], pair, ":"); tag=pair[1]; conf=pair[2]+0
                if (tag in tag_weight_g) { score_g+=tag_weight_g[tag]*conf; conf_sum_g+=conf }
                if (tag in tag_weight_c) { score_c+=tag_weight_c[tag]*conf; conf_sum_c+=conf }
            }
            if (tag_strong_g > 0 && conf_sum_g > 0) s_glob_tag = tanh((score_g/conf_sum_g)*2.0)
            if (tag_strong_c > 0 && conf_sum_c > 0) s_ctx_tag  = tanh((score_c/conf_sum_c)*2.0)
        }
        s_tag = s_ctx_tag * ctx_conf + s_glob_tag * (1 - ctx_conf)
        score = s_implicit*0.30 + s_colour*0.50 + s_tag*0.20
        norm    = (score + 1.0) / 2.0
        tickets = int(norm * (TICKET_SCALE - 1) + 1)
        if (tickets < 1) tickets = 1
        for (i=0; i<tickets; i++) print path
      }
      ' "$OLD_WP_FILE"
      } | ${pkgs.coreutils}/bin/shuf -n 1
    )

    rm -f "$TAG_MAP_FILE" "$NEW_WP_FILE" "$OLD_WP_FILE" "$SENTINEL"

    if [ -z "$WP" ]; then
        if [ -s "$COOLDOWN_FILE" ]; then
            > "$COOLDOWN_FILE"
            WP=$(find "$WP_DIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
                | ${pkgs.coreutils}/bin/shuf -n 1)
        fi
    fi

    if [ -z "$WP" ]; then
        ${pkgs.libnotify}/bin/notify-send -u normal "Wallpaper" "No wallpapers found in $WP_DIR"
        exit 1
    fi

    ${pkgs.gawk}/bin/awk -v p="$WP" 'BEGIN{FS=" ";OFS=" "} $2!=p' "$COOLDOWN_FILE" > "$COOLDOWN_FILE.tmp" \
        && mv "$COOLDOWN_FILE.tmp" "$COOLDOWN_FILE" 2>/dev/null || true
    echo "$INITIAL_HEAT $WP $NOW" >> "$COOLDOWN_FILE"
    ${pkgs.gawk}/bin/awk -v now="$NOW" -v d_min="$DECAY_PER_MINUTE" -v d_sw="$DECAY_PER_SWITCH" -v fl="$HARD_FLOOR" '
        { heat=$1+0; ts=$NF+0; h=heat-(now-ts)/60*d_min; h-=d_sw; if(h>fl) print $0 }
    ' "$COOLDOWN_FILE" > "$COOLDOWN_FILE.tmp" && mv "$COOLDOWN_FILE.tmp" "$COOLDOWN_FILE"

    if ! ${pkgs.gawk}/bin/awk -v p="$WP" '$1==p{found=1;exit} END{exit !found}' "$META_FILE"; then
        wp-analyze "$WP" &
    fi
    if [ "$WP_MODE" != "silent" ]; then
        if ! grep -qF "$WP" "/home/${username}/.local/share/wallpaper_tags.tsv" 2>/dev/null; then
            nice -n 19 ${pkgs.util-linux}/bin/ionice -c 3 wp-tag "$WP" >/dev/null 2>&1 &
        fi
    fi

    TRANSITIONS=(wipe wipe wipe grow outer)
    TRANSITION=''${TRANSITIONS[$RANDOM % ''${#TRANSITIONS[@]}]}
    ${pkgs.swww}/bin/swww img "$WP" \
        --transition-type "$TRANSITION" \
        --transition-angle 45 \
        --transition-duration 1 \
        --transition-fps 60 \
        --transition-wave "20,20"

    wp-sync-greeter "$WP" &

    matugen image "$WP" --config /etc/matugen/config.toml || echo "matugen failed"
    systemctl --user restart swayosd 2>/dev/null || true
    # niri-specific: reload config + notify
    niri msg action load-config-file
    swaync-client -rs || true
    kitty @ --to unix:/tmp/kitty-matugen set-colors --all \
        "/home/${username}/.config/kitty/colors.conf" 2>/dev/null || true
    pkill -SIGUSR2 waybar 2>/dev/null || true
    wp-rgb "$WP" &

    WP_NAME=$(basename "$WP")
    COLOUR_INFO=""
    if META_ROW=$(${pkgs.gawk}/bin/awk -v p="$WP" '$1==p{print $2,$3,$4,$5;exit}' "$META_FILE" 2>/dev/null) && [ -n "$META_ROW" ]; then
        read -r N_HUE N_SAT N_BRIGHT N_COLORFUL <<< "$META_ROW"
        COLOUR_INFO="\nHue: ''${N_HUE}°  Sat: ''${N_SAT}%  Bright: ''${N_BRIGHT}%  Vivid: ''${N_COLORFUL}%"
    fi

    ${pkgs.libnotify}/bin/notify-send -u low -t 4000 \
        -i "$WP" \
        -h string:x-canonical-private-synchronous:wp-change \
        "Wallpaper Changed" \
        "''${WP_NAME}''${COLOUR_INFO}" &

    echo "$WP $NOW" > "$LAST_WP_FILE"
  '';

in
{
  # Consumed by niri-setup.nix (and any other DE module that needs these scripts).
  _module.args.wallpaperPkgs = {
    inherit wp-tag wp-tag-untagged wp-analyze wp-prefs wp-fetch wp-mode
            wp-bank wp-rgb wp-sync-greeter swaylock-themed wp-change;
  };

  environment.systemPackages = with pkgs; [
    wp-tag
    wp-tag-untagged
    wp-analyze
    wp-prefs
    wp-fetch
    wp-mode
    wp-bank
    wp-rgb
    wp-sync-greeter
    swaylock-themed
    wp-change
    swww
    imagemagick
    curl
    jq
    python3
    python3Packages.onnxruntime
    python3Packages.pillow
    python3Packages.numpy
    pkgs."swaylock-effects"
    matugen
  ];

  # ── geoclue2 — used by wp-change for weather location ─────────────────────
  services.geoclue2.enable = true;

  # ── PAM service for swaylock authentication ────────────────────────────────
  security.pam.services.swaylock = {};

  # ── Systemd units ──────────────────────────────────────────────────────────
  systemd.user.services.wallpaper-banker = {
    description    = "Bank wallpaper duration on logout/shutdown";
    wantedBy       = [ "graphical-session.target" ];
    before         = [ "graphical-session.target" ];
    serviceConfig  = {
      Type             = "oneshot";
      RemainAfterExit  = true;
      ExecStop         = "${wp-bank}/bin/wp-bank";
      ExecStart        = "${pkgs.coreutils}/bin/true";
    };
  };

  systemd.user.timers.wallpaper-banker-timer = {
    wantedBy    = [ "timers.target" ];
    timerConfig = {
      OnUnitActiveSec = "1h";
      Unit            = "wallpaper-banker.service";
    };
  };

  systemd.user.services.wp-tag-untagged = {
    description   = "Tag untagged wallpapers";
    serviceConfig = {
      Type              = "oneshot";
      ExecStart         = "${wp-tag-untagged}/bin/wp-tag-untagged";
      Nice              = 19;
      IOSchedulingClass = "idle";
    };
  };

  systemd.user.timers.wp-tag-untagged = {
    wantedBy    = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };

  systemd.user.services.wp-tag-watcher = {
    description   = "Tag newly added wallpapers immediately";
    serviceConfig = {
      Type              = "oneshot";
      ExecStart         = "${wp-tag-untagged}/bin/wp-tag-untagged";
      Nice              = 19;
      IOSchedulingClass = "idle";
    };
  };

  systemd.user.paths.wp-tag-watcher = {
    description = "Watch wallpaper directory for new files";
    wantedBy    = [ "paths.target" ];
    pathConfig  = {
      PathChanged  = "/home/${username}/Pictures/Wallpapers";
      Unit         = "wp-tag-watcher.service";
      MakeDirectory = true;
    };
  };
}