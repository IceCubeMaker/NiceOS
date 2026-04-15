{ config, pkgs, lib, ... }:

let
  dManager = config.global.default_desktop_environment;

  greeterWpDir   = "/var/cache/greeter-wallpaper";
  greeterCssFile = "${greeterWpDir}/style.css";

  # Minimal sway config just for the greeter session.
  # sway is a much more reliable compositor host for gtkgreet than cage —
  # cage's wlroots backend selection is fragile at boot without $DISPLAY.
  swayGreeterConfig = pkgs.writeText "sway-greetd-config" ''
    # Disable the default bar and borders — greeter only
    bar { mode hide }
    default_border none
    default_floating_border none

    # Wallpaper — set via CSS in gtkgreet, but sway needs something here.
    # output * bg #1e1e2e solid_color

    # Launch gtkgreet, then exit sway when it closes
    exec "${pkgs.greetd.gtkgreet}/bin/gtkgreet \
      --sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions \
      --style ${greeterCssFile}; \
      swaymsg exit"
  '';

in
{
  # ── greetd + sway + gtkgreet ─────────────────────────────────────────────
  #
  # sway is used only as the greeter compositor — it starts, runs gtkgreet,
  # then immediately exits. This avoids the cage wlroots/X11 backend issue
  # that occurs when cage can't detect the display backend at boot.
  #
  # Wallpaper sync: wp-change calls wp-sync-greeter after every switch, keeping
  # /var/cache/greeter-wallpaper/style.css up to date. Without niri/wp-change
  # the greeter shows the dark fallback below — no errors, no missing files.
  #
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.sway}/bin/sway --config ${swayGreeterConfig}";
        user = "greeter";
      };
    };
  };

  services.displayManager.defaultSession = dManager;

  # sway needs to be able to find session files
  environment.systemPackages = [
    pkgs.sway
    pkgs.greetd.gtkgreet
  ];

  # Required for sway to start without a seat manager conflict
  security.polkit.enable = true;

  # ── Greeter wallpaper cache ───────────────────────────────────────────────
  # Creating this directory opts in to wallpaper syncing.
  # wp-sync-greeter checks for its existence before doing anything.
  system.activationScripts.greeter-wallpaper-dir = {
    text = ''
      mkdir -p "${greeterWpDir}"
      chmod 755 "${greeterWpDir}"

      # Dark fallback so gtkgreet doesn't crash before wp-sync-greeter runs.
      if [ ! -f "${greeterCssFile}" ]; then
        printf 'window { background-color: #1e1e2e; }\n' > "${greeterCssFile}"
        chmod 644 "${greeterCssFile}"
      fi
    '';
  };
}
