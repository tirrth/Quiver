#!/bin/zsh
# Builds Quiver.app from source. Compiles the Swift app shell, and — when present — the
# Objective-C++ AutoRaise engine and the privileged Hosts helper. Produces an ad-hoc signed
# bundle in ./build. Set ARCHS to build universal, e.g. ARCHS="arm64 x86_64" ./build.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Quiver"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
DEPLOY_TARGET="13.0"
: ${ARCHS:="$(uname -m)"}

rm -rf "$APP_DIR"
mkdir -p "$BUILD_DIR" "$MACOS_DIR" "$RESOURCES_DIR"
touch "$BUILD_DIR/.metadata_never_index"

# ---------- App icon (non-fatal if it fails) ----------
ICON_PNG="$BUILD_DIR/AppIcon-1024.png"
ICONSET="$BUILD_DIR/AppIcon.iconset"
if swift "$ROOT_DIR/scripts/generate_icon.swift" "$ICON_PNG" 2>/dev/null && [[ -f "$ICON_PNG" ]]; then
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  sips -z 16 16     "$ICON_PNG" --out "$ICONSET/icon_16x16.png"      >/dev/null
  sips -z 32 32     "$ICON_PNG" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
  sips -z 32 32     "$ICON_PNG" --out "$ICONSET/icon_32x32.png"      >/dev/null
  sips -z 64 64     "$ICON_PNG" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
  sips -z 128 128   "$ICON_PNG" --out "$ICONSET/icon_128x128.png"    >/dev/null
  sips -z 256 256   "$ICON_PNG" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
  sips -z 256 256   "$ICON_PNG" --out "$ICONSET/icon_256x256.png"    >/dev/null
  sips -z 512 512   "$ICON_PNG" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
  sips -z 512 512   "$ICON_PNG" --out "$ICONSET/icon_512x512.png"    >/dev/null
  cp "$ICON_PNG" "$ICONSET/icon_512x512@2x.png"
  iconutil -c icns "$ICONSET" -o "$RESOURCES_DIR/AppIcon.icns"
else
  echo "warning: icon generation skipped"
fi

ARCH_FLAGS=(); for a in ${=ARCHS}; do ARCH_FLAGS+=(-arch $a); done

# ---------- AutoRaise engine (Objective-C++, optional until Phase C) ----------
ENGINE_SRC="$ROOT_DIR/Sources/AutoRaiseEngine/AutoRaiseEngine.mm"
BRIDGING_HEADER="$ROOT_DIR/Sources/AutoRaiseEngine/Quiver-Bridging-Header.h"
ENGINE_OBJ=""
SWIFT_ENGINE_ARGS=()
ENGINE_FRAMEWORKS=()
if [[ -f "$ENGINE_SRC" ]]; then
  SKYLIGHT=0
  [[ -d /System/Library/PrivateFrameworks/SkyLight.framework ]] && SKYLIGHT=1
  ENGINE_OBJ="$BUILD_DIR/AutoRaiseEngine.o"
  echo "Compiling AutoRaise engine (SkyLight=$SKYLIGHT, archs: $ARCHS)"
  xcrun clang++ "${ARCH_FLAGS[@]}" -O2 -fobjc-arc -std=c++17 -Wall \
    -mmacosx-version-min=$DEPLOY_TARGET \
    -DOLD_ACTIVATION_METHOD -DEXPERIMENTAL_FOCUS_FIRST \
    -D"NS_FORMAT_ARGUMENT(A)=" -D"SKYLIGHT_AVAILABLE=$SKYLIGHT" \
    -F /System/Library/PrivateFrameworks \
    -c "$ENGINE_SRC" -o "$ENGINE_OBJ"
  SWIFT_ENGINE_ARGS=(-import-objc-header "$BRIDGING_HEADER")
  # -lc++ links the C++ runtime the Objective-C++ engine needs.
  ENGINE_FRAMEWORKS=(-lc++ -framework ApplicationServices -framework Carbon -F /System/Library/PrivateFrameworks)
  (( SKYLIGHT == 1 )) && ENGINE_FRAMEWORKS+=(-framework SkyLight)
fi

# ---------- Privileged Hosts helper (Swift, optional until Phase B) ----------
HELPER_SRCS=( "$ROOT_DIR"/Sources/QuiverHelper/*.swift(N) )
if (( ${#HELPER_SRCS} )); then
  echo "Compiling QuiverHelper"
  HELPER_BINS=()
  for a in ${=ARCHS}; do
    out="$BUILD_DIR/QuiverHelper-$a"
    xcrun swiftc -target $a-apple-macos$DEPLOY_TARGET -parse-as-library -O \
      "${HELPER_SRCS[@]}" -o "$out"
    HELPER_BINS+=("$out")
  done
  if (( ${#HELPER_BINS} > 1 )); then
    lipo -create "${HELPER_BINS[@]}" -o "$RESOURCES_DIR/QuiverHelper"
  else
    cp "${HELPER_BINS[1]}" "$RESOURCES_DIR/QuiverHelper"
  fi
  chmod 755 "$RESOURCES_DIR/QuiverHelper"
fi

# ---------- Quiver app (Swift) ----------
APP_SWIFT_SRCS=( "$ROOT_DIR"/Sources/Quiver/**/*.swift(N) )
echo "Compiling Quiver (${#APP_SWIFT_SRCS} swift files, archs: $ARCHS)"
APP_BINS=()
for a in ${=ARCHS}; do
  out="$BUILD_DIR/$APP_NAME-$a"
  xcrun swiftc -target $a-apple-macos$DEPLOY_TARGET -parse-as-library -O \
    "${SWIFT_ENGINE_ARGS[@]}" \
    "${APP_SWIFT_SRCS[@]}" \
    ${ENGINE_OBJ:+$ENGINE_OBJ} \
    -framework AppKit -framework SwiftUI \
    "${ENGINE_FRAMEWORKS[@]}" \
    -o "$out"
  APP_BINS+=("$out")
done
if (( ${#APP_BINS} > 1 )); then
  lipo -create "${APP_BINS[@]}" -o "$MACOS_DIR/$APP_NAME"
else
  cp "${APP_BINS[1]}" "$MACOS_DIR/$APP_NAME"
fi
chmod 755 "$MACOS_DIR/$APP_NAME"

# ---------- Bundle metadata + signing ----------
cp "$ROOT_DIR/App/Info.plist" "$CONTENTS_DIR/Info.plist"
printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

# Prefer a stable local identity (see scripts/setup-stable-signing.sh) so macOS keeps the
# Accessibility grant across rebuilds; fall back to ad-hoc if it isn't set up.
SIGN_IDENTITY="${QUIVER_SIGN_IDENTITY:-Quiver Local Signing}"
ENTITLEMENTS="$ROOT_DIR/App/Quiver.entitlements"
if security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1 \
   && codesign --force --deep --sign "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS" "$APP_DIR" 2>/dev/null; then
  echo "Built $APP_DIR (signed: $SIGN_IDENTITY)"
else
  codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" "$APP_DIR" >/dev/null
  echo "Built $APP_DIR (signed: ad-hoc)"
fi
