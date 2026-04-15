#!/usr/bin/env bash
set -e

NIXOS_DIR="/etc/nixos"
REPO_ROOT="${1:-$HOME/nixconfigs}"

BOLD="\033[1m"
CYAN="\033[36m"
GREEN="\033[32m"
YELLOW="\033[33m"
DIM="\033[2m"
RESET="\033[0m"

# ── Tips (customize these) ────────────────────────────────────────────────────
TIPS=(
    "💡 Run 'rebuild' anytime to apply config changes"
    "💡 Edit configuration.nix in your repo to customize your system"
    "💡 Run 'niceos-install' again anytime to re-link your config"
    "💡 Your flake.lock pins nixpkgs to an exact revision"
    "💡 Run 'update' to pull the latest nixpkgs"
)
# ─────────────────────────────────────────────────────────────────────────────

random_tip() {
    echo "${TIPS[$RANDOM % ${#TIPS[@]}]}"
}

spinner() {
    local pid=$1
    local msg=$2
    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local i=0
    local tip_timer=0
    local current_tip="$(random_tip)"
    while kill -0 "$pid" 2>/dev/null; do
        if (( tip_timer % 20 == 0 )); then
            current_tip="$(random_tip)"
        fi
        printf "\r${CYAN}${frames[$i]}${RESET} ${msg}  ${DIM}${current_tip}${RESET}\033[K"
        i=$(( (i+1) % ${#frames[@]} ))
        tip_timer=$(( tip_timer + 1 ))
        sleep 0.1
    done
    printf "\r\033[K"
}

echo -e "${BOLD}${CYAN}"
cat << 'EOF'
  _  _ _         ___  ___ 
 | \| (_)__ _ __/ _ \/ __|
 | .` | / _/ -_) (_) \__ \
 |_|\_|_\__\___|\___/|___/
EOF
echo -e "${RESET}"
echo -e "${DIM}  The friendly NixOS config framework${RESET}"
echo ""

# Symlink /etc/nixos to repo root
(sudo ln -sfn "$REPO_ROOT" "$NIXOS_DIR") &
spinner $! "Linking /etc/nixos to repo..."
echo -e "${GREEN}✓${RESET} /etc/nixos linked to $REPO_ROOT"

# Add hardware-configuration.nix to .gitignore
if ! grep -q "hardware-configuration.nix" "$REPO_ROOT/.gitignore" 2>/dev/null; then
    echo "hardware-configuration.nix" >> "$REPO_ROOT/.gitignore"
    echo -e "${GREEN}✓${RESET} Added hardware-configuration.nix to .gitignore"
else
    echo -e "${YELLOW}⚠${RESET}  .gitignore already up to date"
fi

# Generate hardware-configuration.nix
(sudo nixos-generate-config --show-hardware-config > "$REPO_ROOT/hardware-configuration.nix") &
spinner $! "Generating hardware configuration..."
echo -e "${GREEN}✓${RESET} hardware-configuration.nix generated"

# configuration.nix
if [ -f "$REPO_ROOT/configuration.nix" ]; then
    echo -e "${YELLOW}⚠${RESET}  configuration.nix already exists, skipping template..."
else
    (cp "$REPO_ROOT/core/templates/configuration.nix" "$REPO_ROOT/configuration.nix") &
    spinner $! "Copying configuration.nix template..."
    echo -e "${GREEN}✓${RESET} configuration.nix copied"
fi

# Enable flakes
(sudo bash -c 'mkdir -p /etc/nix && grep -q "experimental-features" /etc/nix/nix.conf 2>/dev/null || echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf') &
spinner $! "Enabling flakes..."
echo -e "${GREEN}✓${RESET} Flakes enabled"

echo ""
echo -e "${DIM}  $(random_tip)${RESET}"
echo ""

# Rebuild
echo -e "${CYAN}🚀 Starting NiceOS rebuild...${RESET}"
echo ""
nix --experimental-features 'nix-command flakes' run nixpkgs#nh -- os switch "$REPO_ROOT"

echo ""
echo -e "${BOLD}${GREEN}✓ NiceOS installed successfully!${RESET}"
echo -e "${DIM}  Welcome to NiceOS. Run 'rebuild' to apply future changes.${RESET}"
echo ""