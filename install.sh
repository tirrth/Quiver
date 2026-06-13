#!/bin/zsh
# Builds Quiver and installs it to /Applications, then launches it.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$ROOT_DIR/build.sh"

APP_SRC="$ROOT_DIR/build/Quiver.app"
DEST="/Applications/Quiver.app"

# Quit any running copy so we can replace it cleanly.
osascript -e 'tell application "Quiver" to quit' 2>/dev/null || true
pkill -x Quiver 2>/dev/null || true
sleep 1

# Clean up any older copy left in ~/Applications by earlier installs.
rm -rf "$HOME/Applications/Quiver.app" "$HOME/Desktop/Quiver.app" 2>/dev/null || true

# Install to /Applications — a direct copy if it's writable (admins usually can),
# otherwise an admin copy with the standard macOS prompt.
rm -rf "$DEST" 2>/dev/null || true
if ! cp -R "$APP_SRC" "$DEST" 2>/dev/null; then
  osascript -e "do shell script \"rm -rf '$DEST'; cp -R '$APP_SRC' '$DEST'\" with administrator privileges"
fi

open "$DEST"
echo "Installed Quiver to $DEST"
