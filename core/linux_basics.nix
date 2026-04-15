{ config, lib, pkgs, ... }:

let
  # This pulls the latest unstable nixpkgs
  unstable = import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz") {
    config = config.nixpkgs.config; # Ensures unfree settings carry over
  };
in {

   imports = [
      ./scripts/scripts-importer.nix
   ];

    environment.systemPackages = 
    [ 
       config.global.defaultBrowser 
       config.global.defaultTerminal
    ] ++ (with pkgs; [
       ncdu
       python3
       ranger
       neovim
       wget
       git
       github-desktop
       blueman
       revolt-desktop
       nodejs_20
       fastfetch
       pavucontrol
       # download all shells as backup
       fish
       zsh
       bash
       nushell
       bashInteractive
    ]) ++ (lib.optional config.global.isLaptop pkgs.brightnessctl); # only download brightnessctl if it is a laptop

    programs.appimage.enable = true;
    programs.appimage.binfmt = true;

    services.dbus.enable = true;

    # enable bluetooth
    hardware.bluetooth.enable = config.global.bluetoothEnabled;
    hardware.bluetooth.powerOnBoot = config.global.bluetoothEnabled;
    services.blueman.enable = config.global.bluetoothEnabled;

    # enable audio
    services.pipewire = {
       enable = true;
       alsa.enable = true;
       alsa.support32Bit = true;
       pulse.enable = true;
       jack.enable = true;
    };

    # set the shell
    users.users.${config.global.user}.shell = pkgs.${config.global.defaultShell};
    programs.fish.enable = config.global.defaultShell == "fish";
    programs.zsh = lib.mkIf (config.global.defaultShell == "zsh") {
      enable = true;
      enableCompletion = true;
      autosuggestions.enable = true;
    };
      programs.bash = lib.mkIf (config.global.defaultShell == "bash") {
      completion.enable = true;
    };
    
    # set timezone, keyboard and language
    time.timeZone = config.global.timeZone;
    i18n.defaultLocale = "en_US.UTF-8";

    # reduce how much space Nix takes
    nix.settings.auto-optimise-store = true;
    boot.loader.systemd-boot.configurationLimit = 7;
    nix.gc = {
       automatic = true;
       dates = "weekly";
       options = "--delete-older-than +7";
    };

    # optimize RAM usage
    zramSwap = {
       enable = true;
       algorithm = "lz4";
       memoryPercent = 50;
       priority = 100;
    };

    # enable internet
    networking.networkmanager.enable = true;

    # enable boot screen
    boot.plymouth = {
       enable = true;
       theme = "breeze";
    };

    # log if someone tries to connect to a closed port
    networking.firewall.logRefusedConnections = true;

}
