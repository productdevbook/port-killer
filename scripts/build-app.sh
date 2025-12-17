#!/bin/bash

# Build script for PortKiller.app
set -e

APP_NAME="PortKiller"
BUNDLE_ID="com.portkiller.app"
BUILD_DIR=".build/release"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "🔨 Building release binary (first pass)..."
swift build -c release

# Patch SPM resource bundle accessors to check resourceURL (Contents/Resources) first
# SPM generates accessors that only check bundleURL (app root), but macOS apps use Contents/Resources
echo "🔧 Patching resource bundle accessors..."
for accessor in .build/*/release/*.build/DerivedSources/resource_bundle_accessor.swift; do
    if [ -f "$accessor" ]; then
        # Check if already patched
        if ! grep -q "resourceURL" "$accessor"; then
            # Extract target name from path (e.g., KeyboardShortcuts from KeyboardShortcuts.build)
            target_name=$(basename "$(dirname "$(dirname "$accessor")")" .build)

            # SPM bundle naming convention: PackageName_TargetName.bundle
            # For most packages, package name = target name, so it's TargetName_TargetName
            bundle_name="${target_name}_${target_name}"
            echo "  → Patching $target_name (bundle: $bundle_name)"

            # Replace the simple accessor with one that checks resourceURL first
            cat > "$accessor" << 'ACCESSOR_EOF'
import Foundation

extension Foundation.Bundle {
    static let module: Bundle = {
        let bundleName = "BUNDLE_NAME_PLACEHOLDER"

        // For macOS app bundles: check Contents/Resources first
        if let resourceURL = Bundle.main.resourceURL {
            let bundlePath = resourceURL.appendingPathComponent("\(bundleName).bundle").path
            if let bundle = Bundle(path: bundlePath) {
                return bundle
            }
        }

        // Fallback: check app root (Bundle.main.bundleURL)
        let mainPath = Bundle.main.bundleURL.appendingPathComponent("\(bundleName).bundle").path
        if let bundle = Bundle(path: mainPath) {
            return bundle
        }

        // Development fallback: check build directory
        #if DEBUG
        let buildPath = Bundle.main.bundleURL.appendingPathComponent("\(bundleName).bundle").path
        if let bundle = Bundle(path: buildPath) {
            return bundle
        }
        #endif

        Swift.fatalError("could not load resource bundle: \(bundleName)")
    }()
}
ACCESSOR_EOF
            # Replace placeholder with actual bundle name
            sed -i '' "s/BUNDLE_NAME_PLACEHOLDER/${bundle_name}/" "$accessor"

            # Force recompilation by removing compiled object files
            module_build_dir=$(dirname "$(dirname "$accessor")")
            echo "  → Forcing recompilation of $target_name"
            rm -f "$module_build_dir"/*.o 2>/dev/null || true
            rm -f "$module_build_dir"/*.swiftmodule 2>/dev/null || true
        fi
    fi
done

echo "🔨 Building release binary (second pass with patched accessors)..."
swift build -c release

echo "📦 Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$CONTENTS_DIR/Frameworks"

echo "📋 Copying files..."
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/"
cp "Resources/Info.plist" "$CONTENTS_DIR/"

# Debug: List contents of build directory
echo "📂 Contents of $BUILD_DIR:"
ls -la "$BUILD_DIR/" | grep -E "\.bundle$|^total" || echo "  (no bundles found)"

# Copy icon if exists
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$RESOURCES_DIR/"
fi

# Copy all SPM resource bundles to Contents/Resources
for bundle in "$BUILD_DIR"/*.bundle; do
    if [ -d "$bundle" ]; then
        bundle_name=$(basename "$bundle")
        echo "  → Copying $bundle_name"
        cp -r "$bundle" "$RESOURCES_DIR/"
    fi
done

# Download and copy Sparkle framework from official release (preserves symlinks)
SPARKLE_VERSION="2.8.1"
SPARKLE_CACHE="/tmp/Sparkle-${SPARKLE_VERSION}"

if [ ! -d "$SPARKLE_CACHE/Sparkle.framework" ]; then
    echo "📥 Downloading Sparkle ${SPARKLE_VERSION}..."
    curl -L -o /tmp/Sparkle.tar.xz "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
    mkdir -p "$SPARKLE_CACHE"
    tar -xf /tmp/Sparkle.tar.xz -C "$SPARKLE_CACHE"
    rm /tmp/Sparkle.tar.xz
fi

echo "📦 Copying Sparkle.framework..."
ditto "$SPARKLE_CACHE/Sparkle.framework" "$CONTENTS_DIR/Frameworks/Sparkle.framework"

# Remove XPC services (not needed for non-sandboxed apps, saves ~500KB)
echo "🗑️ Removing unnecessary XPC services..."
rm -rf "$CONTENTS_DIR/Frameworks/Sparkle.framework/Versions/B/XPCServices"
rm -f "$CONTENTS_DIR/Frameworks/Sparkle.framework/XPCServices"

# Add rpath so executable can find the framework
echo "🔗 Setting up framework path..."
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$APP_NAME" 2>/dev/null || true

# Verify bundles were copied
echo "📂 Contents of $RESOURCES_DIR:"
ls -la "$RESOURCES_DIR/"

echo "🔏 Signing app bundle..."
codesign --force --deep --sign - "$APP_DIR"

echo "✅ App bundle created at: $APP_DIR"
echo ""
echo "To install, run:"
echo "  cp -r $APP_DIR /Applications/"
echo ""
echo "Or open directly:"
echo "  open $APP_DIR"
