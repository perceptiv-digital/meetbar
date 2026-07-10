#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="${VERSION:-0.4.0}"
BUILD_NUMBER="${BUILD_NUMBER:-5}"
ARCH="${ARCH:-$(uname -m)}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
APP="$ROOT/dist/MeetBar.app"
CONTENTS="$APP/Contents"
RESOURCES="$CONTENTS/Resources"
ICONSET="$ROOT/.build/AppIcon.iconset"

cd "$ROOT"
rm -rf "$APP" "$ROOT/dist/dmg-root" "$ICONSET"
mkdir -p "$CONTENTS/MacOS" "$RESOURCES" "$ROOT/dist/dmg-root"

if [[ "$ARCH" == "universal" ]]; then
  swift build -c release --product MeetBar --arch arm64
  ARM_BIN_DIR="$(swift build -c release --show-bin-path --arch arm64)"
  swift build -c release --product MeetBar --arch x86_64
  INTEL_BIN_DIR="$(swift build -c release --show-bin-path --arch x86_64)"
  lipo -create "$ARM_BIN_DIR/MeetBar" "$INTEL_BIN_DIR/MeetBar" -output "$CONTENTS/MacOS/MeetBar"
else
  swift build -c release --product MeetBar --arch "$ARCH"
  BIN_DIR="$(swift build -c release --show-bin-path --arch "$ARCH")"
  cp "$BIN_DIR/MeetBar" "$CONTENTS/MacOS/MeetBar"
fi
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS/Info.plist"

swift "$ROOT/scripts/generate-icon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns"

if [[ -n "${GOOGLE_OAUTH_CONFIG:-}" ]]; then
  cp "$GOOGLE_OAUTH_CONFIG" "$RESOURCES/GoogleOAuthConfig.json"
fi

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - --entitlements "$ROOT/Resources/MeetBar.entitlements" "$APP"
else
  codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY" --entitlements "$ROOT/Resources/MeetBar.entitlements" "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"

cp -R "$APP" "$ROOT/dist/dmg-root/MeetBar.app"
ln -s /Applications "$ROOT/dist/dmg-root/Applications"
DMG="$ROOT/dist/MeetBar-$VERSION-$ARCH.dmg"
rm -f "$DMG"
hdiutil create -volname "MeetBar" -srcfolder "$ROOT/dist/dmg-root" -ov -format UDZO "$DMG"
rm -rf "$ROOT/dist/dmg-root"

echo "$DMG"
