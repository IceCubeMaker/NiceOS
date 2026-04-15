#!/usr/bin/env bash
set -e

REPO_URL="https://github.com/yourusername/niceos"
REPO_ROOT="/opt/niceos"
USER_CONFIG_DIR="/etc/nice-configs"
USER_CONFIG="$USER_CONFIG_DIR/configuration.nix"

BOLD="\033[1m"
CYAN="\033[36m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
DIM="\033[2m"
RESET="\033[0m"

# ── Tips (customize these) ────────────────────────────────────────────────────
TIPS=(
    "💡 Run 'rebuild' anytime to apply config changes"
    "💡 Edit /etc/nice-configs/configuration.nix to customize your system"
    "💡 Run 'niceos-install' again anytime to re-run the installer"
    "💡 Your flake.lock pins nixpkgs to an exact revision"
    "💡 Run 'update' to pull the latest nixpkgs"
    "💡 Run 'rebuild --turbo' to use all CPU cores for building"
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

# Check for git
if ! command -v git &>/dev/null; then
    echo -e "${RED}✗${RESET} git is required but not installed"
    exit 1
fi

# Clone or update repo
if [ -d "$REPO_ROOT/.git" ]; then
    echo -e "${YELLOW}⚠${RESET}  NiceOS already installed, updating..."
    (sudo git -C "$REPO_ROOT" pull) &
    spinner $! "Updating NiceOS..."
    echo -e "${GREEN}✓${RESET} NiceOS updated"
else
    (sudo git clone "$REPO_URL" "$REPO_ROOT") &
    spinner $! "Cloning NiceOS..."
    echo -e "${GREEN}✓${RESET} NiceOS cloned to $REPO_ROOT"
fi

# Symlink /etc/nixos to repo root
(sudo ln -sfn "$REPO_ROOT" /etc/nixos) &
spinner $! "Linking /etc/nixos to NiceOS..."
echo -e "${GREEN}✓${RESET} /etc/nixos linked to $REPO_ROOT"

# Generate hardware-configuration.nix
(sudo nixos-generate-config --show-hardware-config > "$REPO_ROOT/hardware-configuration.nix") &
spinner $! "Generating hardware configuration..."
echo -e "${GREEN}✓${RESET} hardware-configuration.nix generated"

# Set up user config dir
sudo mkdir -p "$USER_CONFIG_DIR"
if [ -f "$USER_CONFIG" ]; then
    echo -e "${YELLOW}⚠${RESET}  $USER_CONFIG already exists, skipping template..."
else
    (sudo cp "$REPO_ROOT/core/templates/user-configuration-template.nix" "$USER_CONFIG") &
    spinner $! "Copying user configuration template..."
    echo -e "${GREEN}✓${RESET} configuration.nix created at $USER_CONFIG"
fi

# Enable flakes
(sudo bash -c 'mkdir -p /etc/nix && grep -q "experimental-features" /etc/nix/nix.conf 2>/dev/null || echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf') &
spinner $! "Enabling flakes..."
echo -e "${GREEN}✓${RESET} Flakes enabled"

# Add hardware-configuration.nix to .gitignore
if ! grep -q "hardware-configuration.nix" "$REPO_ROOT/.gitignore" 2>/dev/null; then
    sudo bash -c "echo 'hardware-configuration.nix' >> '$REPO_ROOT/.gitignore'"
    echo -e "${GREEN}✓${RESET} Added hardware-configuration.nix to .gitignore"
else
    echo -e "${YELLOW}⚠${RESET}  .gitignore already up to date"
fi

echo ""
echo -e "${DIM}  $(random_tip)${RESET}"
echo ""

# Rebuild
echo -e "${CYAN}🚀 Starting NiceOS rebuild...${RESET}"
echo ""
nix --experimental-features 'nix-command flakes' run nixpkgs#nh -- os switch "$REPO_ROOT"

echo ""
echo -e "${BOLD}${GREEN}✓ NiceOS installed successfully!${RESET}"
echo -e "${DIM}  Your config is at /etc/nice-configs/configuration.nix${RESET}"
echo -e "${DIM}  Edit it with: sudo nano /etc/nice-configs/configuration.nix${RESET}"
echo -e "${DIM}  Then run 'rebuild' to apply changes.${RESET}"
echo ""