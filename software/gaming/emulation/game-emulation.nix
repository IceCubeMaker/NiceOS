{ config, pkgs, lib, ... }:

let
  user = config.global.user;
  baseRomDir = config.global.romDir;
  
  bundles = {
    "nintendo"     = [ "nes" "snes" "n64" "gc" "wii" "wiiu" "switch" "gb" "gbc" "gba" "3ds" "nds" ];
    "sony"         = [ "psx" "ps2" "psp" ];
    "sega"         = [ "megadrive" "saturn" "dreamcast" "gamegear" "mastersystem" ];
    "dual-screen"  = [ "nds" "3ds" "wiiu" ]; 
    "handhelds"    = [ "gb" "gbc" "gba" "nds" "3ds" "psp" "wonderswancolor" "gamegear" ];
    "retro"        = [ "nes" "snes" "gb" "gbc" "megadrive" "atari2600" "pcengine" "mastersystem" ];
    "disc-based"   = [ "psx" "ps2" "saturn" "dreamcast" "gc" "wii" "wiiu" ];
    "arcade"       = [ "mame" "neogeo" ];
    "32-64-bit"    = [ "n64" "psx" "saturn" "nds" ];
    "16-bit"       = [ "snes" "megadrive" "pcengine" "gbc" "wonderswancolor" ];
    "8-bit"        = [ "nes" "gb" "mastersystem" "atari2600" "gamegear" ];
    "high-end"     = [ "gc" "wii" "wiiu" "switch" "ps2" "dreamcast" ];
  };
  
  rawEnabled = config.global.emulationPlatforms;
  enabled = lib.unique (lib.flatten (map (p: 
    if bundles ? ${p} then bundles.${p} # If it's a bundle name, expand it
    else p                             # Otherwise, keep it as a single platform
  ) rawEnabled));

  # Map platforms to their specific launch commands
  allPlatforms = {
    "snes"             = "retroarch --fullscreen -L /run/current-system/sw/lib/retroarch/cores/snes9x_libretro.so";
    "gba"              = "retroarch --fullscreen -L /run/current-system/sw/lib/retroarch/cores/mgba_libretro.so";
    "nes"              = "retroarch --fullscreen -L /run/current-system/sw/lib/retroarch/cores/nestopia_libretro.so";
    "n64"              = "retroarch --fullscreen -L /run/current-system/sw/lib/retroarch/cores/parallel_n64_libretro.so";
    "gc"               = "dolphin-emu -e";
    "wii"              = "dolphin-emu -e";
    #"wiiu"             = "cemu -f -g";
    "switch"           = "Ryujinx --fullscreen";
    "gb"               = "retroarch --fullscreen -L /run/current-system/sw/lib/retroarch/cores/mgba_libretro.so";
    "gbc"              = "retroarch --fullscreen -L /run/current-system/sw/lib/retroarch/cores/mgba_libretro.so";
    "3ds"              = "retroarch --fullscreen -L /run/current-system/sw/lib/retroarch/cores/citra_libretro.so";
    "megadrive"        = "retroarch --fullscreen -L /run/current-system/sw/lib/retroarch/cores/genesis_plus_gx_libretro.so";
    "saturn"           = "retroarch --fullscreen -L /run/current-system/sw/lib/retroarch/cores/yabause_libretro.so";
    "psx"              = "retroarch --fullscreen -L /run/current-system/sw/lib/retroarch/cores/pcsx_rearmed_libretro.so";
    "psp"              = "retroarch --fullscreen -L /run/current-system/sw/lib/retroarch/cores/ppsspp_libretro.so";
    "nds"              = "retroarch --fullscreen -L /run/current-system/sw/lib/retroarch/cores/desmume_libretro.so";
    "pc"               = "retroarch --fullscreen -L /run/current-system/sw/lib/retroarch/cores/dosbox_libretro.so";
    "neogeo"           = "retroarch --fullscreen -L /run/current-system/sw/lib/retroarch/cores/fbneo_libretro.so";
    "mame"             = "retroarch --fullscreen -L /run/current-system/sw/lib/retroarch/cores/mame_libretro.so";
    "gamegear"         = "retroarch --fullscreen -L /run/current-system/sw/lib/retroarch/cores/genesis_plus_gx_libretro.so";
    "wonderswancolor"  = "retroarch --fullscreen -L /run/current-system/sw/lib/retroarch/cores/beetle_wswan_libretro.so";
    "ps2"              = "retroarch --fullscreen -L /run/current-system/sw/lib/retroarch/cores/pcsx2_libretro.so";
    "dreamcast"        = "retroarch --fullscreen -L /run/current-system/sw/lib/retroarch/cores/flycast_libretro.so";
    "atari2600"        = "retroarch --fullscreen -L /run/current-system/sw/lib/retroarch/cores/stella_libretro.so";
    "pcengine"         = "retroarch --fullscreen -L /run/current-system/sw/lib/retroarch/cores/beetle_pce_fast_libretro.so";
    "mastersystem"     = "retroarch --fullscreen -L /run/current-system/sw/lib/retroarch/cores/genesis_plus_gx_libretro.so";
  };
  
  platformMap = lib.filterAttrs (name: value: lib.elem name enabled) allPlatforms;
  platforms = builtins.attrNames platformMap;
  isRetroarchUsed = lib.any (p: lib.hasPrefix "retroarch" (allPlatforms.${p} or "")) enabled;
  
  isEnabled = p: lib.elem p enabled;

  # Directory & Pegasus Generation Rules
  romDirRules = map (p: 
    if p == "steam" then "d ${baseRomDir}/.steam 0755 ${user} users -"
    else "d ${baseRomDir}/${p} 0755 ${user} users -"
  ) platforms;

  pegasusRules = map (p: 
    if p == "steam" then "w+ /home/${user}/.config/pegasus-frontend/game_dirs.txt - - - - ${baseRomDir}/.steam/.metadata\\n"
    else "w+ /home/${user}/.config/pegasus-frontend/game_dirs.txt - - - - ${baseRomDir}/${p}/.metadata\\n"
  ) platforms;

  launchCase = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: cmd: ''
    "${name}") 
      LAUNCH_CMD="${cmd} '{file.path}'" 
      ;;''
  ) platformMap);

  minimis = pkgs.fetchFromGitHub {
    owner = "waldnercharles";
    repo = "Minimis";
    rev = "master";
    sha256 = "sha256-vi+BoNZWsnWDXF8j1uKSERrEAdYsfi9X1nSN9OYI5lA=";
  };

  steam-ghost-gen = pkgs.writeScriptBin "steam-ghost-gen" ''
    #!/bin/sh
    DEST="${baseRomDir}/.steam"
    mkdir -p "$DEST"
    VDF_FILE="$HOME/.local/share/Steam/steamapps/libraryfolders.vdf"
    if [ -f "$VDF_FILE" ]; then
      LIB_PATHS=$(grep "path" "$VDF_FILE" | sed 's/.*"path"[[:space:]]*"\(.*\)"/\1/')
      for LIB in $LIB_PATHS; do
        APPS_DIR="$LIB/steamapps"
        if [ -d "$APPS_DIR" ]; then
          ls "$APPS_DIR"/appmanifest_*.acf 2>/dev/null | xargs -n1 basename 2>/dev/null | \
          sed 's/appmanifest_\([0-9]*\)\.acf/\1.txt/' | xargs -I{} touch "$DEST/{}"
        fi
      done
    fi
  '';

  scrapeScript = pkgs.writeScriptBin "scrape-games" ''
    #!/bin/sh
    PLATFORM=''${1}
    shift
    EXTRA_FLAGS="$@ ${config.global.extraScrapeFlags}"
    
    ROM_DIR="${baseRomDir}/$PLATFORM"
    [ "$PLATFORM" = "steam" ] && ROM_DIR="${baseRomDir}/.steam"

    dedupe-folder "$ROM_DIR"
    OUT_DIR="$ROM_DIR/.metadata"

    case "$PLATFORM" in
      ${launchCase}
      *) LAUNCH_CMD="echo 'Unknown platform'; exit 1" ;;
    esac

    mkdir -p "$OUT_DIR"
    
    # PHASE 1: GATHER
    ${pkgs.skyscraper}/bin/Skyscraper -p "$PLATFORM" -s gamebase -i "$ROM_DIR" \
      $EXTRA_FLAGS
    ${pkgs.skyscraper}/bin/Skyscraper -p "$PLATFORM" -s arcadedb -i "$ROM_DIR" \
      $EXTRA_FLAGS
    ${pkgs.skyscraper}/bin/Skyscraper -p "$PLATFORM" -s esgameslist -i "$ROM_DIR" \
      $EXTRA_FLAGS
    ${pkgs.skyscraper}/bin/Skyscraper -p "$PLATFORM" -s mobygames -i "$ROM_DIR" \
     $EXTRA_FLAGS
    ${pkgs.skyscraper}/bin/Skyscraper -p "$PLATFORM" -s openretro -i "$ROM_DIR" \
      $EXTRA_FLAGS
    ${pkgs.skyscraper}/bin/Skyscraper -p "$PLATFORM" -s thegamesdb -i "$ROM_DIR" \
      $EXTRA_FLAGS
    ${pkgs.skyscraper}/bin/Skyscraper -p "$PLATFORM" -s screenscraper -i "$ROM_DIR" \
      -u "${config.global.screenscraperUser}" \
      $EXTRA_FLAGS
      
    # PHASE 2: EXPORT
    ${pkgs.skyscraper}/bin/Skyscraper -p "$PLATFORM" -f pegasus -i "$ROM_DIR" \
      -g "$OUT_DIR" -o "$OUT_DIR" -a /etc/skyscraper/artwork.xml -e "$LAUNCH_CMD" \
      --flags unattend,symlink,videos,manuals,fanarts,nobrackets,theinfront,backcovers $EXTRA_FLAGS
  '';

  scrapeAllScript = pkgs.writeScriptBin "scrape-all-games" ''
    #!/bin/sh
    NEW_BASE="${baseRomDir}"
    
    echo "--- 1. EXTRACTION PHASE ---"
    find "$NEW_BASE" -type f \( -name "*.zip" -o -name "*.rar" -o -name "*.7z" \) |
    while read -r archive; do
      sys_folder=$(basename "$(dirname "$archive")")
      dir=$(dirname "$archive")

      echo "Extracting: $(basename "$archive")"

      case "$archive" in
        *.zip)
          # -j: junk paths (extracts all files directly into $dir)
          ${pkgs.unzip}/bin/unzip -o -j "$archive" -d "$dir" && rm "$archive"
          ;;
        *.rar)
          # e: extract to current dir (ignoring paths)
          cd "$dir" && ${pkgs.unrar}/bin/unrar e -o+ "$archive" && rm "$archive"
          ;;
        *.7z)
          # e: extract (ignoring paths)
          ${pkgs.p7zip}/bin/7z e -y -o"$dir" "$archive" && rm "$archive"
          ;;
      esac

      # If it's a Dolphin system, run conversion after extraction
      if [ "$sys_folder" = "gc" ] || [ "$sys_folder" = "gamecube" ] || [ "$sys_folder" = "wii" ]; then
          find "$dir" -type f \( -name "*.iso" -o -name "*.wbfs" \) |
          while read -r iso; do
            echo "Converting $iso to RVZ..."
            ${pkgs.dolphin-emu}/bin/DolphinTool convert --format=rvz --input="$iso" --output="''${iso%.*}.rvz" && \
            rm "$iso"
          done
      fi
    done

    echo "--- 2. MIGRATION CHECK ---"
    STATE_FILE="$HOME/.skyscraper/.last_rom_dir"
    if [ -f "$STATE_FILE" ]; then
      OLD_BASE=$(cat "$STATE_FILE")
    else
      OLD_BASE="$NEW_BASE"
      echo "$NEW_BASE" > "$STATE_FILE"
    fi

    if [ "$OLD_BASE" != "$NEW_BASE" ] && [ -d "$OLD_BASE" ]; then
      echo "Moving ROMs from $OLD_BASE to $NEW_BASE..."
      mkdir -p "$NEW_BASE"
      mv "$OLD_BASE"/* "$NEW_BASE/" 2>/dev/null
      echo "$NEW_BASE" > "$STATE_FILE"
    fi

    echo "--- 3. GLOBAL SCRAPE PHASE ---"
    for sys in ${lib.concatStringsSep " " platforms}; do
      echo "--- Processing $sys ---"
      ${scrapeScript}/bin/scrape-games "$sys" "$@"
    done
    
    echo "--- DONE! Pegasus library refreshed ---"
  '';

in {
  imports = [ ./helper_scripts/delete_duplicate_files.nix ];

  environment.systemPackages = with pkgs; [
    # --- CORE TOOLS (Always Installed) ---
    pegasus-frontend 
    skyscraper 
    scrapeScript 
    scrapeAllScript
    atool 
    unrar 
    unzip 
    p7zip 
    ffmpeg-full
  ] 
  # --- DYNAMIC EMULATORS (Installed only if in global list) ---
  
  # Only install RetroArch if any enabled platform uses it
  ++ lib.optional isRetroarchUsed retroarch
  
  # RetroArch Cores (Only installed if the specific platform is enabled)
  ++ lib.optional (isEnabled "gba" || isEnabled "gb" || isEnabled "gbc") libretro.mgba
  ++ lib.optional (isEnabled "nds") libretro.desmume
  ++ lib.optional (isEnabled "n64") libretro.parallel-n64
  ++ lib.optional (isEnabled "snes") libretro.snes9x
  ++ lib.optional (isEnabled "nes") libretro.nestopia
  ++ lib.optional (isEnabled "3ds") libretro.citra
  ++ lib.optional (isEnabled "psx") libretro.pcsx_rearmed
  ++ lib.optional (isEnabled "psp") libretro.ppsspp
  ++ lib.optional (isEnabled "megadrive" || isEnabled "gamegear" || isEnabled "mastersystem") libretro.genesis-plus-gx
  ++ lib.optional (isEnabled "neogeo") libretro.fbneo
  ++ lib.optional (isEnabled "mame") libretro.mame
  ++ lib.optional (isEnabled "pcengine") libretro.beetle-pce-fast
  ++ lib.optional (isEnabled "ps2") libretro.pcsx2
  ++ lib.optional (isEnabled "dreamcast") libretro.flycast
  ++ lib.optional (isEnabled "atari2600") libretro.stella
  
  # Standalone Emulators
  #++ lib.optional (isEnabled "wiiu") cemu
  ++ lib.optional (isEnabled "gc" || isEnabled "wii") dolphin-emu;

  environment.etc."skyscraper/artwork.xml".text = ''
    <?xml version="1.0" encoding="UTF-8"?>
    <artwork>
      <output type="screenshot" name="screenshot"/>
      <output type="video" name="video"/>
      <output type="cover" name="boxFront"/>
      <output type="wheel" name="logo"/>
      <output type="marquee" name="marquee"/>
    </artwork>'';

  systemd.tmpfiles.rules = [
    "d ${baseRomDir} 0755 ${user} users -"
    "d /home/${user}/.config/pegasus-frontend 0755 ${user} users -"
    "f+ /home/${user}/.config/pegasus-frontend/game_dirs.txt 0644 ${user} users -"
    "L+ /home/${user}/.config/pegasus-frontend/themes/Minimis - - - - ${minimis}"
    "L+ /home/${user}/.skyscraper/artwork.xml 0644 ${user} users - /etc/skyscraper/artwork.xml"
  ] ++ romDirRules ++ pegasusRules;

  systemd.user.services.pegasus-autoscrape = {
    description = "Automatically scrape ROM metadata for Pegasus";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "auto-scrape-task" ''
        ${scrapeAllScript}/bin/scrape-all-games
      ''}";
    };
  };
}
