{ pkgs, ... }:
let
  tipsFile     = pkgs.writeTextFile { name = "tips.sh"; text = builtins.readFile ./tips.sh; destination = "/share/niceos/tips.sh"; };
  rebuildScript = pkgs.writeShellScriptBin "rebuild" (builtins.readFile ./rebuild.sh);
  installScript = pkgs.writeShellScriptBin "niceos-install" (builtins.readFile ./install.sh);
in {
  environment.systemPackages = [ tipsFile rebuildScript installScript ];
}