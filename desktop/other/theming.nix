# theming.nix
#
# GTK theming, icon/cursor theme, fonts, and Thunar file manager.
# Entirely DE-agnostic — works under niri, Hyprland, Sway, or any Wayland
# compositor that uses GTK apps.
#
# Provides:
#   - Catppuccin Mocha/Mauve GTK theme (GTK 3 + GTK 4)
#   - Papirus-Dark icon theme (with catppuccin-papirus-folders override)
#   - Bibata-Modern-Classic cursor theme
#   - JetBrainsMono + Symbols Nerd Font
#   - Thunar with archive + volman plugins, gvfs, tumbler
#   - Activation scripts to symlink themes and write gsettings/dconf keys
#
# Place at: /etc/nixos/theming.nix
# Import in: configuration.nix

{ config, pkgs, lib, ... }:

let
  username = config.global.user;
in
{
  # ── Fonts ──────────────────────────────────────────────────────────────────
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.symbols-only
  ];

  # ── Packages ───────────────────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    papirus-icon-theme
    bibata-cursors
    xfce.xfconf
    file-roller
  ];

  # ── Thunar file manager ────────────────────────────────────────────────────
  programs.thunar = {
    enable  = true;
    plugins = with pkgs.xfce; [
      thunar-archive-plugin
      thunar-volman
    ];
  };

  services.gvfs.enable   = true;
  services.tumbler.enable = true;

  xdg.mime.defaultApplications = {
    "inode/directory" = "thunar.desktop";
  };

  # ── System-wide GTK settings (fallback — user settings below take priority) ─
  environment.etc."gtk-3.0/settings.ini".text = ''
    [Settings]
    gtk-theme-name = Catppuccin-Mocha-Standard-Mauve-Dark
    gtk-icon-theme-name = Papirus-Dark
    gtk-cursor-theme-name = Bibata-Modern-Classic
    gtk-cursor-theme-size = 24
  '';

  # ── Activation: symlink themes + write per-user config ────────────────────
  system.activationScripts.thunar-xfconf = {
    deps = [ "users" ];
    text = ''
      USER_HOME="/home/${username}"

      # ── Symlink Papirus-Dark icon theme into user icons dir ──────────────
      mkdir -p "$USER_HOME/.local/share/icons"
      for theme in Papirus Papirus-Dark Papirus-Light; do
        src=$(find /run/current-system/sw/share/icons -maxdepth 1 -name "$theme" -type d 2>/dev/null | head -1)
        if [ -n "$src" ] && [ ! -e "$USER_HOME/.local/share/icons/$theme" ]; then
          ln -sf "$src" "$USER_HOME/.local/share/icons/$theme"
        fi
      done
      chown -R ${username}:users "$USER_HOME/.local/share/icons" 2>/dev/null || true

      # ── Symlink Catppuccin GTK theme into user themes dir ────────────────
      mkdir -p "$USER_HOME/.local/share/themes"
      src=$(find /run/current-system/sw/share/themes -maxdepth 1 -name "Catppuccin-Mocha-Standard-Mauve-Dark" -type d 2>/dev/null | head -1)
      if [ -n "$src" ] && [ ! -e "$USER_HOME/.local/share/themes/Catppuccin-Mocha-Standard-Mauve-Dark" ]; then
        ln -sf "$src" "$USER_HOME/.local/share/themes/Catppuccin-Mocha-Standard-Mauve-Dark"
      fi
      chown -R ${username}:users "$USER_HOME/.local/share/themes" 2>/dev/null || true

      # ── GTK-3 user settings ──────────────────────────────────────────────
      # IMPORTANT: no leading whitespace — GTK's INI parser rejects indented
      # section headers, silently ignores the file, and falls back to Adwaita.
      mkdir -p "$USER_HOME/.config/gtk-3.0"
      cat > "$USER_HOME/.config/gtk-3.0/settings.ini" <<'EOF'
[Settings]
gtk-theme-name = Catppuccin-Mocha-Standard-Mauve-Dark
gtk-icon-theme-name = Papirus-Dark
gtk-cursor-theme-name = Bibata-Modern-Classic
gtk-cursor-theme-size = 24
EOF

      # ── GTK-4 user settings ──────────────────────────────────────────────
      mkdir -p "$USER_HOME/.config/gtk-4.0"
      cat > "$USER_HOME/.config/gtk-4.0/settings.ini" <<'EOF'
[Settings]
gtk-theme-name = Catppuccin-Mocha-Standard-Mauve-Dark
gtk-icon-theme-name = Papirus-Dark
gtk-cursor-theme-name = Bibata-Modern-Classic
gtk-cursor-theme-size = 24
EOF

      # ── Xcursor for X11/XWayland clients ────────────────────────────────
      mkdir -p "$USER_HOME/.icons/default"
      cat > "$USER_HOME/.icons/default/index.theme" <<'EOF'
[Icon Theme]
Name=Default
Comment=Default cursor theme
Inherits=Bibata-Modern-Classic
EOF

      chown -R ${username}:users \
        "$USER_HOME/.config/gtk-3.0/settings.ini" \
        "$USER_HOME/.config/gtk-4.0/settings.ini" \
        "$USER_HOME/.icons"

      # ── gsettings / dconf — runtime source of truth for GTK apps ────────
      ${pkgs.sudo}/bin/sudo -u ${username} \
        env DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(${pkgs.coreutils}/bin/id -u ${username})/bus" \
        ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface gtk-theme    'Catppuccin-Mocha-Standard-Mauve-Dark' 2>/dev/null || true
      ${pkgs.sudo}/bin/sudo -u ${username} \
        env DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(${pkgs.coreutils}/bin/id -u ${username})/bus" \
        ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface icon-theme   'Papirus-Dark' 2>/dev/null || true
      ${pkgs.sudo}/bin/sudo -u ${username} \
        env DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(${pkgs.coreutils}/bin/id -u ${username})/bus" \
        ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Classic' 2>/dev/null || true
      ${pkgs.sudo}/bin/sudo -u ${username} \
        env DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(${pkgs.coreutils}/bin/id -u ${username})/bus" \
        ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface cursor-size  24 2>/dev/null || true

      # ── Thunar xfconf keys (best-effort; works if session is live) ───────
      run_xfconf() {
        ${pkgs.sudo}/bin/sudo -u ${username} \
          env DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(${pkgs.coreutils}/bin/id -u ${username})/bus" \
          ${pkgs.xfce.xfconf}/bin/xfconf-query "$@" 2>/dev/null || true
      }
      run_xfconf -c thunar -p /default-view              -s "ThunarIconView"               --create -t string
      run_xfconf -c thunar -p /misc-icon-view-icon-size  -s 64                             --create -t int
      run_xfconf -c thunar -p /misc-show-hidden-files    -s false                          --create -t bool
      run_xfconf -c thunar -p /misc-single-click         -s false                          --create -t bool
      run_xfconf -c thunar -p /misc-thumbnail-mode       -s "THUNAR_THUMBNAIL_MODE_ALWAYS" --create -t string
    '';
  };
}
