#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  London All Hands — Companion Setup Script
#  Run once on each new operator machine.
#  Usage:  bash setup.sh
# ─────────────────────────────────────────────────────────────────────────────

# Re-exec with bash if invoked via sh
[ -z "${BASH_VERSION:-}" ] && exec bash "$0" "$@"

set -e
set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/LondonCompanion.companionconfig"
COMPANION_API="http://localhost:8000"
GSC_REPO="TomsFaire/Google-Slides-Controller"

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'

step()   { echo; echo -e "${BLUE}${BOLD}── $1${NC}"; }
ok()     { echo -e "${GREEN}  ✓ $1${NC}"; }
warn()   { echo -e "${YELLOW}  ⚠ $1${NC}"; }
err()    { echo -e "${RED}  ✗ $1${NC}"; }
prompt() { read -rp "$(echo -e "  ${BOLD}→ $1:${NC} ")" "$2"; }
pause()  { read -rp "$(echo -e "  ${BOLD}Press Enter to continue...${NC}")"; }

# ── Preflight ─────────────────────────────────────────────────────────────────
clear
echo -e "${BOLD}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║     London All Hands — Companion Setup           ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "  This script will:"
echo "   1. Install Homebrew and Bitfocus Companion"
echo "   2. Download and install Google Slides Opener"
echo "   3. Download and install Zoom Rooms Custom AV Controller"
echo "   4. Pause for you to manually install ZoomOSC ISO (licensed)"
echo "   5. Import the Companion module + config (2 guided steps)"
echo "   6. Prompt for show details and push them into Companion"
echo
pause

if [[ ! -f "$CONFIG_FILE" ]]; then
    err "Cannot find LondonCompanion.companionconfig next to this script."
    err "Run this from inside the LondonAH-Companion folder."
    exit 1
fi

# ── 1. Homebrew ───────────────────────────────────────────────────────────────
step "Homebrew"
if ! command -v brew &>/dev/null; then
    warn "Not found — installing Homebrew (you may be prompted for your password)..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    [[ -f /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
    [[ -f /usr/local/bin/brew   ]] && eval "$(/usr/local/bin/brew shellenv)"
fi
ok "Homebrew $(brew --version | head -1)"

# ── 2. Bitfocus Companion ─────────────────────────────────────────────────────
step "Bitfocus Companion"
if [[ ! -d "/Applications/Companion.app" ]]; then
    warn "Not found — installing via Homebrew cask..."
    brew install --cask companion
    ok "Companion installed"
else
    ok "Companion already installed"
fi

# ── 3. Google Slides Opener ───────────────────────────────────────────────────
step "Google Slides Opener"

