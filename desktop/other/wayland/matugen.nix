# matugen.nix
#
# Matugen Material You colour engine — templates and config.
# Works under any Wayland compositor. The niri-specific template
# (niri.kdl) is kept in niri-setup.nix and registered there.
#
# Templates managed here:
#   waybar-style.css       waybar colours
#   gtk.css                GTK3 colour overrides (imports thunar.css)
#   thunar.css             Thunar-specific GTK3 overrides
#   fuzzel.ini             fuzzel launcher colours
#   kitty-colors.conf      kitty terminal palette
#   swaync.css             SwayNotificationCenter colours
#   swaync-config.json     SwayNC layout/behaviour config
#   swayosd.css.template   SwayOSD volume/brightness popup style
#
# Place at: /etc/nixos/matugen.nix
# Import in: configuration.nix

{ config, pkgs, lib, ... }:

let
  username = config.global.user;

  # ── Templates (writeText so they land in the Nix store) ───────────────────

  waybarTemplate = pkgs.writeText "waybar-style.css" ''
    /* Colours injected by matugen — do not edit by hand */

    @define-color primary         {{colors.primary.default.hex}};
    @define-color on_primary      {{colors.on_primary.default.hex}};
    @define-color secondary       {{colors.secondary.default.hex}};
    @define-color tertiary        {{colors.tertiary.default.hex}};
    @define-color error           {{colors.error.default.hex}};
    @define-color surface         {{colors.surface.default.hex}};
    @define-color on_surface      {{colors.on_surface.default.hex}};
    @define-color surface_variant {{colors.surface_variant.default.hex}};
    @define-color outline_variant {{colors.outline_variant.default.hex}};

    * {
        font-family: "JetBrainsMono Nerd Font", "Symbols Nerd Font", sans-serif;
        font-size: 13px;
        border: none;
        border-radius: 0;
        transition: background-color 0.4s ease, color 0.4s ease;
    }

    @keyframes waybar-fadein {
        from { opacity: 0; }
        to   { opacity: 1; }
    }

    window#waybar {
        background-color: alpha(@surface, 0.85);
        color: @on_surface;
        border-radius: 12px;
        border: 1px solid alpha(@primary, 0.2);
        min-height: 36px;
        animation: waybar-fadein 0.4s ease-out;
        transition: opacity 0.4s ease;
    }

    window#waybar.fade-out { opacity: 0; }

    #workspaces {
        background-color: alpha(@surface_variant, 0.2);
        margin: 4px;
        padding: 0 4px;
        border-radius: 8px;
    }

    #workspaces button {
        padding: 0 7px;
        color: alpha(@on_surface, 0.5);
        border-radius: 6px;
        transition: background-color 0.2s ease, color 0.2s ease;
    }

    #workspaces button:hover {
        background-color: alpha(@primary, 0.1);
        color: @on_surface;
    }

    #workspaces button.active {
        color: @primary;
        background-color: alpha(@primary, 0.18);
        border-bottom: 2px solid @primary;
    }

    #workspaces button.urgent {
        color: @error;
        background-color: alpha(@error, 0.15);
        animation: urgent-pulse 1s ease infinite;
    }

    @keyframes urgent-pulse {
        from { background-color: alpha(@error, 0.15); }
        to   { background-color: alpha(@error, 0.35); }
    }

    #window {
        padding: 0 12px;
        margin: 4px 2px;
        color: alpha(@on_surface, 0.75);
        font-style: italic;
    }

    #clock {
        padding: 0 14px;
        margin: 4px 2px;
        background-color: alpha(@surface_variant, 0.2);
        border-radius: 8px;
        font-weight: bold;
        color: @primary;
        transition: background-color 0.2s ease;
    }

    #clock:hover { background-color: alpha(@primary, 0.12); }

    #pulseaudio, #network, #battery, #cpu, #memory,
    #custom-bluelight, #custom-wallpaper, #tray {
        padding: 0 12px;
        margin: 4px 2px;
        background-color: alpha(@surface_variant, 0.2);
        border-radius: 8px;
        transition: background-color 0.2s ease, color 0.2s ease;
    }

    #pulseaudio:hover, #network:hover, #battery:hover,
    #cpu:hover, #memory:hover, #custom-wallpaper:hover {
        background-color: alpha(@primary, 0.12);
    }

    #pulseaudio.muted {
        color: alpha(@on_surface, 0.4);
        background-color: alpha(@surface_variant, 0.1);
        animation: muted-fade 2s ease-in-out infinite;
    }

    @keyframes muted-fade {
        from { opacity: 1.0; }
        to   { opacity: 0.4; }
    }

    #network.disconnected {
        color: alpha(@on_surface, 0.4);
        background-color: alpha(@surface_variant, 0.1);
    }

    #battery.charging {
        color: @tertiary;
        background-color: alpha(@tertiary, 0.12);
    }
    #battery.plugged { color: @tertiary; }

    #battery.warning {
        color: @secondary;
        background-color: alpha(@secondary, 0.12);
        animation: warning-pulse 2s ease infinite;
    }

    #battery.critical {
        color: @error;
        background-color: alpha(@error, 0.15);
        animation: critical-blink 1s ease infinite;
    }

    @keyframes warning-pulse {
        from { background-color: alpha(@secondary, 0.08); }
        to   { background-color: alpha(@secondary, 0.25); }
    }

    @keyframes critical-blink {
        from { background-color: alpha(@error, 0.15); }
        to   { background-color: alpha(@error, 0.4); }
    }

    #cpu, #memory { color: @secondary; }
    #cpu:hover, #memory:hover { color: @on_surface; }

    #custom-bluelight {
        color: alpha(@on_surface, 0.5);
        padding: 0 10px;
        transition: background-color 0.2s ease, color 0.2s ease;
    }

    #custom-bluelight.active {
        color: #f4a261;
        background-color: rgba(244, 162, 97, 0.13);
    }

    #custom-bluelight.active:hover  { background-color: rgba(244, 162, 97, 0.21); }
    #custom-bluelight.inactive:hover {
        background-color: alpha(@primary, 0.1);
        color: @on_surface;
    }

    #custom-wallpaper {
        color: @primary;
        padding: 0 10px;
        transition: background-color 0.2s ease;
    }

    #custom-wallpaper:hover {
        background-color: alpha(@primary, 0.15);
        animation: spin 0.6s ease;
    }

    #custom-airplane {
        padding: 0 12px;
        margin: 4px 2px;
        background-color: alpha(@surface_variant, 0.2);
        border-radius: 8px;
        transition: background-color 0.2s ease, color 0.2s ease;
    }

    #custom-airplane:hover          { background-color: alpha(@primary, 0.12); }
    #custom-airplane.airplane-on    { color: @primary; text-shadow: 0 0 2px alpha(@primary, 0.4); }
    #custom-airplane.airplane-off   { color: alpha(@on_surface, 0.5); }

    #custom-mode {
        padding: 0 10px;
        margin: 4px 2px;
        background-color: alpha(@surface_variant, 0.2);
        border-radius: 8px;
        transition: background-color 0.2s ease, color 0.2s ease;
        font-size: 15px;
    }

    #custom-mode:hover              { background-color: alpha(@primary, 0.12); }
    #custom-mode.mode-silent        { color: alpha(@on_surface, 0.35); }
    #custom-mode.mode-balanced      { color: @on_surface; }
    #custom-mode.mode-performance   {
        color: @tertiary;
        background-color: alpha(@tertiary, 0.10);
        text-shadow: 0 0 4px alpha(@tertiary, 0.5);
    }

    @keyframes spin {
        from { -gtk-icon-transform: rotate(0deg); }
        to   { -gtk-icon-transform: rotate(360deg); }
    }

    #tray { padding: 0 8px; }
    #tray > .passive { -gtk-icon-effect: dim; }
    #tray > .needs-attention {
        -gtk-icon-effect: highlight;
        background-color: alpha(@error, 0.15);
        animation: critical-blink 1s ease infinite;
    }

    @import url("fadeout-override.css");
  '';

  gtkTemplate = pkgs.writeText "gtk.css" ''
    @define-color primary {{colors.primary.default.hex}};
    @define-color on_primary {{colors.on_primary.default.hex}};
    @define-color secondary {{colors.secondary.default.hex}};
    @define-color surface {{colors.surface.default.hex}};
    @define-color on_surface {{colors.on_surface.default.hex}};
    @define-color surface_variant {{colors.surface_variant.default.hex}};
    @define-color on_surface_variant {{colors.on_surface_variant.default.hex}};
    @define-color outline_variant {{colors.outline_variant.default.hex}};

    @import url("thunar.css");
  '';

  thunarTemplate = pkgs.writeText "thunar.css" ''
    /* Thunar — matugen-driven overrides.
       gtk.css (which @imports this file) already defines the @define-color
       variables, so we can use alpha(@name, x) freely here. */

    .sidebar, placessidebar {
        background-color: alpha(@surface_variant, 0.6);
        color: @on_surface_variant;
        border-right: 1px solid alpha(@outline_variant, 0.4);
    }

    placessidebar row:selected,
    placessidebar row:selected label,
    placessidebar row:selected image {
        background-color: alpha(@primary, 0.18);
        color: @primary;
    }

    placessidebar row:hover { background-color: alpha(@primary, 0.08); }

    placessidebar .sidebar-section-header {
        color: alpha(@on_surface_variant, 0.6);
        font-size: 0.75em;
        font-weight: bold;
        letter-spacing: 0.08em;
        padding: 6px 8px 2px;
    }

    headerbar, .headerbar, toolbar {
        background-color: @surface;
        color: @on_surface;
        border-bottom: 1px solid alpha(@outline_variant, 0.4);
        box-shadow: none;
    }

    headerbar button, toolbar button {
        border: none;
        background: transparent;
        transition: background-color 0.15s ease;
    }

    headerbar button:hover, toolbar button:hover {
        background-color: alpha(@primary, 0.1);
        color: @primary;
    }

    headerbar button:active, toolbar button:active {
        background-color: alpha(@primary, 0.2);
    }

    .view, iconview, treeview {
        background-color: @surface;
        color: @on_surface;
    }

    iconview:selected, treeview:selected {
        background-color: alpha(@primary, 0.2);
        color: @primary;
    }

    iconview:selected:focus, treeview:selected:focus {
        background-color: alpha(@primary, 0.3);
        color: @on_primary;
    }

    iconview text {
        color: @on_surface;
        background-color: transparent;
    }

    iconview:selected text {
        color: @primary;
        background-color: alpha(@primary, 0.1);
        border-radius: 4px;
    }

    rubberband {
        background-color: alpha(@primary, 0.15);
        border: 1px solid alpha(@primary, 0.6);
        border-radius: 2px;
    }

    .path-bar button {
        color: @on_surface_variant;
        border-radius: 6px;
        padding: 0 8px;
    }

    .path-bar button:hover {
        background-color: alpha(@primary, 0.1);
        color: @primary;
    }

    .path-bar button.current-dir {
        color: @primary;
        font-weight: bold;
    }

    .statusbar {
        background-color: alpha(@surface_variant, 0.4);
        color: @on_surface_variant;
        border-top: 1px solid alpha(@outline_variant, 0.25);
        font-size: 0.9em;
        padding: 2px 8px;
    }

    scrollbar slider {
        background-color: alpha(@outline_variant, 0.6);
        border-radius: 4px;
        min-width: 6px;
        min-height: 6px;
    }

    scrollbar slider:hover { background-color: alpha(@primary, 0.6); }
  '';

  fuzzelTemplate = pkgs.writeText "fuzzel.ini" ''
    [main]
    font=JetBrainsMono Nerd Font:size=12
    dpi-aware=yes
    width=35
    lines=10
    horizontal-pad=16
    vertical-pad=12
    inner-pad=8
    border-size=2
    radius=12
    layer=overlay
    exit-on-keyboard-focus-loss=yes

    [colors]
    background={{colors.surface.default.hex_stripped}}cc
    text={{colors.on_surface.default.hex_stripped}}ff
    match={{colors.primary.default.hex_stripped}}ff
    selection={{colors.primary_container.default.hex_stripped}}ff
    selection-text={{colors.on_primary_container.default.hex_stripped}}ff
    selection-match={{colors.primary.default.hex_stripped}}ff
    border={{colors.primary.default.hex_stripped}}cc
  '';

  kittyTemplate = pkgs.writeText "kitty-colors.conf" ''
    foreground            {{colors.on_surface.default.hex}}
    background            {{colors.surface.default.hex}}
    selection_foreground  {{colors.on_primary.default.hex}}
    selection_background  {{colors.primary.default.hex}}
    cursor                {{colors.primary.default.hex}}
    cursor_text_color     {{colors.on_primary.default.hex}}
    url_color             {{colors.tertiary.default.hex}}

    color0   {{colors.surface_variant.default.hex}}
    color8   {{colors.outline.default.hex}}
    color1   {{colors.error.default.hex}}
    color9   {{colors.error.default.hex}}
    color2   {{colors.tertiary.default.hex}}
    color10  {{colors.tertiary.default.hex}}
    color3   {{colors.secondary.default.hex}}
    color11  {{colors.secondary_container.default.hex}}
    color4   {{colors.primary.default.hex}}
    color12  {{colors.primary_container.default.hex}}
    color5   {{colors.tertiary_container.default.hex}}
    color13  {{colors.on_tertiary_container.default.hex}}
    color6   {{colors.secondary.default.hex}}
    color14  {{colors.on_secondary_container.default.hex}}
    color7   {{colors.on_surface_variant.default.hex}}
    color15  {{colors.on_surface.default.hex}}

    active_tab_foreground   {{colors.on_primary.default.hex}}
    active_tab_background   {{colors.primary.default.hex}}
    inactive_tab_foreground {{colors.on_surface_variant.default.hex}}
    inactive_tab_background {{colors.surface_variant.default.hex}}
  '';

  swayncTemplate = pkgs.writeText "swaync.css" ''
    @define-color bg alpha({{colors.surface.default.hex}}, 0.8);
    @define-color fg {{colors.on_surface.default.hex}};
    @define-color primary {{colors.primary.default.hex}};
    @define-color outline {{colors.outline_variant.default.hex}};

    * { font-family: "JetBrainsMono Nerd Font"; }

    .notification {
      background: @bg;
      border: 1px solid alpha(@primary, 0.4);
      border-radius: 16px;
      color: @fg;
      margin: 8px;
      padding: 0px;
      box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
    }

    .notification-content { padding: 14px; }

    .summary {
      font-size: 15px;
      font-weight: bold;
      color: @primary;
    }

    .body { font-size: 13px; color: @fg; }

    .close-button {
      background: alpha(@primary, 0.1);
      color: @fg;
      text-shadow: none;
      margin: 10px;
      border-radius: 100%;
    }

    .close-button:hover { background: alpha(@primary, 0.3); }
  '';

  swayncConfigTemplate = pkgs.writeText "swaync-config.json" ''
    {
      "$schema": "https://github.com/ErikReider/SwayNotificationCenter/blob/main/src/config.schema.json",
      "positionX": "center",
      "positionY": "top",
      "layer": "overlay",
      "control-center-margin-top": 10,
      "hide-on-action": true,
      "notification-icon-size": 80,
      "notification-body-image-height": 100,
      "notification-body-image-width": 200,
      "timeout": 2,
      "widgets": [
        "notifications",
        "title",
        "dnd"
      ]
    }
  '';

  swayosdTemplate = pkgs.writeText "swayosd.css.template" ''
    @keyframes fadeSlide {
      0%   { opacity: 0; transform: translateY(6px); }
      100% { opacity: 1; transform: translateY(0);   }
    }

    window {
        background: alpha({{colors.surface.default.hex}}, 0.92);
        border-radius: 20px;
        padding: 10px 18px;
        border: 1px solid alpha({{colors.primary.default.hex}}, 0.3);
        box-shadow: 0 8px 16px rgba(0, 0, 0, 0.3);
        min-width: 260px;
        animation: fadeSlide 0.15s ease-out;
    }

    .box  { margin: 0; padding: 0; }

    .icon {
        font-size: 24px;
        font-family: "JetBrainsMono Nerd Font", "Symbols Nerd Font";
        color: {{colors.primary.default.hex}};
        margin-right: 12px;
    }

    .bar {
        background-color: alpha({{colors.surface_variant.default.hex}}, 0.6);
        border-radius: 10px;
        min-height: 4px;
    }

    .bar .filled {
        background: linear-gradient(90deg, {{colors.primary.default.hex}}, {{colors.tertiary.default.hex}});
        border-radius: 10px;
        transition: width 0.08s cubic-bezier(0.2, 0.9, 0.4, 1.1);
    }

    .label {
        font-size: 14px;
        font-weight: bold;
        color: {{colors.on_surface.default.hex}};
        margin-left: 8px;
    }
  '';

