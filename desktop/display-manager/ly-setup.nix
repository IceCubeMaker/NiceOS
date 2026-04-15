{ config, pkgs, lib, ... }:

let
  dManager = config.global.default_desktop_environment;

  # Path written by wp-sync-greeter after every wp-change.
  # Contains printf escape sequences setting the 16 TTY palette colors
  # derived from the current wallpaper via matugen.
  paletteScript = "/var/cache/greeter-wallpaper/tty-palette.sh";

  # Fallback palette used on first boot before wp-sync-greeter has run,
  # and re-applied after logout via term_reset_cmd so colors don't revert.
  # Uses Catppuccin Mocha as the static baseline.
  fallbackPalette = pkgs.writeShellScript "ly-palette-fallback" ''
    printf '\e]P01e1e2e'   # base
    printf '\e]P1f38ba8'   # red
    printf '\e]P2a6e3a1'   # green
    printf '\e]P3f9e2af'   # yellow
    printf '\e]P489b4fa'   # blue
    printf '\e]P5cba6f7'   # mauve
    printf '\e]P689dceb'   # sky
    printf '\e]P7cdd6f4'   # text
    printf '\e]P8585b70'   # surface2
    printf '\e]P9f38ba8'   # red
    printf '\e]PAa6e3a1'   # green
    printf '\e]PBf9e2af'   # yellow
    printf '\e]PC89b4fa'   # blue
    printf '\e]PDcba6f7'   # mauve
    printf '\e]PE89dceb'   # sky
    printf '\e]PFcdd6f4'   # text
    clear
  '';

  # Apply the wallpaper-derived palette if available, else fall back.
  applyPalette = pkgs.writeShellScript "ly-apply-palette" ''
    if [ -x "${paletteScript}" ]; then
      "${paletteScript}"
    else
      "${fallbackPalette}"
    fi
  '';

in
{
  services.displayManager.ly = {
    enable = true;
    settings = {
      # ── Visuals ─────────────────────────────────────────────────
      animate        = false;    # no animation — keep it clean
      bigclock       = true;     # large ASCII block clock top-center
      clock          = "%H:%M — %A %d %b";
      hide_borders   = false;

      # Dialog box colors — 1=black(→ our base), 8=white(→ our text)
      # With the TTY palette set to matugen colors, these map correctly.
      bg             = 1;
      fg             = 8;

      blank_password = true;
      load           = true;
      save           = true;
      vi_mode        = false;

      # Re-apply palette after logout so colors don't revert to TTY defaults
      term_reset_cmd = "${applyPalette}";
    };
  };

  services.displayManager.defaultSession = dManager;

  # Apply the palette before ly starts via the systemd service.
  # This sets the full-screen background color — ly's bg= only affects
  # the dialog box, not the whole terminal background.
  systemd.services.ly = {
    serviceConfig = {
      ExecStartPre = "${applyPalette}";
    };
  };

  # ── Greeter wallpaper cache ───────────────────────────────────────────────
  # Creating this directory opts in to wallpaper syncing for all DMs.
  # wp-sync-greeter writes tty-palette.sh here after each wp-change.
  system.activationScripts.greeter-wallpaper-dir = {
    text = ''
      mkdir -p /var/cache/greeter-wallpaper
      chmod 755 /var/cache/greeter-wallpaper
      # Seed fallback CSS for if greetd is ever enabled
      if [ ! -f /var/cache/greeter-wallpaper/style.css ]; then
        printf 'window { background-color: #1e1e2e; }\n' \
          > /var/cache/greeter-wallpaper/style.css
        chmod 644 /var/cache/greeter-wallpaper/style.css
      fi
    '';
  };

  # Fallback console colors at kernel level (used before ly starts)
  console.colors = [
    "1e1e2e" "f38ba8" "a6e3a1" "f9e2af"
    "89b4fa" "cba6f7" "89dceb" "cdd6f4"
    "585b70" "f38ba8" "a6e3a1" "f9e2af"
    "89b4fa" "cba6f7" "89dceb" "cdd6f4"
  ];
}
