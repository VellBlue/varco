#!/bin/zsh
# Builds Varco.app from source: SwiftUI app + bundled varco command + colors and icon.
# usage: scripts/build-app.sh [--install]     (--install copies the app to ~/Applications)
set -e
REPO="${0:A:h:h}"; OUT="$REPO/build.noindex"; APP="$OUT/Varco.app"; REL="${VARCO_RELEASE_DIR:-$REPO/../varco-release}"
DEV="${DEVELOPER_DIR:-$(ls -d /Applications/Xcode*.app 2>/dev/null | head -1)/Contents/Developer}"

# The checksums of the published packages are in VarcoRelease (app/Sources/Varco.swift): if ../varco-release
# has packages with different checksums, warn (VarcoRelease must be updated before publishing)
for f in "$REL"/varco-*.tar.xz.sha256(N); do
  sum="$(cut -d' ' -f1 "$f")"
  grep -q "$sum" "$REPO/app/Sources/Varco.swift" || echo "Warning: ${f:t:r} has a checksum different from the one in VarcoRelease" >&2
done

rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/cli"
echo "Building the app..."
swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macosx15.0 "$REPO/app/Sources/Varco.swift" -o "$APP/Contents/MacOS/Varco"

echo "Resources..."
cp "$REPO/app/Resources/AppIcon.icns" "$APP/Contents/Resources/"
# accent color (Assets.car): needs actool, which only ships with Xcode; without it the app still uses its color
if DEVELOPER_DIR="$DEV" xcrun --find actool >/dev/null 2>&1; then
  DEVELOPER_DIR="$DEV" xcrun actool "$REPO/app/Resources/Assets.xcassets" --compile "$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 15.0 --accent-color AccentColor \
    --output-partial-info-plist "$OUT/assets.plist" >/dev/null
else
  echo "actool not found (needs Xcode): skipping Assets.car" >&2
fi
echo "varco-tool..."
swiftc -O -swift-version 5 -target arm64-apple-macosx15.0 "$REPO/cli/tools/varco-tool.swift" -o "$REPO/cli/tools/varco-tool"
cp -R "$REPO/cli/" "$APP/Contents/Resources/cli/"
rm -f "$APP/Contents/Resources/cli/tools/"*.swift
chmod +x "$APP/Contents/Resources/cli/varco"
BUILD="$(git -C "$REPO" rev-list --count HEAD 2>/dev/null || echo 1)"   # build number: how many commits
APPVER="$(sed -n 's/.*static let appVersion = "\(.*\)".*/\1/p' "$REPO/app/Sources/Varco.swift")"   # VarcoRelease.appVersion
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Varco</string>
<key>CFBundleDisplayName</key><string>Varco</string>
<key>CFBundleIdentifier</key><string>io.github.vellblue.varco</string>
<key>CFBundleExecutable</key><string>Varco</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>${APPVER}</string>
<key>CFBundleVersion</key><string>${BUILD}</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.games</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAccentColorName</key><string>AccentColor</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>it</string></array>
</dict></plist>
PLIST

# signing: Developer ID if given (VARCO_SIGN_ID="Developer ID Application: ..."), otherwise ad-hoc
# (varco-tool lives in Resources, where --deep doesn't reach: it is signed on its own, before the app)
TOOL="$APP/Contents/Resources/cli/tools/varco-tool"
if [[ -n "$VARCO_SIGN_ID" ]]; then
  codesign --force --options runtime --timestamp -s "$VARCO_SIGN_ID" "$TOOL"
  codesign --force --deep --options runtime --timestamp -s "$VARCO_SIGN_ID" "$APP"
else
  codesign --force -s - "$TOOL"
  codesign --force --deep -s - "$APP"
fi
echo "Ready: $APP"

if [[ "$1" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  osascript -e 'tell application "Varco" to quit' >/dev/null 2>&1 || true
  rm -rf "$HOME/Applications/Varco.app"; ditto "$APP" "$HOME/Applications/Varco.app"
  echo "Installed in ~/Applications/Varco.app"
fi
