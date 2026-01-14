#!/bin/bash

# Build script for PortKiller.app (Universal Binary)
set -e

APP_NAME="PortKiller"
BUNDLE_ID="com.portkiller.app"

# Swift PM Universal Build Output Directory
# When building for multiple architectures, SPM puts products in apple/Products/Release
BUILD_DIR=".build/apple/Products/Release"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# First build to fetch dependencies
echo "🔨 Building release binary (fetching dependencies)..."
swift build -c release --arch arm64 --arch x86_64

# Patch the CHECKOUT source files directly (not DerivedSources which gets regenerated)
# This patches the actual library code before the final build
echo "🔧 Patching library source files for macOS app bundle compatibility..."

# Create a helper file that will be included to fix Bundle.module
BUNDLE_FIX_CODE='
// Patched Bundle.module accessor for macOS app bundles
// This extension takes precedence over SPM-generated one due to same-module compilation
private func findResourceBundle(named bundleName: String) -> Bundle? {
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

    return nil
}
'

# Patch KeyboardShortcuts - add resourceURL check to its Utilities.swift
KS_UTILS=".build/checkouts/KeyboardShortcuts/Sources/KeyboardShortcuts/Utilities.swift"
if [ -f "$KS_UTILS" ] && ! grep -q "resourceURL" "$KS_UTILS"; then
    echo "  → Patching KeyboardShortcuts/Utilities.swift"
    # Make file writable
    chmod +w "$KS_UTILS"
    # Add the fix at the beginning of the file
    cat > /tmp/ks_patch.swift << 'PATCH_EOF'
import Foundation

// PATCHED: Fix Bundle.module for macOS app bundles
// SPM's generated accessor doesn't check Contents/Resources
extension Foundation.Bundle {
    static var modulePatched: Bundle {
        let bundleName = "KeyboardShortcuts_KeyboardShortcuts"

        // For macOS app bundles: check Contents/Resources first
        if let resourceURL = Bundle.main.resourceURL {
            let bundlePath = resourceURL.appendingPathComponent("\(bundleName).bundle").path
            if let bundle = Bundle(path: bundlePath) {
                return bundle
            }
        }

        // Fallback: check app root
        let mainPath = Bundle.main.bundleURL.appendingPathComponent("\(bundleName).bundle").path
        if let bundle = Bundle(path: mainPath) {
            return bundle
        }

        // Development: use SPM's generated accessor as last resort
        return module
    }
}

// Patch String.localized to use modulePatched
extension String {
    var localizedPatched: String {
        NSLocalizedString(self, bundle: .modulePatched, comment: self)
    }
}

PATCH_EOF
    # Prepend patch to the file
    cat /tmp/ks_patch.swift "$KS_UTILS" > /tmp/ks_utils_patched.swift
    cp /tmp/ks_utils_patched.swift "$KS_UTILS"

    # Replace ".localized" (as property, not part of localizedStringWithFormat) with .localizedPatched
    KS_RECORDER=".build/checkouts/KeyboardShortcuts/Sources/KeyboardShortcuts/RecorderCocoa.swift"
    if [ -f "$KS_RECORDER" ]; then
        echo "  → Patching KeyboardShortcuts/RecorderCocoa.swift"
        chmod +w "$KS_RECORDER"
        # Only replace .localized when followed by non-word char (not localizedStringWithFormat)
        sed -i '' 's/\.localized\([^A-Za-z]\)/.localizedPatched\1/g' "$KS_RECORDER"
        # Also handle .localized at end of line
        sed -i '' 's/\.localized$/.localizedPatched/g' "$KS_RECORDER"
    fi
fi

