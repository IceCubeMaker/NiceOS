{ config, lib, pkgs, ... }:

let
 
  ###################
  ### NIRI CONFIG ###
  ###################
  
  niriConfig = pkgs.writeText "niri-config.kdl" ''

input {
    keyboard {
        xkb {
        }
        numlock
    }
    touchpad {
        tap
    }

    mouse {
    }

    trackpoint {
    }
}

layout {
    background-color "transparent"
    gaps 10
    center-focused-column "never"
    preset-column-widths {
        proportion 0.33333
        proportion 0.5
        proportion 0.66667
    }

    default-column-width { proportion 0.5; }
    focus-ring {
        width 2
        active-color "#000000"
        inactive-color "#000000"
    }

    border {
        width 1
        active-color "#ffffff"
        inactive-color "#505050"
    }

    shadow {
        softness 30
        spread 5
        offset x=0 y=5
        color "#0007"
    }

    struts {
    }
}

environment {
    XCURSOR_THEME "Bibata-Modern-Light"
    XCURSOR_SIZE "24"
}

spawn-sh-at-startup "waybar"
spawn-sh-at-startup "wl-clip-persist --clipboard both"
spawn-sh-at-startup "syncthing"
spawn-sh-at-startup "dbus-update-activation-environment --systemd --all && systemctl --user restart xdg-desktop-portal xdg-desktop-portal-gnome xdg-desktop-portal-gtk"
spawn-sh-at-startup "swww-daemon"
prefer-no-csd

screenshot-path "~/Pictures/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png"

animations {
    workspace-switch {
        spring damping-ratio=0.8 stiffness=1000 epsilon=0.0001
    }

    window-open {
        spring damping-ratio=0.6 stiffness=800 epsilon=0.0001
    }

    window-close {
	spring damping-ratio=0.8 stiffness=800 epsilon=0.0001
    }
    horizontal-view-movement {
        spring damping-ratio=0.8 stiffness=800 epsilon=0.0001
    }

    window-movement {
        spring damping-ratio=0.8 stiffness=800 epsilon=0.0001
    }

    window-resize {
        spring damping-ratio=0.8 stiffness=800 epsilon=0.0001
    }

    config-notification-open-close {
        spring damping-ratio=0.6 stiffness=1000 epsilon=0.001
    }

    exit-confirmation-open-close {
        spring damping-ratio=0.6 stiffness=500 epsilon=0.01
    }

    screenshot-ui-open {
        duration-ms 200
        curve "ease-out-quad"
    }

    overview-open-close {
        spring damping-ratio=0.8 stiffness=800 epsilon=0.0001
    }

    recent-windows-close {
        spring damping-ratio=0.8 stiffness=800 epsilon=0.001
    }

    slowdown 1.2

}

window-rule {
    match app-id=r#"^org\.wezfurlong\.wezterm$"#
    default-column-width {}
}

window-rule {

    match app-id=r#"firefox$"# title="^Picture-in-Picture$"
    open-floating true
}

/-window-rule {
    match app-id=r#"^org\.keepassxc\.KeePassXC$"#
    match app-id=r#"^org\.gnome\.World\.Secrets$"#

    block-out-from "screen-capture"

}
window-rule {
    geometry-corner-radius 5
    clip-to-geometry true
}

layer-rule {
    match namespace="^swww-daemon$"
    place-within-backdrop true
}



