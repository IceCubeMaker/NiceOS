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

# ── Checks ────────────────────────────────────────────────────────────────────
[[ -f /etc/NIXOS ]] || { echo -e "${RED}Not NixOS${RESET}"; exit 1; }
command -v git          >/dev/null || { echo -e "${RED}git required${RESET}"; exit 1; }
command -v nixos-rebuild >/dev/null || { echo -e "${RED}nixos-rebuild not found${RESET}"; exit 1; }
sudo -v

# ── Detect capabilities ───────────────────────────────────────────────────────

# Does nixos-rebuild accept --flake?
HAVE_FLAKE_FLAG=0
if nixos-rebuild --help 2>&1 | grep -q -- "--flake"; then
  HAVE_FLAKE_FLAG=1
fi

# Does nix support flakes at all (either already enabled or new enough to pass inline)?
HAVE_FLAKES=0
if nix flake --version >/dev/null 2>&1 || \
   NIX_CONFIG="experimental-features = nix-command flakes" nix flake --version >/dev/null 2>&1; then
  HAVE_FLAKES=1
fi

# Does nixos-generate-config support --show-hardware-config?
HAVE_SHOW_HW=0
if nixos-generate-config --help 2>&1 | grep -q -- "--show-hardware-config"; then
  HAVE_SHOW_HW=1
fi

# ── Clone / update repo ───────────────────────────────────────────────────────
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

# ── Flake check ───────────────────────────────────────────────────────────────
if [[ ! -f "$REPO_ROOT/flake.nix" ]]; then
  if [[ $HAVE_FLAKE_FLAG -eq 1 ]]; then
    echo -e "${RED}flake.nix not found in repo${RESET}"; exit 1
  else
    echo -e "${DIM}  No flake.nix — using classic nixos-rebuild${RESET}"
  fi
fi

# ── Safe directory ────────────────────────────────────────────────────────────
sudo git config --global --add safe.directory "$REPO_ROOT"

# ── Point /etc/nixos at repo ──────────────────────────────────────────────────
sudo ln -sfn "$REPO_ROOT" /etc/nixos

# ── Hardware config ───────────────────────────────────────────────────────────
HW_FILE="$REPO_ROOT/hardware-configuration.nix"
if [[ ! -f "$HW_FILE" ]]; then
  echo -e "${CYAN}Generating hardware configuration...${RESET}"
  if [[ $HAVE_SHOW_HW -eq 1 ]]; then
    sudo nixos-generate-config --show-hardware-config | sudo tee "$HW_FILE" > /dev/null
  else
    # Older: generate in place then copy out
    sudo nixos-generate-config --dir /tmp/niceos-hwcfg
    sudo cp /tmp/niceos-hwcfg/hardware-configuration.nix "$HW_FILE"
    sudo rm -rf /tmp/niceos-hwcfg
  fi
fi

# ── User config dir ───────────────────────────────────────────────────────────
sudo mkdir -p "$USER_CONFIG_DIR"

if [[ ! -f "$USER_CONFIG" ]]; then
  sudo cp "$REPO_ROOT/core/templates/user-configuration-template.nix" "$USER_CONFIG"
  sudo sed -i "s/__USERNAME__/$TARGET_USER/g" "$USER_CONFIG" || true
fi

if [[ ! -f "$USER_PASSWORDS" ]]; then
  sudo cp "$REPO_ROOT/core/templates/passwords-template.nix" "$USER_PASSWORDS"
fi
sudo chown root:root "$USER_PASSWORDS"
sudo chmod 644 "$USER_PASSWORDS"

# ── Git init for user config dir ──────────────────────────────────────────────
if [[ ! -d "$USER_CONFIG_DIR/.git" ]]; then
  sudo git -C "$USER_CONFIG_DIR" init
  sudo git -C "$USER_CONFIG_DIR" add configuration.nix || true
  sudo git -C "$USER_CONFIG_DIR" commit -m "initial NiceOS config" || true
fi

# ── Enable flakes in nix.conf (persists for future boots) ────────────────────
sudo mkdir -p /etc/nix
if ! grep -q "experimental-features" /etc/nix/nix.conf 2>/dev/null; then
  echo "experimental-features = nix-command flakes" | sudo tee -a /etc/nix/nix.conf > /dev/null
fi

# ── gitignore ─────────────────────────────────────────────────────────────────
grep -qxF "hardware-configuration.nix" "$REPO_ROOT/.gitignore" 2>/dev/null || \
  echo "hardware-configuration.nix" | sudo tee -a "$REPO_ROOT/.gitignore" > /dev/null

# ── Build ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}🚀 Rebuilding system...${RESET}"
LOG=$(mktemp)

build_cmd() {
  # Pass NIX_BUILD_CORES explicitly since sudo drops env vars.
  # Pass NIX_CONFIG to enable flakes inline — no daemon restart needed.
  if [[ $HAVE_FLAKE_FLAG -eq 1 && $HAVE_FLAKES -eq 1 ]]; then
    sudo env \
      NIX_BUILD_CORES=2 \
      NIX_CONFIG="experimental-features = nix-command flakes" \
      nixos-rebuild switch --flake "$REPO_ROOT#" --impure
  else
    # Fallback: classic rebuild, config already linked to /etc/nixos
    sudo env NIX_BUILD_CORES=2 nixos-rebuild switch
  fi
}

(build_cmd > "$LOG" 2>&1) &
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