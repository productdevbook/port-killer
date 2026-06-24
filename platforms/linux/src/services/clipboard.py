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
