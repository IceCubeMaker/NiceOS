{ lib, config, pkgs, ... }:

{
  imports = [
    ./software/gaming/emulation/game-emulation.nix
    ./software/programming/chillcube.nix
    ./core/linux_basics.nix
    ./software/university/university.nix

    # ── Display Manager — uncomment exactly ONE ──────────────────────────────
    # Style guide:
    #   Graphical (GPU-rendered):  sddm, gdm, cosmic-greeter
    #   TUI (terminal):            ly, lemurs, greetd (tuigreet/wlgreet/gtkgreet)
    #   All are Wayland-native; none require services.xserver.enable.
    #
    # ★ Recommended for niri: greetd (gtkgreet+cage frontend)
    #   Wallpaper syncs automatically from wp-change — no extra config needed.
    #   Falls back to a dark background if no wallpaper has been set yet.
    #   Safe to use with or without niri/wp-change.
    #
    # ./DisplayManagers/greetd-setup.nix           # ★ graphical — gtkgreet+sway, wallpaper sync
    ./desktop/display-manager/ly-setup.nix             # ★ TUI — Catppuccin Mocha, DOOM fire, big clock
    # ./DisplayManagers/lemurs-setup.nix         #   TUI       — Rust, themeable (needs seat group)
    # ./DisplayManagers/sddm_setup.nix             #   graphical — astronaut theme, wallpaper sync
    # ./DisplayManagers/gdm-setup.nix            #   graphical — GNOME DM, heavy
    # ./DisplayManagers/cosmic-greeter-setup.nix #   graphical — COSMIC/Iced, pulls in cosmic-comp
    # ────────────────────────────────────────────────────────────────────────

    ./desktop/compositor/wayland/niri/niri-setup.nix
    ./unsorted.nix
    ./software/taskcli/taskcli.nix
    ./core/globals.nix
  ];

# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).


  # Overriding default global variables
  # global.timeZone =                    "Europe/Oslo";
  global.user =                        "franz";
  # global.defaultBrowser =              pkgs.firefox;
  global.extraScrapeFlags = "--flags unattend,symlink,videos,manuals,nobrackets,theinfront"; 
  # global.romDir = "/home/franz/ROMs"
  global.isLaptop = true;
  # global.defaultShell =                "fish"
  global.default_desktop_environment =   "niri";
  global.niriBlur                    =   false;


  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.kernelModules = [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];

  networking.hostName = "nixos"; # Define your hostname.
  
  # Enable networking
  networking.networkmanager.enable = true;

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "no";
    variant = "";
  };

  # Configure console keymap
  console.keyMap = "no";

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.franz = {
    isNormalUser = true;
    description = "Franz";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [
    #  thunderbird
    ];
  };

  # Install firefox.
  programs.firefox.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
     neovim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
     wget
     discord-ptb
     nodejs_22
     freetube
     (google-fonts.override { fonts = [ "Blinker" "Chakra Petch" ]; })
     aider-chat
     vscodium
     fuzzel
  ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true; # This fixes the glXChooseVisual error
  };

  # Enable the Steam hardware/firewall rules
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true; 
    dedicatedServer.openFirewall = true;
  };

  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia.open = true;
  hardware.nvidia.modesetting.enable = true;

  services.asusd.enable = true;

  system.stateVersion = "25.11"; # Did you read the comment?

}