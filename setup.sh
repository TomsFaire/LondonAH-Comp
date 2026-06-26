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

# Clean up any temp files on exit (handles crashes and early exits)
trap 'rm -rf /tmp/Companion.dmg /tmp/gslide-opener.zip /tmp/gslide-opener-extracted /tmp/ZoomRoomsCustomAVController.dmg /tmp/ZoomOSC-Installer.dmg /tmp/ZoomOSC-download.zip /tmp/zoomosc-zip 2>/dev/null; rm -f "${SCRIPT_DIR}/LondonCompanion_configured.companionconfig" 2>/dev/null' EXIT

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

# gatekeeper_guide APP_DISPLAY_NAME — opens Privacy & Security and shows bypass steps
# Call this immediately after attempting to open an app that Gatekeeper may block.
gatekeeper_guide() {
    local name="$1"
    echo
    echo -e "  ${YELLOW}${BOLD}Gatekeeper security warning — action required:${NC}"
    echo "  ┌──────────────────────────────────────────────────────────────────┐"
    echo "  │  macOS may have blocked $name with a                            │"
    echo "  │  'cannot be opened because the developer cannot be verified'     │"
    echo "  │  dialog. If that happened:                                        │"
    echo "  │                                                                   │"
    echo "  │  1. Click  [Done]  on the Gatekeeper warning to dismiss it       │"
    echo "  │  2. System Settings → Privacy & Security is opening now          │"
    echo "  │  3. Scroll down to the Security section — you will see:          │"
    echo "  │       \"$name was blocked from use...\"                          │"
    echo "  │  4. Click  [Open Anyway]                                         │"
    echo "  │  5. Click  [Open]  in the final confirmation dialog              │"
    echo "  │                                                                   │"
    echo "  │  If the app launched normally, skip this and continue below.     │"
    echo "  └──────────────────────────────────────────────────────────────────┘"
    echo
    open "x-apple.systempreferences:com.apple.preference.security" 2>/dev/null || \
        open "x-apple.systempreferences:com.apple.security" 2>/dev/null || true
}

