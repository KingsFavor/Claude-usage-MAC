#!/bin/bash
# Build, sign, (optionally notarize), and package Claude Usage into a styled DMG.
#
# Notarization runs automatically when a notarytool keychain profile named
# "claude-usage" exists. Create it once (secrets never touch this repo):
#   xcrun notarytool store-credentials claude-usage \
#     --apple-id "<APPLE_ID>" --team-id 4S9VPFZ465
# Force on/off with NOTARIZE=1 / NOTARIZE=0.
set -euo pipefail

ROOT="/Users/kingsfavor/Documents/projects/playground/claude-usage"
APP_NAME="Claude Usage"
EXEC="ClaudeUsageMonitor"
VOL="Claude Usage"
VERSION="1.0.0"
SIGN_ID="Developer ID Application: Kwonwoo Lyu (4S9VPFZ465)"
NOTARY_PROFILE="claude-usage"

BUILD="$ROOT/.build/release"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/Claude-Usage-$VERSION.dmg"
DMG_RW="$DIST/rw.dmg"
PKG="$ROOT/packaging"

# Decide whether to notarize.
NOTARIZE="${NOTARIZE:-auto}"
if [ "$NOTARIZE" = "auto" ]; then
  if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    NOTARIZE=1
  else
    NOTARIZE=0
  fi
fi

build_dmg() {
  echo "==> Creating writable DMG"
  for d in $(hdiutil info | awk -v v="$VOL" 'index($0,v){print prev} {prev=$1}' | grep '^/dev/disk'); do
    hdiutil detach "$d" -force >/dev/null 2>&1 || true
  done
  rm -f "$DMG_RW" "$DMG"
  hdiutil create -srcfolder "$APP" -volname "$VOL" -fs HFS+ \
    -format UDRW -size 150m "$DMG_RW" >/dev/null
  local ATTACH DEV VOLPATH VOLNAME
  ATTACH=$(hdiutil attach "$DMG_RW" -nobrowse -noverify -noautoopen)
  DEV=$(echo "$ATTACH" | egrep '^/dev/' | head -1 | awk '{print $1}')
  VOLPATH=$(echo "$ATTACH" | grep -o '/Volumes/.*' | head -1)
  VOLNAME=$(basename "$VOLPATH")
  sleep 1
  mkdir -p "$VOLPATH/.background"
  cp "$PKG/background.tiff" "$VOLPATH/.background/background.tiff"
  ln -s /Applications "$VOLPATH/Applications"

  echo "==> Styling DMG window (background + icon layout)"
  osascript <<EOF || echo "   (Finder styling skipped — automation permission may be needed)"
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {300, 140, 960, 560}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 104
    set text size of opts to 12
    set background picture of opts to file ".background:background.tiff"
    set position of item "$APP_NAME.app" of container window to {175, 215}
    set position of item "Applications" of container window to {485, 215}
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF
  sync
  hdiutil detach "$DEV" >/dev/null || hdiutil detach "$DEV" -force >/dev/null
  hdiutil convert "$DMG_RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
  rm -f "$DMG_RW"
  codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
}

echo "==> Compiling (release)"
swift build -c release --package-path "$ROOT"

echo "==> Assembling app bundle (+ icon)"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/$EXEC" "$APP/Contents/MacOS/$EXEC"
cp "$PKG/Info.plist" "$APP/Contents/Info.plist"
cp "$PKG/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing app (Developer ID, hardened runtime)"
codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
codesign --verify --strict "$APP"

if [ "$NOTARIZE" = "1" ]; then
  echo "==> Notarizing app (this can take a few minutes)"
  ditto -c -k --keepParent "$APP" "$DIST/app.zip"
  xcrun notarytool submit "$DIST/app.zip" --keychain-profile "$NOTARY_PROFILE" --wait
  rm -f "$DIST/app.zip"
  echo "==> Stapling app"
  xcrun stapler staple "$APP"
else
  echo "==> (skipping notarization — no '$NOTARY_PROFILE' profile; local install only)"
fi

build_dmg

if [ "$NOTARIZE" = "1" ]; then
  echo "==> Notarizing DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "==> Stapling DMG"
  xcrun stapler staple "$DMG"
fi

xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
xattr -dr com.apple.quarantine "$DMG" 2>/dev/null || true

echo ""
echo "DONE  (notarized=$NOTARIZE)"
echo "  App: $APP"
echo "  DMG: $DMG"
if [ "$NOTARIZE" = "1" ]; then
  echo "--- gatekeeper assessment ---"
  spctl --assess --type execute --verbose=2 "$APP" 2>&1 || true
  xcrun stapler validate "$APP" 2>&1 | tail -1 || true
fi
