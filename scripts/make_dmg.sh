#!/bin/zsh
# Packages build/Quiver.app into a compressed, distributable disk image with an Applications link.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT_DIR/build/Quiver.app"
[[ -d "$APP" ]] || { echo "Build first: ./build.sh"; exit 1; }

STAGE="$ROOT_DIR/build/dmg"
DMG="$ROOT_DIR/build/Quiver.dmg"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "Quiver" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "Created $DMG"
