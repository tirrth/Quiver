#!/bin/zsh
# Builds Quiver, installs it to ~/Applications, adds a Desktop alias, and launches it.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$ROOT_DIR/build.sh"

APP_SRC="$ROOT_DIR/build/Quiver.app"
DEST_DIR="$HOME/Applications"
DEST="$DEST_DIR/Quiver.app"

mkdir -p "$DEST_DIR"

# Quit any running copy so we can replace it cleanly.
osascript -e 'tell application "Quiver" to quit' 2>/dev/null || true
pkill -x Quiver 2>/dev/null || true
sleep 1

rm -rf "$DEST"
cp -R "$APP_SRC" "$DEST"

ln -sfn "$DEST" "$HOME/Desktop/Quiver.app" 2>/dev/null || true

open -R "$DEST"
open "$DEST"
echo "Installed Quiver to $DEST"
