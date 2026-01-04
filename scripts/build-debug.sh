#!/bin/bash
set -e

# Build a debug version that can be profiled with Instruments
# This version has get-task-allow entitlement which allows debugger attach

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║           Building PortKiller (Debug/Profile)                    ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# Check for Rust library
if [ ! -f ".build/rust/lib/libportkiller.a" ]; then
    echo "⚠️  Rust library not found. Building..."
    ./scripts/build-rust.sh
fi

# Build debug
echo "🔨 Building debug..."
swift build -c debug

# Create app bundle structure
APP_NAME="PortKiller"
BUILD_DIR=".build/debug"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"

echo "📦 Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$FRAMEWORKS_DIR"

# Copy executable
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/"

# Copy Info.plist
cp "Resources/Info.plist" "$CONTENTS_DIR/"

# Copy resources
if [ -d "Resources/Assets.xcassets" ]; then
    # Compile assets if xcrun is available
    if command -v xcrun &> /dev/null; then
        xcrun actool "Resources/Assets.xcassets" --compile "$RESOURCES_DIR" --platform macosx --minimum-deployment-target 15.0 --app-icon AppIcon --output-partial-info-plist /tmp/assetcatalog_generated_info.plist 2>/dev/null || true
    fi
fi

# Copy SPM resource bundles
for bundle in "$BUILD_DIR"/*.bundle; do
    if [ -d "$bundle" ]; then
        bundle_name=$(basename "$bundle")
        cp -R "$bundle" "$RESOURCES_DIR/$bundle_name"
    fi
done

# Add rpath
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$APP_NAME" 2>/dev/null || true

# Sign with debug entitlements (allows Instruments to attach)
echo "🔏 Signing with debug entitlements..."
codesign --force --sign - --entitlements "Resources/PortKiller.entitlements" "$APP_DIR"

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                    Debug Build Complete!                         ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""
echo "App location: $APP_DIR"
echo ""
echo "To profile with Instruments:"
echo "  1. Open Instruments"
echo "  2. Select 'Allocations' or 'Leaks'"
echo "  3. Target → Launch → Choose Target"
echo "  4. Select: $PROJECT_DIR/$APP_DIR"
echo "  5. Click Record"
echo ""
echo "Or run directly:"
echo "  open $APP_DIR"