in
{
  # ── Install template files ─────────────────────────────────────────────────
  environment.etc."matugen/templates/waybar-style.css".source         = waybarTemplate;
  environment.etc."matugen/templates/gtk.css".source                  = gtkTemplate;
  environment.etc."matugen/templates/thunar.css".source               = thunarTemplate;
  environment.etc."matugen/templates/fuzzel.ini".source               = fuzzelTemplate;
  environment.etc."matugen/templates/kitty-colors.conf".source        = kittyTemplate;
  environment.etc."matugen/templates/swaync.css".source               = swayncTemplate;
  environment.etc."matugen/templates/swaync-config.json".source       = swayncConfigTemplate;
  environment.etc."matugen/templates/swayosd.css.template".source     = swayosdTemplate;

  # ── Matugen config (niri.kdl + nirimap templates registered in niri-setup.nix) ─
  environment.etc."matugen/config.toml".text = ''
    [config]

    [templates.waybar]
    input_path  = '/etc/matugen/templates/waybar-style.css'
    output_path = '/home/${username}/.config/waybar/style.css'

    [templates.fuzzel]
    input_path  = '/etc/matugen/templates/fuzzel.ini'
    output_path = '/home/${username}/.config/fuzzel/fuzzel.ini'

    [templates.gtk]
    input_path  = '/etc/matugen/templates/gtk.css'
    output_path = '/home/${username}/.config/gtk-3.0/gtk.css'

    [templates.kitty]
    input_path  = '/etc/matugen/templates/kitty-colors.conf'
    output_path = '/home/${username}/.config/kitty/colors.conf'

    [templates.thunar]
    input_path  = '/etc/matugen/templates/thunar.css'
    output_path = '/home/${username}/.config/gtk-3.0/thunar.css'

    [templates.swaync]
    input_path  = '/etc/matugen/templates/swaync.css'
    output_path = '/home/${username}/.config/swaync/style.css'

    [templates.swaync-config]
    input_path  = '/etc/matugen/templates/swaync-config.json'
    output_path = '/home/${username}/.config/swaync/config.json'

    [templates.swayosd]
    input_path  = '/etc/matugen/templates/swayosd.css.template'
    output_path = '/home/${username}/.cache/matugen/swayosd.css'

    # niri-specific templates are appended by niri-setup.nix via
    # environment.etc."matugen/config.toml" mkAfter / imports.
    # If you use a different compositor, add its templates here instead.
  '';

  # ── First-boot placeholder files ──────────────────────────────────────────
  # Matugen writes these on first wp-change; without placeholders apps that
  # try to include them at startup crash or show missing-file errors.
  system.activationScripts.matugen-placeholder = {
    text = ''
      mkdir -p /home/${username}/.config/swaync
      mkdir -p /home/${username}/.cache/matugen
      for dir_file in \
        "/home/${username}/.config/swaync/style.css" \
        "/home/${username}/.config/swaync/config.json" \
        "/home/${username}/.config/fuzzel/fuzzel.ini" \
        "/home/${username}/.config/waybar/style.css" \
        "/home/${username}/.config/waybar/fadeout-override.css" \
        "/home/${username}/.config/gtk-3.0/gtk.css" \
        "/home/${username}/.config/gtk-3.0/thunar.css" \
        "/home/${username}/.cache/matugen/swayosd.css" \
        "/home/${username}/.config/kitty/colors.conf"; do
        dir=$(dirname "$dir_file")
        if [ ! -f "$dir_file" ]; then
          mkdir -p "$dir"
          echo "" > "$dir_file"
          chown -R ${username}:users "$dir"
        fi
      done
    '';
  };

  # ── Packages ───────────────────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    matugen
    fuzzel
    kitty
    wl-clipboard
  ];
}
