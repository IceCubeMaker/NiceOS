{ lib, config, pkgs, ... }:

{

  options.global = {

    ##### GENERAL SETTINGS #############################################

    user     = lib.mkOption { type = lib.types.str; default = "franz"; };
    timeZone = lib.mkOption { type = lib.types.str; default = "Europe/Oslo"; };

    # Controls both the WM/DE loaded by niri-setup.nix and the DM default session.
    # Options: "niri"  "gnome"  "plasma"  "hyprland"
    default_desktop_environment = lib.mkOption {
      type    = lib.types.str;
      default = "niri";
    };

    # ── Display manager selector (informational) ────────────────────
    # Must match the uncommented import above.
    # Options: "sddm"  "gdm"  "cosmic-greeter"  "ly"  "lemurs"  "greetd"
    display_manager = lib.mkOption {
      type    = lib.types.enum [ "sddm" "gdm" "cosmic-greeter" "ly" "lemurs" "greetd" ];
      default = "ly";
      description = ''
        Which display manager is currently active. Must match the
        uncommented import in the imports list:

          greetd         → ./DisplayManagers/greetd-setup.nix   ★ recommended for niri
          ly             → ./DisplayManagers/ly-setup.nix
          lemurs         → ./DisplayManagers/lemurs-setup.nix
          sddm           → ./DisplayManagers/sddm_setup.nix
          gdm            → ./DisplayManagers/gdm-setup.nix
          cosmic-greeter → ./DisplayManagers/cosmic-greeter-setup.nix

        Quick comparison:
          greetd         — gtkgreet+cage; wallpaper syncs from wp-change automatically
          ly             — minimal TUI, single file, zero dependencies
          lemurs         — TUI in Rust, themeable via TOML (needs seat group)
          sddm           — polished graphical greeter, QML-themed
          gdm            — GNOME DM, heavy but rock-solid
          cosmic-greeter — COSMIC/Rust DM, pulls in cosmic-comp for greeter session
      '';
    };

    defaultBrowser   = lib.mkOption { type = lib.types.package; default = pkgs.firefox; };
    defaultTerminal  = lib.mkOption { type = lib.types.package; default = pkgs.kitty; };
    defaultShell     = lib.mkOption { type = lib.types.str;     default = "fish"; };
    bluetoothEnabled = lib.mkOption { type = lib.types.bool;    default = true; };
    isLaptop         = lib.mkOption { type = lib.types.bool;    default = false; };

    # Set to true on ASUS TUF/ROG hardware to enable asusd + keyboard RGB sync.
    # On other machines this is a no-op — wp-rgb itself also exits silently
    # if the ASUS sysfs LED interface isn't present.
    asusLaptop       = lib.mkOption { type = lib.types.bool;    default = false; };

    # ── Niri visual effects ─────────────────────────────────────────────────
    # Enable blur, rounded corners, shadows, and transparency effects in niri.
    # Requires niri with blur support (currently in an unmerged PR).
    # Safe to set true now — the config is generated correctly either way.
    # Flip to true once blur lands in a stable niri release.
    niriBlur         = lib.mkOption { type = lib.types.bool;    default = false; };

    #### GAMING SETUP ##################################################

    extraScrapeFlags   = lib.mkOption { type = lib.types.str; default = "--flags unattend,symlink,videos,manuals,fanarts,nobrackets,theinfront,backcovers"; };
    romDir             = lib.mkOption { type = lib.types.str; default = "/home/franz/Games/ROMs"; };
    screenscraperUser = lib.mkOption { type = lib.types.str; default = ""; };
    emulationPlatforms = lib.mkOption {
      type        = lib.types.listOf lib.types.str;
      default     = [ "nintendo" ];
      description = "List of platforms to enable (e.g., [ 'snes' 'gba' 'ps2' ], or [ 'nintendo' '8-bit' 'handhelds'])";
    };

    ### STUDYING SETUP #################################################

    pomodoroTimer     = lib.mkOption { type = lib.types.package; default = pkgs.solanum; };
    noteTakingProgram = lib.mkOption { type = lib.types.package; default = pkgs.obsidian; };
    syncService       = lib.mkOption { type = lib.types.package; default = pkgs.syncthing; };
  };
}
