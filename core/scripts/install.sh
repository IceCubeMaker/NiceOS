#!/usr/bin/env bash
set -e

REPO_URL="https://github.com/IceCubeMaker/NiceOS"
REPO_ROOT="/opt/niceos"
USER_CONFIG_DIR="/etc/nice-configs"
USER_CONFIG="$USER_CONFIG_DIR/configuration.nix"
USER_PASSWORDS="$USER_CONFIG_DIR/passwords.nix"

BOLD="\033[1m"
CYAN="\033[36m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
DIM="\033[2m"
RESET="\033[0m"

spinner() {
    local pid=$1
    local msg=$2
    local logfile=$3
    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        local last=""
        if [ -n "$logfile" ] && [ -f "$logfile" ]; then
            last=$(tail -1 "$logfile" 2>/dev/null | tr -d '\n')
        fi
        printf "\r${CYAN}${frames[$i]}${RESET} ${msg}\033[K"
        printf "\n${DIM}   ${last}${RESET}\033[K"
        printf "\033[1A"
        i=$(( (i+1) % ${#frames[@]} ))
        sleep 0.1
    done
    printf "\r\033[K\n\033[K\033[1A"
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

# Check for NixOS
if [ ! -f /etc/NIXOS ]; then
    echo -e "${RED}✗${RESET} NiceOS requires NixOS."
    echo -e "${DIM}  Visit https://nixos.org to get started.${RESET}"
    exit 1
fi

# Check for git
if ! command -v git &>/dev/null; then
    echo -e "${RED}✗${RESET} git is required but not installed"
    exit 1
fi

# Ask for sudo upfront
sudo -v

# Clone or update NiceOS repo
LOG=$(mktemp)
if [ -d "$REPO_ROOT/.git" ]; then
    echo -e "${YELLOW}⚠${RESET}  NiceOS already installed, updating..."
    (sudo git -C "$REPO_ROOT" pull > "$LOG" 2>&1) &
    spinner $! "Updating NiceOS..." "$LOG"
    echo -e "${GREEN}✓${RESET} NiceOS updated"
else
    (sudo git clone "$REPO_URL" "$REPO_ROOT" > "$LOG" 2>&1) &
    spinner $! "Cloning NiceOS..." "$LOG"
    echo -e "${GREEN}✓${RESET} NiceOS cloned to $REPO_ROOT"
fi
rm -f "$LOG"

# Symlink /etc/nixos to repo root
LOG=$(mktemp)
(sudo ln -sfn "$REPO_ROOT" /etc/nixos > "$LOG" 2>&1) &
spinner $! "Linking /etc/nixos to NiceOS..." "$LOG"
rm -f "$LOG"
echo -e "${GREEN}✓${RESET} /etc/nixos linked to $REPO_ROOT"

# Generate hardware-configuration.nix
LOG=$(mktemp)
(sudo nixos-generate-config --show-hardware-config > "$REPO_ROOT/hardware-configuration.nix" 2>"$LOG") &
spinner $! "Generating hardware configuration..." "$LOG"
rm -f "$LOG"
echo -e "${GREEN}✓${RESET} hardware-configuration.nix generated"

# Set up user config dir
sudo mkdir -p "$USER_CONFIG_DIR"

# configuration.nix
if [ -f "$USER_CONFIG" ]; then
    echo -e "${YELLOW}⚠${RESET}  configuration.nix already exists, skipping template..."
else
    LOG=$(mktemp)
    (sudo cp "$REPO_ROOT/core/templates/user-configuration-template.nix" "$USER_CONFIG" > "$LOG" 2>&1) &
    spinner $! "Copying user configuration template..." "$LOG"
    rm -f "$LOG"
    echo -e "${GREEN}✓${RESET} configuration.nix created at $USER_CONFIG"
fi

# passwords.nix
if [ -f "$USER_PASSWORDS" ]; then
    echo -e "${YELLOW}⚠${RESET}  passwords.nix already exists, skipping template..."
else
    LOG=$(mktemp)
    (sudo cp "$REPO_ROOT/core/templates/passwords-template.nix" "$USER_PASSWORDS" > "$LOG" 2>&1) &
    spinner $! "Copying passwords template..." "$LOG"
    rm -f "$LOG"
    echo -e "${GREEN}✓${RESET} passwords.nix created at $USER_PASSWORDS"
fi

# Lock down permissions on passwords.nix
LOG=$(mktemp)
(sudo chmod 600 "$USER_PASSWORDS" && sudo chown root:root "$USER_PASSWORDS" > "$LOG" 2>&1) &
spinner $! "Securing passwords.nix..." "$LOG"
rm -f "$LOG"
echo -e "${GREEN}✓${RESET} passwords.nix permissions secured"

# Initialize git repo in user config dir
if [ -d "$USER_CONFIG_DIR/.git" ]; then
    echo -e "${YELLOW}⚠${RESET}  User config git repo already initialized"
else
    LOG=$(mktemp)
    (sudo git -C "$USER_CONFIG_DIR" init && \
     sudo git -C "$USER_CONFIG_DIR" add configuration.nix && \
     sudo git -C "$USER_CONFIG_DIR" commit -m "initial NiceOS user config" > "$LOG" 2>&1) &
    spinner $! "Initializing user config git repo..." "$LOG"
    rm -f "$LOG"
    echo -e "${GREEN}✓${RESET} Git repo initialized at $USER_CONFIG_DIR"
fi

# Enable flakes
LOG=$(mktemp)
(sudo bash -c 'mkdir -p /etc/nix && grep -q "experimental-features" /etc/nix/nix.conf 2>/dev/null || echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf' > "$LOG" 2>&1) &
spinner $! "Enabling flakes..." "$LOG"
rm -f "$LOG"
echo -e "${GREEN}✓${RESET} Flakes enabled"

# Add hardware-configuration.nix to .gitignore
if ! grep -q "hardware-configuration.nix" "$REPO_ROOT/.gitignore" 2>/dev/null; then
    sudo bash -c "echo 'hardware-configuration.nix' >> '$REPO_ROOT/.gitignore'"
    echo -e "${GREEN}✓${RESET} Added hardware-configuration.nix to .gitignore"
else
    echo -e "${YELLOW}⚠${RESET}  .gitignore already up to date"
fi

echo ""
echo -e "${CYAN}🚀 Starting NiceOS rebuild...${RESET}"
echo ""
nix --experimental-features 'nix-command flakes' run nixpkgs#nh -- os switch "$REPO_ROOT"

echo ""
echo -e "${BOLD}${GREEN}✓ NiceOS installed successfully!${RESET}"
echo -e "${DIM}  Your config is at /etc/nice-configs/configuration.nix${RESET}"
echo -e "${DIM}  Your passwords are at /etc/nice-configs/passwords.nix${RESET}"
echo -e "${DIM}  Run 'rebuild' to apply future changes.${RESET}"
echo ""