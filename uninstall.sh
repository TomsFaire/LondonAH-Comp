#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  London All Hands — Companion Uninstall / Reset Script
#  Removes everything installed by setup.sh so the machine can be re-provisioned.
#  Homebrew itself is NOT removed.
#  Usage:  bash uninstall.sh
# ─────────────────────────────────────────────────────────────────────────────

[ -z "${BASH_VERSION:-}" ] && exec bash "$0" "$@"

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'

step() { echo; echo -e "${BLUE}${BOLD}── $1${NC}"; }
ok()   { echo -e "${GREEN}  ✓ $1${NC}"; }
warn() { echo -e "${YELLOW}  ⚠ $1${NC}"; }
skip() { echo -e "  · $1 (not found, skipping)"; }

clear
echo -e "${BOLD}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║   London All Hands — Companion Reset / Uninstall ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "  This will remove:"
echo "   • Bitfocus Companion (app + all config data)"
echo "   • Google Slides Opener"
echo "   • ZoomOSC ISO"
echo "   • Zoom Rooms Custom AV Controller (CavZRC)"
echo "   • The prepared LondonCompanion_configured.companionconfig"
echo
echo -e "  ${YELLOW}${BOLD}Homebrew will NOT be removed.${NC}"
echo
read -rp "$(echo -e "  ${BOLD}Are you sure? Type YES to continue:${NC} ")" CONFIRM
[[ "$CONFIRM" != "YES" ]] && echo "  Aborted." && exit 0

# ── 1. Kill running processes ─────────────────────────────────────────────────
step "Stopping running apps"

for proc in "Companion" "ZoomOSC" "ZoomRoomsCustomAVController" "Google Slides Opener"; do
    if pgrep -f "$proc" &>/dev/null; then
        pkill -f "$proc" 2>/dev/null && ok "Stopped: $proc" || warn "Could not stop $proc — you may need to quit it manually"
    else
        skip "$proc not running"
    fi
done
sleep 2

# ── 2. Bitfocus Companion ─────────────────────────────────────────────────────
step "Removing Bitfocus Companion"

if brew list --cask companion &>/dev/null 2>&1; then
    brew uninstall --cask companion && ok "Companion removed via Homebrew"
elif [[ -d "/Applications/Companion.app" ]]; then
    rm -rf "/Applications/Companion.app" && ok "Companion.app removed"
else
    skip "Companion not found in Homebrew or /Applications"
fi

# Remove Companion config/data directory (modules, imported config, variables)
COMPANION_DATA="$HOME/Library/Application Support/companion"
if [[ -d "$COMPANION_DATA" ]]; then
    rm -rf "$COMPANION_DATA"
    ok "Companion data directory removed"
else
    skip "Companion data directory not found"
fi

# ── 3. Google Slides Opener ───────────────────────────────────────────────────
step "Removing Google Slides Opener"

GSC_APP=$(find /Applications -maxdepth 1 -iname "*slides*opener*" -o -iname "*google*slides*" 2>/dev/null | head -1)
if [[ -n "$GSC_APP" ]]; then
    rm -rf "$GSC_APP" && ok "Removed: $GSC_APP"
else
    skip "Google Slides Opener not found in /Applications"
fi

# ── 4. ZoomOSC ISO ────────────────────────────────────────────────────────────
step "Removing ZoomOSC ISO"

ZOOMOSC_APP=$(find /Applications -maxdepth 1 -iname "*zoomosc*" 2>/dev/null | head -1)
if [[ -n "$ZOOMOSC_APP" ]]; then
    rm -rf "$ZOOMOSC_APP" && ok "Removed: $ZOOMOSC_APP"
else
    skip "ZoomOSC not found in /Applications"
fi

# ── 5. Zoom Rooms Custom AV Controller (CavZRC) ───────────────────────────────
step "Removing Zoom Rooms Custom AV Controller"

CAVZRC_APP=$(find /Applications -maxdepth 1 -iname "*ZoomRooms*AV*" -o -iname "*ZoomRoomsCustom*" 2>/dev/null | head -1)
if [[ -n "$CAVZRC_APP" ]]; then
    rm -rf "$CAVZRC_APP" && ok "Removed: $CAVZRC_APP"
else
    skip "ZoomRoomsCustomAVController not found in /Applications"
fi

# ── 6. Configured companion config ───────────────────────────────────────────
step "Removing prepared config files"

PATCHED="$SCRIPT_DIR/LondonCompanion_configured.companionconfig"
if [[ -f "$PATCHED" ]]; then
    rm -f "$PATCHED" && ok "Removed: $PATCHED"
else
    skip "No prepared config file found"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo
echo -e "${GREEN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║           Reset complete — clean slate!          ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "  You can now run setup.sh again to re-provision this machine."
echo
