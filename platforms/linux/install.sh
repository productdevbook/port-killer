#!/bin/bash
set -e

# Linux Installer for PortKiller Native Tray App
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.local/share/port-killer"
AUTOSTART_DIR="$HOME/.config/autostart"
APPLICATIONS_DIR="$HOME/.local/share/applications"
ICONS_DIR="$HOME/.local/share/icons/hicolor/scalable/apps"

echo "Installing PortKiller for Linux..."

# Verify runtime dependencies before installing anything
missing=""

if ! command -v python3 >/dev/null 2>&1; then
    missing="$missing python3"
fi

if ! python3 -c "import gi; gi.require_version('Gtk', '3.0')" >/dev/null 2>&1; then
    missing="$missing python3-gi/GTK3"
fi

if ! python3 -c "
import gi
try:
    gi.require_version('AppIndicator3', '0.1')
except ValueError:
    gi.require_version('AyatanaAppIndicator3', '0.1')
" >/dev/null 2>&1; then
    missing="$missing libappindicator3/libayatana-appindicator3"
fi

if [ -n "$missing" ]; then
    echo "Error: missing required dependencies:$missing" >&2
    echo "" >&2
    echo "Install them first, e.g.:" >&2
    echo "  Debian/Ubuntu: sudo apt install python3 python3-gi gir1.2-ayatanaappindicator3-0.1" >&2
    echo "  Fedora:        sudo dnf install python3 python3-gobject libayatana-appindicator-gtk3" >&2
    echo "  Arch:          sudo pacman -S python python-gobject libayatana-appindicator" >&2
    exit 1
fi

# Create install directories
mkdir -p "$INSTALL_DIR"
mkdir -p "$AUTOSTART_DIR"
mkdir -p "$APPLICATIONS_DIR"

# Copy python script and assets
cp -r "$SCRIPT_DIR/src" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/port-killer.py" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/port-killer.py"

# Install the app icon. Never create a placeholder here: get_icon_path() only
# rejects a missing file, so an empty AppIcon.svg would be handed to
# AppIndicator instead of falling back to the system icon.
SOURCE_ICON="$SCRIPT_DIR/../macos/Resources/AppIcon.svg"
ICON_NAME="port-killer"

if [ -s "$SOURCE_ICON" ]; then
    cp "$SOURCE_ICON" "$INSTALL_DIR/AppIcon.svg"

    # Also register in the hicolor theme so the icon resolves by name
    mkdir -p "$ICONS_DIR"
    cp "$SOURCE_ICON" "$ICONS_DIR/$ICON_NAME.svg"
    DESKTOP_ICON="$ICON_NAME"

    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache -q -t -f "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
    fi
else
    echo "Warning: $SOURCE_ICON not found or empty; using a system fallback icon." >&2
    rm -f "$INSTALL_DIR/AppIcon.svg"
    DESKTOP_ICON="utilities-system-monitor"
fi

# Generate desktop file
DESKTOP_FILE="$APPLICATIONS_DIR/port-killer.desktop"
AUTOSTART_FILE="$AUTOSTART_DIR/port-killer.desktop"

# Generate launcher desktop entry
cat <<EOF > "$DESKTOP_FILE"
[Desktop Entry]
Type=Application
Name=PortKiller
Comment=Monitor listening ports and terminate processes from system tray
Exec=$INSTALL_DIR/port-killer.py
Icon=$DESKTOP_ICON
Terminal=false
Categories=Development;
StartupNotify=false
StartupWMClass=port-killer
EOF

# Copy desktop file to autostart so it starts on login
cp "$DESKTOP_FILE" "$AUTOSTART_FILE"
chmod +x "$DESKTOP_FILE"
chmod +x "$AUTOSTART_FILE"

echo "✓ PortKiller installed successfully!"
echo "You can now find PortKiller in your application launcher, or start it immediately by running:"
echo "  $INSTALL_DIR/port-killer.py &"
echo ""
echo "It will also start automatically every time you log in."