binds {

    F1 			 { spawn-sh "wtype -M alt -k Left -m alt"; }
    F2			 { spawn-sh "wtype -M alt -k Right -m alt"; }
    F3 			 { spawn-sh "wtype -M ctrl r -m ctrl"; }
    Alt+S		 { screenshot; }   

    Alt+T	         hotkey-overlay-title="Open a Terminal: Kitty" { spawn "kitty"; }
    Alt+R 	         hotkey-overlay-title="Run an Application: fuzzel" { spawn "fuzzel"; }
    Alt+Mod+Alt+R 	 hotkey-overlay-title="Reboot" { spawn-sh "reboot"; }
    Alt+Mod+Alt+K 	 hotkey-overlay-title="Shutodnw" {spawn-sh "shutdown now"; }
    Alt+O 		 hotkey-overlay-title="overview" {toggle-overview;}
    Alt+F 	         hotkey-overlay-title="maximize window" {maximize-column;}
    F5 			 hotkey-overlay-title="maximize window" {maximize-column;}
    Alt+Q 		 repeat=false {close-window;}
    F4			 {fullscreen-window;}

    // AUDIO CONTROLS --------------------------------------
    F10 		 allow-when-locked=true { spawn-sh "pamixer -i 5"; }
    F9 			 allow-when-locked=true { spawn-sh "pamixer -d 5"; }
    F8        		 allow-when-locked=true { spawn-sh "pamixer -t"; }
    F7                   allow-when-locked=true { spawn "brightnessctl" "set" "10%+"; }
    F6 			 allow-when-locked=true { spawn "brightnessctl" "set" "10%-"; }

    // MOVING WORKSPACE AND WINDOWS ------------------------
    Alt+J 	         { focus-column-left; }
    Alt+K  	         { focus-workspace-down; }
    Alt+I  	         { focus-workspace-up; }
    Alt+L  	         { focus-column-right; }
    Alt+Ctrl+I     	 { move-window-to-workspace-up; }
    Alt+Ctrl+J     	 { move-column-left; }
    Alt+Ctrl+K    	 { move-window-to-workspace-down; }
    Alt+Ctrl+L    	 { move-column-right; }
}

  '';

   ############################
   #### WAYBAR JSON CONFIG ####
   ############################

   waybarConfig = pkgs.writeText "config.jsonc" ''

   {
  "layer": "top",
  "position": "bottom",
  "height": 0,
  "modules-left": ["niri/workspaces"],

  "modules-center": ["clock", "custom/weather"],

  "modules-right": [
    "pulseaudio",
    "battery",
    "network",
    "tray"
  ],

  "niri/workspaces": {
    "format": "{icon}",
    "format-icons": {
      "active": "",
      "default": "o"
    }
  },

  "tray": {
    "icon-size": 16,
    "spacing": 5
  },

  "custom/music": {
    "format": "  {}",
    "escape": true,
    "interval": 5,
    "tooltip": false,
    "exec": "playerctl metadata --format='{{ artist }} - {{ title }}'",
    "on-click": "playerctl play-pause",
    "max-length": 50
  },

  "clock": {
    "timezone": "Europe/Oslo",
    "tooltip-format": "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>",
    "format": "{:%d/%m/%Y - %H:%M:%S}",
    "interval": 1
  },

  "network": {
    "format-wifi": "󰤢 {bandwidthDownBits}",
    "format-ethernet": "󰈀 {bandwidthDownBits}",
    "format-disconnected": "󰤠 No Network",
    "interval": 5,
    "tooltip": false
  },

  "cpu": {
    "interval": 1,
    "format": "  {icon0}{icon1}{icon2}{icon3} {usage:>2}%",
    "format-icons": ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
  },

  "battery": {
    "states": {
        "warning": 30,
        "critical": 15
    },
    "format": "{icon} {capacity}%",
    "format-charging": "CHARGING {capacity}%", // Using a symbol for charging
    "format-plugged": "CHARGING {capacity}%",
    "format-icons": ["Battery", "BAttery", "BATTery", "BATTEry", "BATTERY"],
    "tooltip": false
  },

  "memory": {
    "interval": 30,
    "format": "  {used:0.1f}G/{total:0.1f}G"
  },

  "custom/uptime": {
    "format": "{}",
    "interval": 1600,
    "exec": "sh -c '(uptime -p)'"
  },

  "pulseaudio": {
    "format": "{icon} {volume}%",
    "format-muted": "MUTED",
    "format-icons": {
      "default": ["sound", "Sound", "SOUND"]
    },
    "on-click": "pavucontrol"
  },

  "custom/power": {
    "tooltip": false,
    "on-click": "wlogout &",
    "format": "⏻"
  },

  "custom/docker": {
    "format": "{}",
    "return-type": "json",
    "interval": 10,
    "exec": "$(pwd)/scripts/docker-stats/docker-stats",
    "tooltip": true
  },

  "custom/weather": {
    "format": "{}",
    "tooltip": true,
    "interval": 1800,
    "exec": "$(pwd)/scripts/weather-stats/weather-stats",
    "return-type": "json"
  }
}

   '';

   ########################
   ### WAYBAR CSS STYLE ###
   ########################

   waybarCSS = pkgs.writeText "style.css" ''


* {
  font-family: Courier Prime;
  font-size: 18px;
  min-height: 0;
  padding: 0;
  margin: 0;
  border: none;
}

#waybar {
  background: transparent;
  color: #000000;
  margin: 0px 0px;
}

#workspaces {
  margin: 0px;
  background: transparent;
  margin-left: 2px;
}

