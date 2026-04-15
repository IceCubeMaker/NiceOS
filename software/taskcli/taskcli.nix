{ config, pkgs, lib, ... }:

let
  taskcli = pkgs.python3Packages.buildPythonApplication {
    pname = "taskcli";
    version = "0.1.0";
    src = ./code;

    pyproject = true;

    nativeBuildInputs = with pkgs.python3Packages; [
      setuptools
      wheel
    ];

    propagatedBuildInputs = with pkgs.python3Packages; [
      click
      textual
      lupa
      watchdog
      pyyaml
      python-dateutil
      pyperclip
    ];
  };
in {
  environment.systemPackages = [
    taskcli
    pkgs.neovim   # required by taskcli's 'e' and 't' keybinds
  ];
}
