{ config, pkgs, ... }:

let
  dedupe-script = pkgs.writeShellScriptBin "dedupe-folder" ''
    TARGET_DIR="''${1:-.}"
    if [ ! -d "$TARGET_DIR" ]; then
      echo "Directory not found."
      exit 1
    fi

    # Find duplicates based on SHA256 hash
    ${pkgs.findutils}/bin/find "$TARGET_DIR" -type f -print0 | \
    ${pkgs.findutils}/bin/xargs -0 ${pkgs.coreutils}/bin/sha256sum | \
    ${pkgs.coreutils}/bin/sort | \
    ${pkgs.gawk}/bin/awk '
      {
        hash = $1; $1 = ""; file = substr($0, 2);
        if (seen[hash]) { print file }
        else { seen[hash] = 1 }
      }' | while read -r dup; do
        echo "Removing: $dup"
        rm "$dup"
    done
  '';
in
{
  environment.systemPackages = with pkgs; [
    dedupe-script
    rmlint 
  ];
}
