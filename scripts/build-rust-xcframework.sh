#!/bin/bash
#
# Build Rust portkiller-ffi as XCFramework for Swift integration
#
# This script:
# 1. Builds Rust for Apple Silicon (aarch64) and Intel (x86_64)
# 2. Generates Swift bindings via uniffi-bindgen
# 3. Creates a universal (fat) static library
# 4. Packages everything as an XCFramework
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RUST_DIR="$PROJECT_ROOT/backend"
FFI_DIR="$RUST_DIR/ffi"
BUILD_DIR="$PROJECT_ROOT/.build/rust"
XCFRAMEWORK_DIR="$PROJECT_ROOT/Frameworks"
SWIFT_BRIDGE_DIR="$PROJECT_ROOT/Sources/RustBridge"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_step() {
    echo -e "${GREEN}==>${NC} $1"
}

echo_warning() {
    echo -e "${YELLOW}Warning:${NC} $1"
}

echo_error() {
    echo -e "${RED}Error:${NC} $1"
}

# Ensure required tools are available
check_requirements() {
    echo_step "Checking requirements..."

    if ! command -v cargo &> /dev/null; then
        echo_error "cargo is not installed. Please install Rust."
        exit 1
    fi

    if ! command -v xcodebuild &> /dev/null; then
        echo_error "xcodebuild is not installed. Please install Xcode Command Line Tools."
        exit 1
    fi

    if ! command -v lipo &> /dev/null; then
        echo_error "lipo is not installed. Please install Xcode Command Line Tools."
        exit 1
    fi
}

# Install Rust targets if missing
install_targets() {
    echo_step "Checking Rust targets..."

    local targets=("aarch64-apple-darwin" "x86_64-apple-darwin")

    for target in "${targets[@]}"; do
        if ! rustup target list --installed | grep -q "$target"; then
            echo_step "Installing Rust target: $target"
            rustup target add "$target"
        fi
    done
}

# Build Rust for a specific target
build_rust() {
    local target=$1
    echo_step "Building Rust for $target..."

    cd "$RUST_DIR"
    cargo build --release --package portkiller-ffi --target "$target"
}

# Generate Swift bindings using uniffi-bindgen
generate_bindings() {
    echo_step "Generating Swift bindings..."

    mkdir -p "$BUILD_DIR/swift"

    cd "$RUST_DIR"

    # Build the uniffi-bindgen binary first
    cargo build --release --package portkiller-ffi --bin uniffi-bindgen

    # Use our bundled uniffi-bindgen to generate Swift bindings
    # We need to use the library path for library mode generation
    ./target/release/uniffi-bindgen generate \
        --library "./target/aarch64-apple-darwin/release/libportkiller_ffi.a" \
        --language swift \
        --out-dir "$BUILD_DIR/swift" 2>/dev/null || {

        # Fallback: generate from UDL directly
        echo_warning "Library mode failed, trying UDL mode..."
        ./target/release/uniffi-bindgen generate \
            "$FFI_DIR/src/lib.udl" \
            --language swift \
            --out-dir "$BUILD_DIR/swift"
    }

    echo_step "Swift bindings generated in: $BUILD_DIR/swift"
    ls -la "$BUILD_DIR/swift/"
}

# Create universal (fat) library
create_universal_lib() {
    echo_step "Creating universal library..."

    mkdir -p "$BUILD_DIR/macos-universal"

    lipo -create \
        "$RUST_DIR/target/aarch64-apple-darwin/release/libportkiller_ffi.a" \
        "$RUST_DIR/target/x86_64-apple-darwin/release/libportkiller_ffi.a" \
        -output "$BUILD_DIR/macos-universal/libportkiller_ffi.a"

    echo_step "Universal library created at: $BUILD_DIR/macos-universal/libportkiller_ffi.a"
}

