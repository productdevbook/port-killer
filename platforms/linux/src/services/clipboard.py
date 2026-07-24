import shutil
import subprocess

import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk

def copy_to_clipboard(text):
    try:
        clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)
        clipboard.set_text(text, -1)
        return True
    except Exception as e:
        print(f"Error copying to clipboard: {e}")
        return False


# Resolved once: warn at startup rather than failing silently on every action.
_NOTIFY_SEND = shutil.which("notify-send")
if not _NOTIFY_SEND:
    print(
        "Warning: notify-send not found; desktop notifications are disabled. "
        "Install libnotify-bin (Debian/Ubuntu) or libnotify (Fedora/Arch)."
    )


def notify(title, message):
    """
    Show a desktop notification. Runs without blocking the GTK main loop.
    """
    if not _NOTIFY_SEND:
        return False
    try:
        subprocess.Popen(
            [_NOTIFY_SEND, "-a", "PortKiller", title, message],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return True
    except OSError as e:
        print(f"Error sending notification: {e}")
        return False
