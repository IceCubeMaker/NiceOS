{ config, pkgs, ... }:

{
  # 1. Install the necessary packages
  environment.systemPackages = [
    config.global.defaultBrowser 
    config.global.pomodoroTimer
    config.global.noteTakingProgram
    config.global.syncService
  ];
}
