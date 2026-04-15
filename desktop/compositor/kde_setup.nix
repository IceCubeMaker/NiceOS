{ config, pkgs, ... }:

{
  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the KDE Plasma Desktop Environment.
  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm.wayland.enable = true; # Even for X11 sessions, this helps SDDM
  hardware.enableAllFirmware = true;
}
