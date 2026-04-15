{ config, pkgs, lib, ... }:

let
  dManager = config.global.default_desktop_environment;
in
{
  # GDM — GNOME Display Manager. Graphical, Wayland-native, polished.
  # Heavy (pulls in GNOME libs). Best pairing: gnome DE.
  # Works fine with niri — just more overhead than the others.
  services.displayManager.gdm = {
    enable       = true;
    wayland      = true;   # Wayland greeter (required for niri)
    autoSuspend  = false;  # prevent greeter sleeping while you're away
  };

  services.displayManager.defaultSession = dManager;
}
