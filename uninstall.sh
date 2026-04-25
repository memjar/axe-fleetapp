#!/bin/bash
# AXE Fleet Notify — Uninstaller

set -euo pipefail

PLIST_DST="$HOME/Library/LaunchAgents/com.axe.fleet-notify.plist"
CLI_LINK="$HOME/.local/bin/axe-fleet"

echo "[AXE] AXE Fleet Notify — Uninstaller"
echo ""

if launchctl list | grep -q "com.axe.fleet-notify" 2>/dev/null; then
    launchctl unload "$PLIST_DST" 2>/dev/null || true
    echo "[OK] Daemon stopped"
fi

rm -f "$PLIST_DST"
echo "[OK] LaunchAgent removed"

rm -f "$CLI_LINK"
echo "[OK] CLI removed"

echo ""
echo "Done. Config and logs preserved in this directory."
echo "To fully remove: rm -rf $(cd "$(dirname "$0")" && pwd)"
