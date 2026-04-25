#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# AXE Fleet Notify — Installer
# Installs LaunchAgent for persistent fleet monitoring
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_SRC="${APP_DIR}/launchagents/com.axe.fleet-notify.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.axe.fleet-notify.plist"
CLI_LINK="$HOME/.local/bin/axe-fleet"

echo "🪓 AXE Fleet Notify — Installer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check deps
if ! command -v python3 &>/dev/null; then
    echo "❌ python3 required but not found"
    exit 1
fi

if ! command -v curl &>/dev/null; then
    echo "❌ curl required but not found"
    exit 1
fi

echo "✅ Dependencies OK (python3, curl, osascript)"

# Create log dirs
mkdir -p "${APP_DIR}/logs/state" "${APP_DIR}/logs/cooldown"
echo "✅ Log directories created"

# Stop existing daemon if running
if launchctl list | grep -q "com.axe.fleet-notify" 2>/dev/null; then
    echo "⏹️  Stopping existing daemon..."
    launchctl unload "$PLIST_DST" 2>/dev/null || true
fi

# Generate plist with correct path
sed "s|INSTALL_DIR|${APP_DIR}|g" "$PLIST_SRC" > "$PLIST_DST"
echo "✅ LaunchAgent installed → $PLIST_DST"

# Load daemon
launchctl load "$PLIST_DST"
echo "✅ Daemon loaded and running"

# Install CLI shortcut
mkdir -p "$(dirname "$CLI_LINK")"
cat > "$CLI_LINK" << EOFCLI
#!/bin/bash
${APP_DIR}/scripts/axe-fleet-notify.sh "\$@"
EOFCLI
chmod +x "$CLI_LINK"
echo "✅ CLI installed → axe-fleet (run: axe-fleet status)"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🪓 AXE Fleet Notify is LIVE"
echo ""
echo "Commands:"
echo "  axe-fleet status     — Show fleet status"
echo "  tail -f ${APP_DIR}/logs/axe-fleet-notify.log — Watch events"
echo ""
echo "To stop:  launchctl unload ~/Library/LaunchAgents/com.axe.fleet-notify.plist"
echo "To start: launchctl load ~/Library/LaunchAgents/com.axe.fleet-notify.plist"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
