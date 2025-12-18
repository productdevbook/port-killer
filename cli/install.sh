#!/bin/sh
set -e

# portkiller CLI installer
# Usage: curl -fsSL https://raw.githubusercontent.com/productdevbook/port-killer/main/cli/install.sh | sh

REPO="productdevbook/port-killer"
BINARY_NAME="portkiller"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1"
}

error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1"
    exit 1
}

# Detect OS
detect_os() {
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    case "$OS" in
        darwin) OS="darwin" ;;
        linux) OS="linux" ;;
        mingw*|msys*|cygwin*) OS="windows" ;;
        *) error "Unsupported OS: $OS" ;;
    esac
}

# Detect architecture
detect_arch() {
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        *) error "Unsupported architecture: $ARCH" ;;
    esac
}

# Get latest version from GitHub
get_latest_version() {
    LATEST=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases" | \
        grep -o '"tag_name": "cli-v[^"]*"' | \
        head -1 | \
        sed 's/"tag_name": "//;s/"//')

    if [ -z "$LATEST" ]; then
        error "Failed to get latest version"
    fi

    echo "$LATEST"
}

# Download and install
install() {
    detect_os
    detect_arch

    info "Detected OS: $OS, Arch: $ARCH"

    VERSION=$(get_latest_version)
    info "Latest version: $VERSION"

    if [ "$OS" = "windows" ]; then
        FILENAME="${BINARY_NAME}-${OS}-${ARCH}.zip"
    else
        FILENAME="${BINARY_NAME}-${OS}-${ARCH}.tar.gz"
    fi

    URL="https://github.com/${REPO}/releases/download/${VERSION}/${FILENAME}"
    info "Downloading from: $URL"

    TMP_DIR=$(mktemp -d)
    trap "rm -rf $TMP_DIR" EXIT

    cd "$TMP_DIR"

    if ! curl -fsSL -o "$FILENAME" "$URL"; then
        error "Failed to download $URL"
    fi

    info "Extracting..."
    if [ "$OS" = "windows" ]; then
        unzip -q "$FILENAME"
    else
        tar -xzf "$FILENAME"
    fi

    # Find the binary
    BINARY=$(find . -name "${BINARY_NAME}*" -type f ! -name "*.tar.gz" ! -name "*.zip" | head -1)

    if [ -z "$BINARY" ]; then
        error "Binary not found in archive"
    fi

    chmod +x "$BINARY"

    # Install
    if [ -w "$INSTALL_DIR" ]; then
        mv "$BINARY" "${INSTALL_DIR}/${BINARY_NAME}"
    else
        info "Need sudo to install to $INSTALL_DIR"
        sudo mv "$BINARY" "${INSTALL_DIR}/${BINARY_NAME}"
    fi

    info "Installed ${BINARY_NAME} to ${INSTALL_DIR}/${BINARY_NAME}"

    # Verify installation
    if command -v "$BINARY_NAME" >/dev/null 2>&1; then
        info "Installation successful!"
        "$BINARY_NAME" --version
    else
        warn "Installation complete, but $BINARY_NAME not found in PATH"
        warn "You may need to add $INSTALL_DIR to your PATH"
    fi
}

install
