{ pkgs, ... }:
let
  rebuildScript = pkgs.writeShellScriptBin "rebuild" (builtins.readFile ./rebuild.sh);
  installScript = pkgs.writeShellScriptBin "niceos-install" (builtins.readFile ./install.sh);
in {
  environment.systemPackages = [ rebuildScript installScript ];
}