# Resolve latest release asset URLs from GitHub API
warn "Fetching latest release info..."
RELEASE_JSON=$(curl -sf https://api.github.com/repos/$GSC_REPO/releases/latest)
RELEASE_TAG=$(echo "$RELEASE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['tag_name'])")

# Pick arm64 or x64 based on this machine's architecture
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    APP_URL=$(echo "$RELEASE_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(next(a['browser_download_url'] for a in d['assets'] if 'arm64-mac' in a['name']))")
else
    APP_URL=$(echo "$RELEASE_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(next(a['browser_download_url'] for a in d['assets'] if 'x64-mac' in a['name']))")
fi
MODULE_URL=$(echo "$RELEASE_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(next(a['browser_download_url'] for a in d['assets'] if a['name'].endswith('.tgz')))")
MODULE_FILE="$SCRIPT_DIR/companion-module-gslide-opener.tgz"

if [[ ! -d "/Applications/Google Slides Opener.app" ]]; then
    warn "Downloading Google Slides Opener $RELEASE_TAG ($ARCH)..."
    curl -L --progress-bar "$APP_URL" -o /tmp/gslide-opener.zip
    warn "Installing..."
    unzip -q /tmp/gslide-opener.zip -d /tmp/gslide-opener-extracted
    # Find and move the .app (it may be nested in the zip)
    APP_PATH=$(find /tmp/gslide-opener-extracted -name "*.app" -maxdepth 2 | head -1)
    cp -r "$APP_PATH" "/Applications/Google Slides Opener.app"
    rm -rf /tmp/gslide-opener.zip /tmp/gslide-opener-extracted
    ok "Google Slides Opener installed"
else
    ok "Google Slides Opener already installed"
fi

# Clear Gatekeeper quarantine (unsigned build)
warn "Clearing Gatekeeper quarantine..."
xattr -dr com.apple.quarantine "/Applications/Google Slides Opener.app" 2>/dev/null || true
ok "Gatekeeper cleared"

# Download companion module .tgz if not already present
if [[ ! -f "$MODULE_FILE" ]]; then
    warn "Downloading Companion module .tgz..."
    curl -L --progress-bar "$MODULE_URL" -o "$MODULE_FILE"
fi
ok "Companion module ready: $MODULE_FILE"

# Launch Google Slides Opener
if ! curl -sf http://127.0.0.1:9595/api/status &>/dev/null; then
    warn "Starting Google Slides Opener..."
    open -a "Google Slides Opener"
    sleep 3
fi
if curl -sf http://127.0.0.1:9595/api/status &>/dev/null; then
    ok "Google Slides Opener running on port 9595"
else
    warn "Google Slides Opener may still be starting — verify it's open before the show"
fi

# ── 4. Zoom Rooms Custom AV Controller (CavZRC) ───────────────────────────────
step "Zoom Rooms Custom AV Controller (CavZRC)"
CAVZRC_DMG="/tmp/ZoomRoomsCustomAVController.dmg"
if [[ ! -d "/Applications/ZoomRoomsCustomAVController.app" ]] && \
   [[ ! -d "/Applications/Zoom Rooms Custom AV Controller.app" ]]; then
    warn "Downloading CavZRC..."
    curl -L --progress-bar "https://zoom.us/client/latest/ZoomRoomsCustomAVController.dmg" \
        -o "$CAVZRC_DMG"
    warn "Mounting installer..."
    hdiutil attach "$CAVZRC_DMG" -quiet -nobrowse
    MOUNT=$(hdiutil info | grep "ZoomRooms" | grep "Volumes" | awk '{print $NF}')
    APP=$(find "$MOUNT" -name "*.app" -maxdepth 2 | head -1)
    cp -r "$APP" /Applications/
    hdiutil detach "$MOUNT" -quiet
    rm -f "$CAVZRC_DMG"
    ok "CavZRC installed"
else
    ok "CavZRC already installed"
fi

# ── 5. ZoomOSC ────────────────────────────────────────────────────────────────
step "ZoomOSC ISO  ⚠ manual install required"
echo
echo "  ZoomOSC ISO is a licensed app from Liminal and must be installed manually."
echo
echo "  1. Download ZoomOSC ISO from https://www.liminalet.com"
echo "  2. Install and launch it"
echo "  3. Sign into your Zoom account inside ZoomOSC"
echo
pause

# ── 6. Launch Companion ───────────────────────────────────────────────────────
step "Launching Companion"
if ! pgrep -x "Companion" &>/dev/null; then
    open -a "Companion"
fi

echo -n "  Waiting for Companion to start"
for i in $(seq 1 30); do
    if curl -sf "$COMPANION_API/api/version" &>/dev/null 2>&1; then
        echo; ok "Companion is ready"; break
    fi
    echo -n "."; sleep 2
    if [[ $i -eq 30 ]]; then
        echo
        warn "Timed out — make sure Companion is open, then press Enter."
        pause
    fi
done

# ── 7. Import the Companion module ────────────────────────────────────────────
step "Import the Google Slides Opener module into Companion"
echo
echo "  We need to install the Google Slides Opener module before the config."
echo "  Follow these steps in the browser that's about to open:"
echo
echo "    1. Click  [Modules]  in the left sidebar"
echo "    2. Click  [Import module package]"
echo "    3. Select this file:"
echo -e "       ${BOLD}$MODULE_FILE${NC}"
echo "    4. Confirm the import"
echo
open "http://localhost:8000/modules"
echo
echo "  Module imported?"
pause

# ── 8. Import the config ──────────────────────────────────────────────────────
step "Import the London AH config"
echo
echo "  Now import the full Companion config."
echo "  In the browser page that opens:"
echo
echo "    1. Click  [Import]"
echo "    2. Select:"
echo -e "       ${BOLD}$CONFIG_FILE${NC}"
echo "    3. Click  [Import full config]"
echo "    4. Companion will restart — wait for it to come back up"
echo
open "http://localhost:8000/settings/import-export"
echo
echo "  Config imported and Companion restarted?"
pause

# Wait for Companion to come back after restart
echo -n "  Waiting for Companion to restart"
sleep 5
for i in $(seq 1 20); do
    if curl -sf "$COMPANION_API/api/version" &>/dev/null 2>&1; then
        echo; ok "Companion back online"; break
    fi
    echo -n "."; sleep 2
    if [[ $i -eq 20 ]]; then
        echo
        warn "Companion seems slow — if it's up, press Enter to continue anyway."
        pause
    fi
done

# ── 8. Pre-show variables ─────────────────────────────────────────────────────
step "Show details"
echo "  Enter the details for this show."
echo "  (Speaker fields are optional — press Enter to skip.)"
echo

prompt "Zoom Meeting ID"                          MEETING_ID
prompt "Zoom Passcode"                            MEETING_PASS
prompt "Google Slides URL"                        SLIDES_URL
prompt "London Zoom room display name (Speaker0)" SPEAKER0
prompt "Speaker 1 — remote guest display name"   SPEAKER1
prompt "Speaker 2 — remote guest display name"   SPEAKER2
prompt "Speaker 3 — remote guest display name"   SPEAKER3

step "Applying variables to Companion"

set_var() {
    local name=$1 value=$2
    [[ -z "$value" ]] && return
    if curl -sf -X POST "$COMPANION_API/api/custom-variable/$name/value" \
        -H "Content-Type: application/json" \
        -d "{\"value\": \"$value\"}" &>/dev/null; then
        ok "$name = $value"
    else
        err "Failed to set $name — set it manually in Companion > Custom Variables"
    fi
}

set_var "meetingID"       "$MEETING_ID"
set_var "meetingPasscode" "$MEETING_PASS"
set_var "Slides"          "$SLIDES_URL"
set_var "Speaker0"        "$SPEAKER0"
set_var "Speaker1"        "$SPEAKER1"
set_var "Speaker2"        "$SPEAKER2"
set_var "Speaker3"        "$SPEAKER3"

# ── Done ──────────────────────────────────────────────────────────────────────
echo
echo -e "${GREEN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║               Setup complete! 🎉                 ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "  Before the show, check these off:"
echo "   □ Launch ZoomOSC ISO (must be running before Companion connects)"
echo "   □ Launch CavZRC"
echo "   □ Launch Google Slides Opener"
echo "   □ Connect Stream Deck or XKeys"
echo "   □ Set timer names and messages in StageTimer.io (room ID: E5KJ2Y79)"
echo "   □ Verify all 4 connections show green in Companion > Connections"
echo
