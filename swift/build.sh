#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="AXE Fleet"
BUILD_DIR="$SCRIPT_DIR/.build/release"
APP_DIR="$SCRIPT_DIR/dist/${APP_NAME}.app"

echo "[AXE] Building AXE Fleet Monitor..."
echo "[AXE] Swift: $(swift --version 2>&1 | head -1)"

cd "$SCRIPT_DIR"
swift build -c release 2>&1

BINARY="$BUILD_DIR/AXEFleet"
if [ ! -f "$BINARY" ]; then
    echo "[FAIL] Binary not found at $BINARY"
    exit 1
fi

echo "[+] Binary: $(du -h "$BINARY" | cut -f1)"

# Create .app bundle
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BINARY" "$APP_DIR/Contents/MacOS/AXEFleet"
cp "$SCRIPT_DIR/Info.plist" "$APP_DIR/Contents/"

# Copy icon resources
if [ -d "$SCRIPT_DIR/Resources" ]; then
    cp "$SCRIPT_DIR/Resources/"* "$APP_DIR/Contents/Resources/" 2>/dev/null || true
fi

echo "[+] Bundle: $APP_DIR"
echo "[+] Size: $(du -sh "$APP_DIR" | cut -f1)"

# Optional install to /Applications
if [ "${1:-}" = "--install" ]; then
    INSTALL_DIR="/Applications/${APP_NAME}.app"
    echo "[AXE] Installing to $INSTALL_DIR..."
    rm -rf "$INSTALL_DIR"
    cp -R "$APP_DIR" "$INSTALL_DIR"
    echo "[+] Installed. Launch: open '/Applications/${APP_NAME}.app'"
fi

echo "[AXE] Build complete."
