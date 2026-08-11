#!/bin/bash
# Build, sign, notarize, and package Claude Usage into a styled DMG.
#
# Works both locally and in CI. All tunables are environment overridable so the
# same script drives `packaging/build.sh` on a laptop and the GitHub Actions
# release workflow.
#
# Version:
#   VERSION      marketing version, e.g. 1.2.3   (default: parsed from Info.plist)
#   BUILD_NUMBER CFBundleVersion, e.g. 42         (default: 1)
#
# Signing:
#   SIGN_ID      "Developer ID Application: Kwonwoo Lyu (4S9VPFZ465)"
#
# Notarization — three modes, chosen automatically:
#   1. API key   set NOTARY_KEY (path to .p8), NOTARY_KEY_ID, NOTARY_ISSUER
#   2. Keychain  a notarytool profile named "$NOTARY_PROFILE" exists (local default)
#   3. Skipped   neither is available (local unsigned install / PR builds)
#   Force with NOTARIZE=1 / NOTARIZE=0.
set -euo pipefail

# Repo root: portable — two levels up from this script, overridable via ROOT.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

APP_NAME="Claude Usage"
EXEC="ClaudeUsageMonitor"
VOL="Claude Usage"
SIGN_ID="${SIGN_ID:-Developer ID Application: Kwonwoo Lyu (4S9VPFZ465)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-claude-usage}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

PKG="$ROOT/packaging"

# Version: use env, else read from Info.plist.
if [ -z "${VERSION:-}" ]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PKG/Info.plist" 2>/dev/null || echo 1.0.0)"
fi

BUILD="$ROOT/.build/release"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/Claude-Usage-$VERSION.dmg"
DMG_RW="$DIST/rw.dmg"

# Decide notarization mode.
NOTARIZE="${NOTARIZE:-auto}"
NOTARY_ARGS=()
notary_ready() {
  if [ -n "${NOTARY_KEY:-}" ] && [ -n "${NOTARY_KEY_ID:-}" ] && [ -n "${NOTARY_ISSUER:-}" ]; then
    NOTARY_ARGS=(--key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
    return 0
  fi
  if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
    return 0
  fi
  return 1
}
if [ "$NOTARIZE" = "auto" ]; then
  if notary_ready; then NOTARIZE=1; else NOTARIZE=0; fi
elif [ "$NOTARIZE" = "1" ]; then
  notary_ready || { echo "NOTARIZE=1 but no credentials found"; exit 1; }
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

  # Finder styling needs a UI session + automation permission. It works locally
  # and is skipped gracefully on headless CI runners (DMG stays functional).
  echo "==> Styling DMG window (background + icon layout)"
  osascript <<EOF || echo "   (Finder styling skipped — headless runner or automation permission needed)"
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

echo "==> Building Claude Usage $VERSION (build $BUILD_NUMBER, notarize=$NOTARIZE)"

echo "==> Compiling (release)"
swift build -c release --package-path "$ROOT"

echo "==> Assembling app bundle (+ icon)"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/$EXEC" "$APP/Contents/MacOS/$EXEC"
cp "$PKG/Info.plist" "$APP/Contents/Info.plist"
cp "$PKG/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "==> Stamping version $VERSION ($BUILD_NUMBER)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

echo "==> Signing app (Developer ID, hardened runtime)"
codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
codesign --verify --strict "$APP"

if [ "$NOTARIZE" = "1" ]; then
  echo "==> Notarizing app (this can take a few minutes)"
  ditto -c -k --keepParent "$APP" "$DIST/app.zip"
  xcrun notarytool submit "$DIST/app.zip" "${NOTARY_ARGS[@]}" --wait
  rm -f "$DIST/app.zip"
  echo "==> Stapling app"
  xcrun stapler staple "$APP"
else
  echo "==> (skipping notarization — no credentials; local install only)"
fi

build_dmg

if [ "$NOTARIZE" = "1" ]; then
  echo "==> Notarizing DMG"
  xcrun notarytool submit "$DMG" "${NOTARY_ARGS[@]}" --wait
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