# Also patch any other files that use .localized in KeyboardShortcuts
for ks_file in .build/checkouts/KeyboardShortcuts/Sources/KeyboardShortcuts/*.swift; do
    if [ -f "$ks_file" ] && grep -q '".*"\.localized' "$ks_file" && ! grep -q 'localizedPatched' "$ks_file"; then
        echo "  → Patching $(basename "$ks_file")"
        chmod +w "$ks_file"
        sed -i '' 's/\.localized\([^A-Za-z]\)/.localizedPatched\1/g' "$ks_file"
        sed -i '' 's/\.localized$/.localizedPatched/g' "$ks_file"
    fi
done

# Touch patched files to ensure SPM sees them as modified
echo "🔄 Updating timestamps on patched files..."
touch .build/checkouts/KeyboardShortcuts/Sources/KeyboardShortcuts/*.swift 2>/dev/null || true

# Remove compiled KeyboardShortcuts objects and executable to force recompilation
echo "🧹 Forcing recompilation..."
rm -f .build/*/release/KeyboardShortcuts.build/*.o 2>/dev/null || true
rm -f .build/*/release/PortKiller
rm -rf .build/*/release/*.bundle

echo "🔨 Building release binary with patched sources..."
swift build -c release --arch arm64 --arch x86_64

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

# Generate icons from AppIcon.icon using actool (Xcode 26+)
if [ -d "Resources/AppIcon.icon" ]; then
    echo "🎨 Compiling AppIcon.icon with actool..."

    # Use actool to compile .icon folder - generates both Assets.car and fallback .icns
    # Wrap in conditional to handle CI crashes (common with Xcode 26+ on some GHA runners)
    if xcrun actool "Resources/AppIcon.icon" \
        --compile "$RESOURCES_DIR" \
        --app-icon AppIcon \
        --target-device mac \
        --platform macosx \
        --minimum-deployment-target 15.0 \
        --include-all-app-icons \
        --output-partial-info-plist /tmp/icon-info.plist 2>/dev/null; then
        echo "  ✅ Generated AppIcon.icns and Assets.car"
    else
        echo "  ⚠️ Warning: actool failed (likely CI/Environment issue)."
        # Fallback: use pre-generated static .icns file
        if [ -f "Resources/AppIcon.icns" ]; then
            echo "  → Using static AppIcon.icns as fallback"
            cp "Resources/AppIcon.icns" "$RESOURCES_DIR/"
        else
            echo "  ❌ Error: No AppIcon.icns fallback available."
            exit 1
        fi
    fi
elif [ -f "Resources/AppIcon.icns" ]; then
    # Fallback: copy static .icns if .icon folder doesn't exist
    echo "  → Copying static AppIcon.icns (legacy fallback)"
    cp "Resources/AppIcon.icns" "$RESOURCES_DIR/"
fi

# Copy all SPM resource bundles to Contents/Resources (use ditto to preserve symlinks)
for bundle in "$BUILD_DIR"/*.bundle; do
    if [ -d "$bundle" ]; then
        bundle_name=$(basename "$bundle")
        echo "  → Copying $bundle_name"
        ditto "$bundle" "$RESOURCES_DIR/$bundle_name"
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

# Verify patched accessor is in binary (checks for resourceURL which is only in patched version)
echo "🔍 Verifying patched accessor..."
if strings "$MACOS_DIR/$APP_NAME" | grep -q "resourceURL"; then
    echo "  ✅ Patched accessor verified in binary"
else
    echo "  ❌ ERROR: Accessor not patched correctly! Binary still uses original SPM accessor."
    echo "  The app will crash when trying to load resource bundles."
    exit 1
fi

# Verify required bundles exist
echo "🔍 Verifying resource bundles..."
MISSING_BUNDLES=0
for bundle in KeyboardShortcuts_KeyboardShortcuts Defaults_Defaults; do
    if [ -d "$RESOURCES_DIR/${bundle}.bundle" ]; then
        echo "  ✅ ${bundle}.bundle"
    else
        echo "  ❌ Missing: ${bundle}.bundle"
        MISSING_BUNDLES=1
    fi
done
if [ $MISSING_BUNDLES -eq 1 ]; then
    echo "  ERROR: Some resource bundles are missing!"
    exit 1
fi

echo "🔏 Signing app bundle..."
codesign --force --deep --sign - "$APP_DIR"

echo "✅ App bundle created at: $APP_DIR"
echo ""
echo "To install, run:"
echo "  cp -r $APP_DIR /Applications/"
echo ""
echo "Or open directly:"
echo "  open $APP_DIR"
