#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
APP="$ROOT/build/PortKiller.app"
PLIST="$APP/Contents/Info.plist"

swift build --package-path "$ROOT" -c "$CONFIGURATION" --product PortKiller
BIN="$(swift build --package-path "$ROOT" -c "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/PortKiller" "$APP/Contents/MacOS/PortKiller"
cp "$ROOT/Resources/Info.plist" "$PLIST"
cp "$ROOT/Resources/ToolbarIcon.png" "$ROOT/Resources/ToolbarIcon@2x.png" "$APP/Contents/Resources/"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
if [[ -n "${VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION#v}" "$PLIST"
fi

# actool crashes on some CI images; the prebuilt .icns keeps the bundle usable when it does.
if ! xcrun actool "$ROOT/Resources/AppIcon.icon" \
    --compile "$APP/Contents/Resources" \
    --app-icon AppIcon \
    --platform macosx \
    --target-device mac \
    --minimum-deployment-target 27.0 \
    --include-all-app-icons \
    --output-partial-info-plist "$(mktemp -t PortKillerIcon)" >/dev/null 2>&1; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"

for rpath in $(otool -l "$APP/Contents/MacOS/PortKiller" | awk '/LC_RPATH/ { getline; getline; print $2 }'); do
    [[ "$rpath" == /* ]] && install_name_tool -delete_rpath "$rpath" "$APP/Contents/MacOS/PortKiller"
done
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/PortKiller"

codesign --force --deep --sign "${SIGN_IDENTITY:--}" "$APP" >/dev/null
echo "$APP"