# check_port PORT NAME — warns if UDP/TCP port is already in use
check_port() {
    local port="$1" name="$2"
    if lsof -iTCP:"$port" -sTCP:LISTEN -t &>/dev/null 2>&1 || \
       lsof -iUDP:"$port" -t &>/dev/null 2>&1; then
        warn "Port $port ($name) appears to be in use. Another process may be occupying it."
        echo -e "  ${YELLOW}  Run: lsof -i :$port${NC}  to identify and quit the conflicting app."
    else
        ok "Port $port ($name) is available"
    fi
}

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
    warn "Not found — trying Homebrew cask..."
    if brew reinstall --cask companion 2>&1; then
        ok "Companion installed via Homebrew"
    else
        warn "Homebrew install failed — falling back to direct download..."
        COMPANION_ARCH=$(uname -m | sed 's/x86_64/x64/;s/arm64/arm64/')
        COMPANION_JSON=$(curl -sf "https://api.bitfocus.io/v1/product/companion/packages?branch=stable&limit=10")
        COMPANION_URL=$(echo "$COMPANION_JSON" | python3 -c "
import json,sys
pkgs = json.load(sys.stdin)['packages']
mac = [p for p in pkgs if 'mac-$COMPANION_ARCH' in p.get('target','') or 'mac' in p.get('target','')]
print(mac[0]['url'])
" 2>/dev/null)
        if [[ -z "$COMPANION_URL" ]]; then
            err "Could not resolve Companion download URL."
            err "Download manually from https://bitfocus.io/companion, install it, then re-run."
            exit 1
        fi
        warn "Downloading Companion from $COMPANION_URL ..."
        curl -L --progress-bar "$COMPANION_URL" -o /tmp/Companion.dmg
        COMPANION_MOUNT_OUTPUT=$(hdiutil attach /tmp/Companion.dmg -nobrowse 2>&1)
        MOUNT=$(echo "$COMPANION_MOUNT_OUTPUT" | awk -F'\t' '/\/Volumes\//{print $NF}' | head -1)
        cp -r "$MOUNT/Companion.app" /Applications/
        hdiutil detach "$MOUNT" -quiet
        rm -f /tmp/Companion.dmg
        ok "Companion installed via direct download"
    fi
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
    CAVZRC_MOUNT_OUTPUT=$(hdiutil attach "$CAVZRC_DMG" -nobrowse 2>&1)
    MOUNT=$(echo "$CAVZRC_MOUNT_OUTPUT" | awk -F'\t' '/\/Volumes\//{print $NF}' | head -1)
    APP=$(find "$MOUNT" -name "*.app" -maxdepth 2 | head -1)
    cp -r "$APP" /Applications/
    hdiutil detach "$MOUNT" -quiet
    rm -f "$CAVZRC_DMG"
    ok "CavZRC installed"
else
    ok "CavZRC already installed"
fi

# Clear Gatekeeper quarantine on installed app
warn "Clearing Gatekeeper quarantine on CavZRC..."
CAVZRC_APP=$(find /Applications -maxdepth 1 \( -name "*ZoomRooms*AV*" -o -name "*ZoomRoomsCustom*" \) 2>/dev/null | head -1)
if [[ -n "$CAVZRC_APP" ]]; then
    xattr -dr com.apple.quarantine "$CAVZRC_APP" 2>/dev/null || true
    ok "Quarantine cleared: $CAVZRC_APP"
else
    warn "CavZRC app not found in /Applications — quarantine not cleared"
fi

# Launch CavZRC and guide OSC config
step "Configuring CavZRC OSC Ports"
echo "  Checking required ports..."
check_port 9090 "CavZRC TX"
check_port 1236 "CavZRC RX"
echo
warn "Launching CavZRC — macOS may show a security warning..."
open -a "ZoomRoomsCustomAVController" 2>/dev/null || open -a "Zoom Rooms Custom AV Controller" 2>/dev/null || true
sleep 2
gatekeeper_guide "ZoomRoomsCustomAVController"
echo -e "  ${BOLD}Once CavZRC is open, continue to the next step.${NC}"
pause
echo
echo -e "  ${BOLD}Configure CavZRC OSC settings:${NC}"
echo "  ┌─────────────────────────────────────────────────┐"
echo "  │  In CavZRC → OSC Settings (top-right button)   │"
echo "  │                                                  │"
echo "  │  Enable OSC for network control  →  ON          │"
echo "  │  Transmission IP                 →  127.0.0.1   │"
echo "  │  Transmission Port               →  9090         │"
echo "  │  Receiving Port                  →  1236         │"
echo "  │  OSC Output Header               →  /roomosc     │"
echo "  │  OSC Network Interface           →  All          │"
echo "  │  Use IP Allow List               →  OFF          │"
echo "  └─────────────────────────────────────────────────┘"
echo "  Sign in with your Zoom account, pair your Zoom Room, then click OK."
echo
pause

# ── 5. ZoomOSC ────────────────────────────────────────────────────────────────
step "ZoomOSC ISO"
ZOOMOSC_DMG="/tmp/ZoomOSC-Installer.dmg"
ZOOMOSC_GDRIVE_ID="1-IuWmsTWFmBkJ97aqRTGoD2tIZPFw8Xe"
if [[ ! -d "/Applications/ZoomOSC.app" ]]; then
    warn "Downloading ZoomOSC installer from Google Drive..."
    curl -L --progress-bar \
        "https://drive.usercontent.google.com/download?id=${ZOOMOSC_GDRIVE_ID}&export=download&confirm=t" \
        -o "$ZOOMOSC_DMG"

    # Verify we got an actual DMG
    FILETYPE=$(file -b "$ZOOMOSC_DMG")
    if ! echo "$FILETYPE" | grep -qi "zlib\|x86\|boot\|data\|image"; then
        err "Download did not produce a valid DMG (got: $FILETYPE)."
        err "Download the DMG manually from https://drive.google.com/file/d/${ZOOMOSC_GDRIVE_ID}/view"
        err "Save it to /tmp/ZoomOSC-Installer.dmg then press Enter."
        rm -f "$ZOOMOSC_DMG"
        pause
    fi

    # Clear quarantine so macOS lets hdiutil mount it
    xattr -dr com.apple.quarantine "$ZOOMOSC_DMG" 2>/dev/null || true

    warn "Mounting installer..."
    MOUNT_OUTPUT=$(hdiutil attach "$ZOOMOSC_DMG" -nobrowse 2>&1)
    MOUNT=$(echo "$MOUNT_OUTPUT" | awk -F'\t' '/\/Volumes\//{print $NF}' | head -1)
    if [[ -z "$MOUNT" ]]; then
        err "Failed to mount ZoomOSC DMG."
        err "Download manually from https://drive.google.com/file/d/${ZOOMOSC_GDRIVE_ID}/view and install ZoomOSC, then press Enter."
        rm -f "$ZOOMOSC_DMG"
        pause
    else
        PKG=$(find "$MOUNT" -name "*.pkg" -maxdepth 2 | head -1)
        APP=$(find "$MOUNT" -name "*.app" -maxdepth 2 | head -1)
        if [[ -n "$PKG" ]]; then
            sudo installer -pkg "$PKG" -target /
        elif [[ -n "$APP" ]]; then
            cp -r "$APP" /Applications/
        fi
        hdiutil detach "$MOUNT" -quiet || true
        rm -f "$ZOOMOSC_DMG"
        ok "ZoomOSC installed"
    fi
else
    ok "ZoomOSC already installed"
fi

# Clear Gatekeeper quarantine on installed ZoomOSC app
warn "Clearing Gatekeeper quarantine on ZoomOSC..."
ZOOMOSC_APP=$(find /Applications -maxdepth 1 -iname "*zoomosc*" 2>/dev/null | head -1)
if [[ -n "$ZOOMOSC_APP" ]]; then
    xattr -dr com.apple.quarantine "$ZOOMOSC_APP" 2>/dev/null || true
    ok "Quarantine cleared: $ZOOMOSC_APP"
else
    warn "ZoomOSC app not found in /Applications — quarantine not cleared"
fi

step "Configuring ZoomOSC OSC Ports"
echo "  Checking required ports..."
check_port 1234 "ZoomOSC TX"
check_port 9091 "ZoomOSC RX"
echo
warn "Launching ZoomOSC — macOS may show a security warning..."
open -a "ZoomOSC" 2>/dev/null || true
sleep 2
gatekeeper_guide "ZoomOSC"
echo -e "  ${BOLD}Once ZoomOSC is open, continue to the next step.${NC}"
pause
echo
echo -e "  ${BOLD}Configure ZoomOSC OSC settings:${NC}"
echo "  ┌──────────────────────────────────────────────────────┐"
echo "  │  In ZoomOSC → OSC Settings tab, enter:              │"
echo "  │                                                       │"
echo "  │  Transmission IP       →  127.0.0.1                  │"
echo "  │  Transmission Port     →  1234                        │"
echo "  │  Receiving Port        →  9091                        │"
echo "  │  OSC Output Rate       →  Fastest Possible            │"
echo "  │  Listen to Interface   →  All                         │"
echo "  │  Subscribe to          →  All                         │"
echo "  │  Gallery Tracking Mode →  Zoom ID                     │"
echo "  └──────────────────────────────────────────────────────┘"
echo "  Sign in with your Zoom account, configure the settings above, then press Go."
echo
pause

# ── 6. Launch Companion ───────────────────────────────────────────────────────
step "Launching Companion"
if ! pgrep -x "Companion" &>/dev/null; then
    open -a "Companion"
fi

echo -n "  Waiting for Companion to start"
for i in $(seq 1 30); do
    if curl -sf "$COMPANION_API/" &>/dev/null 2>&1; then
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
echo "    3. Import each of these files one at a time:"
echo -e "       ${BOLD}$MODULE_FILE${NC}  (Google Slides Opener)"
CAVZRC_MODULE=$(find "$SCRIPT_DIR" -name "companion-module-cavzrc*.tgz" -maxdepth 1 | head -1)
if [[ -n "$CAVZRC_MODULE" ]]; then
    echo -e "       ${BOLD}$CAVZRC_MODULE${NC}  (CavZRC)"
else
    warn "companion-module-cavzrc .tgz not found next to this script."
    warn "Build it from https://github.com/TomsFaire/companion-module-cavzrc and add it to this folder,"
    warn "or install zoom-cavzrc from the Companion module store instead."
fi
echo "    4. Confirm each import"
echo
open "http://localhost:8000/modules"
echo
echo "  All modules imported?"
pause

# ── 8. StageTimer credentials ────────────────────────────────────────────────
step "StageTimer configuration"
echo "  The Companion config needs your StageTimer credentials."
echo "  Find your API key at: stagetimer.io → Settings → API"
echo
prompt "StageTimer Room ID  (e.g. E5KJ2Y79)" ST_ROOM_ID
prompt "StageTimer API Key" ST_API_KEY
echo

PATCHED_CONFIG="$SCRIPT_DIR/LondonCompanion_configured.companionconfig"
cp "$CONFIG_FILE" "$PATCHED_CONFIG"
[[ -n "$ST_ROOM_ID" ]] && sed -i '' "s/__STAGETIMER_ROOM_ID__/$ST_ROOM_ID/g" "$PATCHED_CONFIG"
[[ -n "$ST_API_KEY" ]] && sed -i '' "s/__STAGETIMER_API_KEY__/$ST_API_KEY/g" "$PATCHED_CONFIG"
CONFIG_FILE="$PATCHED_CONFIG"
ok "Config prepared — saved next to setup.sh as:"
echo -e "     ${BOLD}$CONFIG_FILE${NC}"

# ── 9. Import the config ──────────────────────────────────────────────────────
step "Import the London AH config"
echo
echo "  Now import the full Companion config."
echo "  A Finder window will open showing the file to import."
echo
echo "  In the browser page that opens:"
echo
echo "    1. Click  [Import]"
echo "    2. Select the highlighted file:"
echo -e "       ${BOLD}$CONFIG_FILE${NC}"
echo "    3. Click  [Import full config]"
echo "    4. Companion will restart — wait for it to come back up"
echo
open -R "$CONFIG_FILE"
open "http://localhost:8000/import-export"
echo
echo "  Config imported and Companion restarted?"
pause

# Wait for Companion to come back after restart
echo -n "  Waiting for Companion to restart"
sleep 5
for i in $(seq 1 20); do
    if curl -sf "$COMPANION_API/" &>/dev/null 2>&1; then
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