#workspaces button {
  color: #000000;
  padding: 0.4rem;
}

#workspaces button.active {
  color: #000000;
}

button {
  background: transparent;
}

#workspaces button:hover {
  background: transparent;
  border: 0px solid transparent;
}

#custom-music,
#tray,
#backlight,
#clock,
#battery,
#pulseaudio,
#network,
#cpu,
#memory,
#custom-lock,
#custom-power,
#custom-weather,
#custom-uptime,
#custom-docker {
  background-color: transparent;
  padding: 0.5rem 1rem;
  margin: 0px 0;
}

#clock {
  color: #000000;
}

#custom-weather {
  color: #000000;
  margin-left: 0.5rem;
}

#battery {
  color: #000000;
}

#battery.charging {
  color: #000000;
}

#battery.warning:not(.charging) {
  color: #000000;
}

#backlight {
  color: #000000;
}

#backlight,
#battery {
}

#pulseaudio {
  color: #000000;
}

#custom-docker {
  color: #000000;
}

#custom-music {
  color: #000000;
}

#custom-lock {
  color: #000000;
}

#custom-power {
  margin-right: 1rem;
  color: #000000;
}

#custom-docker.docker {
  color: #000000;
}

#custom-docker.docker-none {
  color: #000000;
}

#custom-docker.docker-error {
  color: #000000;
}

#custom-weather.clear {
  color: #000000; /* Sunny yellow */
}

#custom-weather.cloud {
  color: #000000; /* Light blue */
}

#custom-weather.rain {
  color: #000000; /* Blue */
}

#custom-weather.snow {
  color: #000000; /* White-ish */
}

#custom-weather.thunder {
  color: #000000; /* Purple */
}

#custom-weather.fog {
  color: #000000; /* Gray */
}

#custom-weather.error {
  color: #000000; /* Red */
}


   '';

  Wallpaper = pkgs.fetchurl {
    url = "https://r4.wallpaperflare.com/wallpaper/555/558/411/illustration-gameboy-nintendo-super-mario-wallpaper-7bf62c8d53015fc985146bc92d2c4cd0.jpg";
    sha256 = "1b5r6jj9jac8bzixysgcsfdmgmqpqz32p7v1xbc03iadsw7kki76";
  };


in {

  globals = import ./globals.nix;
  user = globals.user;

  environment.systemPackages = with pkgs; [
    swww               # wallpaper manager
    xwayland-satellite
    wl-clipboard       # for screenshots
    fuzzel             # launcher
    pavucontrol        # audio control 
    pamixer           # audio control
  ];

  programs.niri.enable = true;
  programs.waybar.enable = true;
  
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gnome # Required for screen sharing
      xdg-desktop-portal-gtk   # Handles file pickers and basic dialogs
    ];
    config = {
      common = {
        default = [ "gtk" ];
        # Specifically use GNOME for these three to ensure OBS/Discord work
        "org.freedes:ktop.impl.portal.ScreenCast" = [ "gnome" ];
        "org.freedesktop.impl.portal.Screenshot" = [ "gnome" ];
        "org.freedesktop.impl.portal.Settings" = [ "gnome" ]; # Fixes OBS crashes
      };
    };
  };

  environment.sessionVariables = {
     MOZ_ENABLE_WAYLAND = "1";
  };

  fonts.packages = with pkgs; [
     courier-prime
  ];

  systemd.tmpfiles.rules = [
    "d /home/${user}/.config/niri 0755 ${user} users - -"
    "L+ /home/${user}/.config/niri/config.kdl - - - - ${niriConfig}"
    "d /home/${user}/.config/waybar 0755 ${user} users - -"
    "L+ /home/${user}/.config/waybar/config.jsonc - - - - ${waybarConfig}"
    "L+ /home/${user}/.config/waybar/style.css - - - - ${waybarCSS}"
    "d /home/${user}/wallpapers 0755 ${user} users - -"
    "L+ /home/${user}/wallpapers/wallpaper.png - - - - ${Wallpaper}"
  ];


  systemd.user.services.swww-init = {
    description = "Set wallpaper";
    partOf = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.swww}/bin/swww img /home/${user}/wallpapers/wallpaper.png";
      Restart = "on-failure";
      RestartSec = 1;
    };
  };


  systemd.user.services.waybar = {
    description = "Waybar status bar";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.waybar}/bin/waybar";
      Restart = "on-failure"; 
    };
  };

}
