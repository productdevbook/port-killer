#!/bin/bash
set -e

# Build Rust libraries for macOS and create XCFramework
# Usage: ./scripts/build-rust.sh [release|debug]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RUST_CORE_DIR="$PROJECT_DIR/portkiller-core"
RUST_FFI_DIR="$PROJECT_DIR/portkiller-ffi"
OUTPUT_DIR="$PROJECT_DIR/.build/rust"

BUILD_TYPE="${1:-release}"
PROFILE="release"
CARGO_FLAGS="--release"

if [ "$BUILD_TYPE" = "debug" ]; then
    PROFILE="debug"
    CARGO_FLAGS=""
fi

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║           Building PortKiller Rust Libraries                      ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""
echo "Build type: $BUILD_TYPE"
echo "Output dir: $OUTPUT_DIR"
echo ""

# Clean output directory
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/lib"
mkdir -p "$OUTPUT_DIR/include"

# ============================================================================
# Build for macOS (Apple Silicon)
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Building for aarch64-apple-darwin (Apple Silicon)..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd "$RUST_FFI_DIR"
cargo build $CARGO_FLAGS --target aarch64-apple-darwin

AARCH64_LIB="$RUST_FFI_DIR/target/aarch64-apple-darwin/$PROFILE/libportkiller.a"

if [ ! -f "$AARCH64_LIB" ]; then
    echo "Error: Failed to build aarch64-apple-darwin library"
    exit 1
fi

echo "✓ Built: $AARCH64_LIB"

# ============================================================================
# Build for macOS (Intel)
# ============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Building for x86_64-apple-darwin (Intel)..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cargo build $CARGO_FLAGS --target x86_64-apple-darwin

X86_64_LIB="$RUST_FFI_DIR/target/x86_64-apple-darwin/$PROFILE/libportkiller.a"

if [ ! -f "$X86_64_LIB" ]; then
    echo "Error: Failed to build x86_64-apple-darwin library"
    exit 1
fi

echo "✓ Built: $X86_64_LIB"

# ============================================================================
# Create Universal Binary (Fat Library)
# ============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Creating universal binary..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

UNIVERSAL_LIB="$OUTPUT_DIR/lib/libportkiller.a"

lipo -create \
    "$AARCH64_LIB" \
    "$X86_64_LIB" \
    -output "$UNIVERSAL_LIB"

echo "✓ Created universal library: $UNIVERSAL_LIB"

# Verify architectures
echo ""
echo "Library architectures:"
lipo -info "$UNIVERSAL_LIB"

# ============================================================================
# Copy headers
# ============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Copying headers..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cp "$RUST_FFI_DIR/include/portkiller.h" "$OUTPUT_DIR/include/"
cp "$RUST_FFI_DIR/include/module.modulemap" "$OUTPUT_DIR/include/"

echo "✓ Copied headers to $OUTPUT_DIR/include/"

# ============================================================================
# Create XCFramework
# ============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Creating XCFramework..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

XCFRAMEWORK_DIR="$OUTPUT_DIR/PortKillerFFI.xcframework"
rm -rf "$XCFRAMEWORK_DIR"

xcodebuild -create-xcframework \
    -library "$UNIVERSAL_LIB" \
    -headers "$OUTPUT_DIR/include" \
    -output "$XCFRAMEWORK_DIR"

echo "✓ Created XCFramework: $XCFRAMEWORK_DIR"

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                      Build Complete!                              ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""
echo "Output files:"
echo "  • Universal library: $UNIVERSAL_LIB"
echo "  • XCFramework:       $XCFRAMEWORK_DIR"
echo "  • Headers:           $OUTPUT_DIR/include/"
echo ""
echo "To use in your Swift project:"
echo "  1. Add PortKillerFFI.xcframework to your target"
echo "  2. Or link libportkiller.a and set header search paths"
echo ""
echo "Library size:"
ls -lh "$UNIVERSAL_LIB" | awk '{print "  " $5}'
