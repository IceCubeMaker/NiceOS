#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/IceCubeMaker/NiceOS"
REPO_ROOT="/opt/niceos"
USER_CONFIG_DIR="/etc/nice-configs"
USER_CONFIG="$USER_CONFIG_DIR/configuration.nix"
USER_PASSWORDS="$USER_CONFIG_DIR/passwords.nix"

BOLD="\033[1m"
CYAN="\033[36m"
GREEN="\033[32m"
RED="\033[31m"
DIM="\033[2m"
RESET="\033[0m"

spinner() {
  local pid=$1
  local msg=$2
  local logfile=$3
  local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
  local i=0
  printf "\033[?25l"
  while kill -0 "$pid" 2>/dev/null; do
    local last=""
    if [[ -f "$logfile" ]]; then
      last=$(tail -n 1 "$logfile" | sed 's/[^[:print:]]//g' | cut -c1-80)
    fi
    printf "\r${CYAN}${frames[$i]}${RESET} %s\033[K\n${DIM}  %-80s${RESET}\033[1A" "$msg" "$last"
    i=$(( (i+1) % ${#frames[@]} ))
    sleep 0.1
  done
  printf "\033[?25h"
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

read -rp "👤 Enter your username: " TARGET_USER

# Checks
[[ -f /etc/NIXOS ]] || { echo -e "${RED}Not NixOS${RESET}"; exit 1; }
command -v git >/dev/null || { echo -e "${RED}git required${RESET}"; exit 1; }
sudo -v

# Clone / update repo
LOG=$(mktemp)
if [[ -d "$REPO_ROOT/.git" ]]; then
  (sudo git -C "$REPO_ROOT" pull > "$LOG" 2>&1) &
  spinner $! "Updating NiceOS..." "$LOG"
else
  (sudo git clone "$REPO_URL" "$REPO_ROOT" > "$LOG" 2>&1) &
  spinner $! "Cloning NiceOS..." "$LOG"
fi
rm -f "$LOG"
echo -e "${GREEN}✓ Repo ready${RESET}"

# Check flake.nix exists
[[ -f "$REPO_ROOT/flake.nix" ]] || { echo -e "${RED}flake.nix not found in repo${RESET}"; exit 1; }

# Safe directory
sudo git config --global --add safe.directory "$REPO_ROOT"

# Point /etc/nixos at repo
sudo ln -sfn "$REPO_ROOT" /etc/nixos

# Hardware config
HW_FILE="/etc/nixos/hardware-configuration.nix"
if [[ ! -f "$HW_FILE" ]]; then
  echo -e "${CYAN}Generating hardware configuration...${RESET}"
  sudo nixos-generate-config --show-hardware-config | sudo tee "$HW_FILE" > /dev/null
fi

# Config dir
sudo mkdir -p "$USER_CONFIG_DIR"

# User config
if [[ ! -f "$USER_CONFIG" ]]; then
  sudo cp "$REPO_ROOT/core/templates/user-configuration-template.nix" "$USER_CONFIG"
  sudo sed -i "s/__USERNAME__/$TARGET_USER/g" "$USER_CONFIG" || true
fi

# Passwords
if [[ ! -f "$USER_PASSWORDS" ]]; then
  sudo cp "$REPO_ROOT/core/templates/passwords-template.nix" "$USER_PASSWORDS"
fi
sudo chown root:root "$USER_PASSWORDS"
sudo chmod 644 "$USER_PASSWORDS"

# Git init for user config dir
if [[ ! -d "$USER_CONFIG_DIR/.git" ]]; then
  sudo git -C "$USER_CONFIG_DIR" init
  sudo git -C "$USER_CONFIG_DIR" add configuration.nix || true
  sudo git -C "$USER_CONFIG_DIR" commit -m "initial NiceOS config" || true
fi

# Enable flakes
sudo mkdir -p /etc/nix
if ! grep -q "experimental-features" /etc/nix/nix.conf 2>/dev/null; then
  echo "experimental-features = nix-command flakes" | sudo tee -a /etc/nix/nix.conf > /dev/null
fi

# gitignore
grep -qxF "hardware-configuration.nix" "$REPO_ROOT/.gitignore" 2>/dev/null || \
  echo "hardware-configuration.nix" | sudo tee -a "$REPO_ROOT/.gitignore" > /dev/null

# Build
echo ""
echo -e "${CYAN}🚀 Rebuilding system...${RESET}"
LOG=$(mktemp)
(NIX_BUILD_CORES=2 sudo nixos-rebuild switch --flake "$REPO_ROOT#" --impure > "$LOG" 2>&1) &
BUILD_PID=$!
spinner $BUILD_PID "Building NiceOS..." "$LOG"
wait $BUILD_PID
BUILD_EXIT=$?
rm -f "$LOG"
[[ $BUILD_EXIT -eq 0 ]] || { echo -e "${RED}✗ Build failed — check output above${RESET}"; exit 1; }

echo ""
echo -e "${GREEN}✓ Done${RESET}"
echo "Config:    $USER_CONFIG"
echo "Passwords: $USER_PASSWORDS"