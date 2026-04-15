{ config, pkgs, lib, ... }:

let
  dManager = config.global.default_desktop_environment;

  # Fixed path that wp-sync-greeter keeps updated after every wp-change.
  # sddm-astronaut reads this at greeter startup so it always shows the
  # most recently used wallpaper.
  sddmWpFile = "/var/cache/greeter-wallpaper/current";

  # Build the theme with the background pointing at our synced wallpaper.
  # On first boot the file won't exist yet — the theme falls back to its
  # own default astronaut background gracefully.
  sddmTheme = pkgs.sddm-astronaut.override {
    embeddedTheme = "astronaut";
    themeConfig = {
      background        = sddmWpFile;
      BackgroundMode    = "fill";
      # Keep the rest of the astronaut aesthetic
      blur              = false;
    };
  };

in
{
  services.displayManager.sddm = {
    enable       = true;
    package      = lib.mkForce pkgs.kdePackages.sddm;
    theme        = "sddm-astronaut-theme";
    wayland.enable = true;
    extraPackages = [
      sddmTheme
      pkgs.kdePackages.qtsvg
      pkgs.kdePackages.qtmultimedia
      pkgs.kdePackages.qtvirtualkeyboard
    ];
  };

  services.displayManager.defaultSession = dManager;

  environment.systemPackages = [ sddmTheme ];

  # ── Greeter wallpaper cache ───────────────────────────────────────────────
  # Same shared dir used by greetd — wp-sync-greeter is DM-agnostic.
  # Creating it here opts in to wallpaper syncing for SDDM.
  system.activationScripts.greeter-wallpaper-dir = {
    text = ''
      mkdir -p /var/cache/greeter-wallpaper
      chmod 755 /var/cache/greeter-wallpaper

      # On first boot seed a dark fallback so SDDM doesn't show a broken image.
      # Once wp-change runs it will be replaced with the real wallpaper.
      if [ ! -f "${sddmWpFile}" ]; then
        cp ${pkgs.nixos-artwork.wallpapers.simple-dark-gray}/share/backgrounds/nixos/nix-wallpaper-simple-dark-gray.png \
          "${sddmWpFile}" 2>/dev/null || true
        chmod 644 "${sddmWpFile}" 2>/dev/null || true
      fi
    '';
  };
}