# Prepare headers for XCFramework
prepare_headers() {
    echo_step "Preparing headers..."

    mkdir -p "$BUILD_DIR/headers"

    # Find and copy the generated header
    local header_file=""
    if [ -f "$BUILD_DIR/swift/portkiller_ffiFFI.h" ]; then
        header_file="$BUILD_DIR/swift/portkiller_ffiFFI.h"
    elif [ -f "$BUILD_DIR/swift/portkiller_ffi.h" ]; then
        header_file="$BUILD_DIR/swift/portkiller_ffi.h"
    else
        # Try to find any .h file
        header_file=$(find "$BUILD_DIR/swift" -name "*.h" -type f | head -1)
    fi

    if [ -z "$header_file" ] || [ ! -f "$header_file" ]; then
        echo_error "Generated header not found!"
        ls -la "$BUILD_DIR/swift/" || true
        exit 1
    fi

    cp "$header_file" "$BUILD_DIR/headers/portkiller_ffiFFI.h"

    # Create module.modulemap (module name must match what UniFFI expects)
    cat > "$BUILD_DIR/headers/module.modulemap" << 'EOF'
module portkiller_ffiFFI {
    header "portkiller_ffiFFI.h"
    export *
}
EOF

    echo_step "Headers prepared in: $BUILD_DIR/headers/"
}

# Create XCFramework
create_xcframework() {
    echo_step "Creating XCFramework..."

    mkdir -p "$XCFRAMEWORK_DIR"

    # Remove existing framework
    rm -rf "$XCFRAMEWORK_DIR/PortKillerCore.xcframework"

    xcodebuild -create-xcframework \
        -library "$BUILD_DIR/macos-universal/libportkiller_ffi.a" \
        -headers "$BUILD_DIR/headers" \
        -output "$XCFRAMEWORK_DIR/PortKillerCore.xcframework"

    echo_step "XCFramework created at: $XCFRAMEWORK_DIR/PortKillerCore.xcframework"
}

# Copy Swift bindings to source directory
copy_swift_bindings() {
    echo_step "Copying Swift bindings..."

    mkdir -p "$SWIFT_BRIDGE_DIR"

    # Find the Swift file
    local swift_file=""
    if [ -f "$BUILD_DIR/swift/portkiller_ffi.swift" ]; then
        swift_file="$BUILD_DIR/swift/portkiller_ffi.swift"
    else
        swift_file=$(find "$BUILD_DIR/swift" -name "*.swift" -type f | head -1)
    fi

    if [ -z "$swift_file" ] || [ ! -f "$swift_file" ]; then
        echo_error "Swift bindings not found!"
        ls -la "$BUILD_DIR/swift/" || true
        exit 1
    fi

    # Post-process for Swift 6 concurrency safety
    echo_step "Post-processing Swift bindings for Swift 6 concurrency..."
    sed -i '' 's/private var initializationResult/nonisolated(unsafe) private var initializationResult/' "$swift_file"

    cp "$swift_file" "$SWIFT_BRIDGE_DIR/portkiller_ffi.swift"
    echo_step "Swift bindings copied to: $SWIFT_BRIDGE_DIR/portkiller_ffi.swift"
}

# Main execution
main() {
    echo "========================================"
    echo "  PortKiller Rust XCFramework Builder  "
    echo "========================================"
    echo ""

    check_requirements
    install_targets

    # Build for both architectures
    build_rust "aarch64-apple-darwin"
    build_rust "x86_64-apple-darwin"

    # Generate bindings
    generate_bindings

    # Create universal library
    create_universal_lib

    # Prepare headers
    prepare_headers

    # Create XCFramework
    create_xcframework

    # Copy Swift bindings
    copy_swift_bindings

    echo ""
    echo "========================================"
    echo -e "${GREEN}Build complete!${NC}"
    echo "========================================"
    echo ""
    echo "XCFramework: $XCFRAMEWORK_DIR/PortKillerCore.xcframework"
    echo "Swift bindings: $SWIFT_BRIDGE_DIR/portkiller_ffi.swift"
    echo ""
}

main "$@"
