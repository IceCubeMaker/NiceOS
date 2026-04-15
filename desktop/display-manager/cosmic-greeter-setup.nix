{ config, pkgs, lib, ... }:

let
  dManager = config.global.default_desktop_environment;
in
{
  # cosmic-greeter — the COSMIC desktop's graphical greeter.
  # Wayland-native, GPU-accelerated, built with Iced (Rust).
  # Clean and modern. No GNOME/KDE dependencies.
  # Best pairing: any Wayland compositor. Works well with niri.
  #
  # Note: pulls in the COSMIC compositor (cosmic-comp) for the greeter
  # session itself — not for your main session.
  services.displayManager.cosmic-greeter = {
    enable = true;
  };

  services.displayManager.defaultSession = dManager;
}
