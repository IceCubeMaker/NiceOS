{ config, pkgs, lib, ... }:
let
  dManager = config.global.default_desktop_environment;
  paletteScript = "/var/cache/greeter-wallpaper/tty-palette.sh";
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
    printf '\e]PE89dcheb'   # sky
    printf '\e]PFcdd6f4'   # text
    clear
  '';
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
      animate        = false;
      bigclock       = true;
      clock          = "%H:%M — %A %d %b";
      hide_borders   = false;
      bg             = 1;
      fg             = 8;
      blank_password = true;
      load           = true;
      save           = true;
      vi_mode        = false;
      term_reset_cmd = "${applyPalette}";
    };
  };

  services.displayManager.defaultSession = dManager;

  # Run palette script before ly starts without clobbering ly's generated unit
  systemd.services.ly-palette = {
    description = "Apply TTY palette before ly";
    wantedBy = [ "ly.service" ];
    before = [ "ly.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${applyPalette}";
    };
  };

  system.activationScripts.greeter-wallpaper-dir = {
    text = ''
      mkdir -p /var/cache/greeter-wallpaper
      chmod 755 /var/cache/greeter-wallpaper
      if [ ! -f /var/cache/greeter-wallpaper/style.css ]; then
        printf 'window { background-color: #1e1e2e; }\n' \
          > /var/cache/greeter-wallpaper/style.css
        chmod 644 /var/cache/greeter-wallpaper/style.css
      fi
    '';
  };

  console.colors = [
    "1e1e2e" "f38ba8" "a6e3a1" "f9e2af"
    "89b4fa" "cba6f7" "89dceb" "cdd6f4"
    "585b70" "f38ba8" "a6e3a1" "f9e2af"
    "89b4fa" "cba6f7" "89dceb" "cdd6f4"
  ];
}