{ config, pkgs, lib, ... }:

{
  environment.systemPackages = with pkgs; [
     vscodium
     nh
     nix-output-monitor
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
