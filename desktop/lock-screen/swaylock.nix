# swaylock.nix – themed swaylock-effects wrapper + idle manager for niri
{ config, pkgs, lib, ... }:

let
  swaylock-themed = pkgs.writeShellScriptBin "swaylock-themed" ''
    exec ${pkgs.swaylock-effects}/bin/swaylock \
      --screenshots \
      --effect-blur 8x5 \
      --effect-vignette 0.4:0.6 \
      --fade-in 0.3 \
      --clock \
      --timestr "%H:%M" \
      --datestr "%A, %d %B" \
      --font "JetBrainsMono Nerd Font" \
      --indicator \
      --indicator-radius 120 \
      --indicator-thickness 10 \
      --indicator-caps-lock \
      --grace 1 \
      --grace-no-mouse \
      --show-failed-attempts \
      --color            1e1e2e \
      --inside-color     1e1e2e \
      --inside-clear-color     1e1e2e \
      --inside-caps-lock-color 1e1e2e \
      --inside-ver-color       1e1e2e \
      --inside-wrong-color     1e1e2e \
      --ring-color       313244 \
      --ring-clear-color f5e0dc \
      --ring-caps-lock-color   fab387 \
      --ring-ver-color         89b4fa \
      --ring-wrong-color       eba0ac \
      --line-color       00000000 \
      --line-clear-color       00000000 \
      --line-caps-lock-color   00000000 \
      --line-ver-color         00000000 \
      --line-wrong-color       00000000 \
      --separator-color  00000000 \
      --key-hl-color     a6e3a1 \
      --bs-hl-color      f5e0dc \
      --caps-lock-key-hl-color a6e3a1 \
      --caps-lock-bs-hl-color  f5e0dc \
      --text-color       cdd6f4 \
      --text-clear-color       f5e0dc \
      --text-caps-lock-color   fab387 \
      --text-ver-color         89b4fa \
      --text-wrong-color       eba0ac \
      --layout-bg-color        00000000 \
      --layout-border-color    00000000 \
      --layout-text-color      cdd6f4
  '';

  niri-pkg = config.programs.niri.package;
in
{
  environment.systemPackages = with pkgs; [
    swaylock-themed
    swayidle
  ];

  security.pam.services.swaylock = {};

  systemd.user.services.swayidle = {
    description = "Idle manager for Wayland (lock, DPMS, suspend)";
    wantedBy    = [ "graphical-session.target" ];
    partOf      = [ "graphical-session.target" ];
    after       = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = ''
        ${pkgs.swayidle}/bin/swayidle -w \
          timeout 300 '${swaylock-themed}/bin/swaylock-themed' \
          timeout 360 '${niri-pkg}/bin/niri msg action power-off-monitors' \
            resume '${niri-pkg}/bin/niri msg action power-on-monitors' \
          timeout 1200 '${pkgs.systemd}/bin/systemctl suspend' \
          before-sleep '${swaylock-themed}/bin/swaylock-themed'
      '';
      Restart    = "on-failure";
      RestartSec = 2;
    };
  };
}