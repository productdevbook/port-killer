#!/bin/bash
set -e

# Linux Installer for PortKiller Native Tray App
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.local/share/port-killer"
AUTOSTART_DIR="$HOME/.config/autostart"
APPLICATIONS_DIR="$HOME/.local/share/applications"

echo "Installing PortKiller for Linux..."

# Create install directories
mkdir -p "$INSTALL_DIR"
mkdir -p "$AUTOSTART_DIR"
mkdir -p "$APPLICATIONS_DIR"

# Copy python script and assets
cp "$SCRIPT_DIR/port-killer.py" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/port-killer.py"

# Try to find AppIcon.svg
if [ -f "$SCRIPT_DIR/../../Resources/AppIcon.svg" ]; then
    cp "$SCRIPT_DIR/../../Resources/AppIcon.svg" "$INSTALL_DIR/AppIcon.svg"
else
    # Fallback to creating a dummy or copying if path is different
    touch "$INSTALL_DIR/AppIcon.svg"
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
Icon=$INSTALL_DIR/AppIcon.svg
Terminal=false
Categories=Development;Utility;
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
