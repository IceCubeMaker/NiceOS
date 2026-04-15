#!/usr/bin/env bash

source /run/current-system/sw/share/niceos/tips.sh

FULL_CPU=false
[[ "${1:-}" == "--turbo" ]] && FULL_CPU=true

if $FULL_CPU; then
    NIX_JOBS="auto"
else
    NIX_JOBS=2
fi

read -rp "🏷️  Rebuild name: " REBUILD_NAME
REBUILD_NAME="${REBUILD_NAME:-rebuild}"

sudo git -C /etc/nice-configs add -A
sudo git -C /etc/nice-configs commit -m "$REBUILD_NAME" --allow-empty

OUTPUT=$(nh os switch /opt/niceos -- --impure -j $NIX_JOBS 2>&1)
echo "$OUTPUT" | grep -iv "was moved to top-level\|has been renamed"

echo "$OUTPUT" | grep -i "was moved to top-level\|has been renamed" | while read -r line; do
    old=$(echo "$line" | grep -oP "(?<=')\S+(?=' was moved|\S+(?=' has been renamed))")
    new=$(echo "$line" | grep -oP "(?<=pkgs\.)\w+(?=' directly)|(?<=renamed to ')\w+")
    [ -z "$old" ] || [ -z "$new" ] && continue
    echo "🔄 Renaming $old → pkgs.$new"
    find "/opt/niceos" -type f -name "*.nix" | while read -r file; do
        sudo sed -i "s/\b$old\b/$new/g" "$file"
    done
done