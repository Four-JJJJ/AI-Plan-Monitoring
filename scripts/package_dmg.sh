#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AIBalanceMonitor"
BIN_PATH="$ROOT_DIR/.build/arm64-apple-macosx/release/$APP_NAME"
DIST_DIR="$ROOT_DIR/dist"
TMP_ROOT="$(mktemp -d /tmp/aibm_pkg.XXXXXX)"
APP_DIR="$TMP_ROOT/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RES_DIR="$CONTENTS_DIR/Resources"
DMG_STAGING="$TMP_ROOT/dmg-root"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"

# Always build fresh release before packaging to avoid stale DMG content.
echo "Building release binary..."
swift build -c release

if [[ ! -x "$BIN_PATH" ]]; then
  echo "Release binary not found at: $BIN_PATH"
  exit 1
fi

mkdir -p "$DIST_DIR"
rm -rf "$DIST_DIR/$APP_NAME.app" "$DIST_DIR/dmg-root" "$DMG_PATH"
mkdir -p "$MACOS_DIR" "$RES_DIR" "$DMG_STAGING"

cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>AIBalanceMonitor</string>
  <key>CFBundleExecutable</key>
  <string>AIBalanceMonitor</string>
  <key>CFBundleIdentifier</key>
  <string>com.fourj.aibalancemonitor</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>AIBalanceMonitor</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

# Remove filesystem metadata that can invalidate app bundles (e.g. FinderInfo).
if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$APP_DIR" >/dev/null 2>&1 || true
fi

# Ad-hoc sign for local distribution consistency.
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - --timestamp=none "$APP_DIR" >/dev/null
  codesign --verify --deep --strict --verbose=2 "$APP_DIR" >/dev/null
fi

cp -R "$APP_DIR" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo "DMG: $DMG_PATH"
echo "TMP_APP: $APP_DIR"
