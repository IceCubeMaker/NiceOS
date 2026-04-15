{ config, pkgs, lib, ... }:

let
  dManager = config.global.default_desktop_environment;
  user     = config.global.user;
in
{
  # Lemurs — customizable TUI display manager written in Rust.
  # Similar feel to ly, but more actively maintained and themeable.
  #
  # ⚠ KNOWN ISSUE: audio (PipeWire/PulseAudio) may not work unless your user
  #   is in the "seat" group. Add it to users.users.<you>.extraGroups.
  #   See: https://discourse.nixos.org/t/lemurs-login-manager-has-audio-and-permission-logind-issues
  #
  # To customise the look: edit /etc/lemurs/config.toml after first boot,
  # or override below with environment.etc."lemurs/config.toml".text.
  services.displayManager.lemurs = {
    enable = true;
  };

  services.displayManager.defaultSession = dManager;

  # Required: your user must be in the "seat" group for Wayland sessions
  # to get proper device access (input, GPU). Remove if already set globally.
  users.users.${user}.extraGroups = [ "seat" ];

  # seatd provides the seat management backend that lemurs relies on
  services.seatd.enable = true;
}
