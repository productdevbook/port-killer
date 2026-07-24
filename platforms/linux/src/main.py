import os
import sys
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk, GLib

def main():
    # Set application details for desktop integration (so taskbar/dock maps correctly)
    GLib.set_prgname('port-killer')
    GLib.set_application_name('PortKiller')

    # Load custom stylesheet
    script_dir = os.path.dirname(os.path.abspath(__file__))
    css_path = os.path.join(script_dir, "ui", "styles.css")
    
    if os.path.exists(css_path):
        css_provider = Gtk.CssProvider()
        try:
            css_provider.load_from_path(css_path)
            screen = Gdk.Screen.get_default()
            Gtk.StyleContext.add_provider_for_screen(
                screen, 
                css_provider, 
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            )
        except Exception as e:
            print(f"Warning: Could not load CSS styles: {e}")

    # Set default window icon globally
    from .config import get_icon_path
    icon_path = get_icon_path()
    if icon_path:
        try:
            Gtk.Window.set_default_icon_from_file(icon_path)
        except Exception as e:
            print(f"Warning: Could not set default window icon: {e}")

    # Import and start the tray app
    from .ui.tray import PortKillerTrayApp
    app = PortKillerTrayApp()
    
    # Run Gtk main loop
    Gtk.main()

if __name__ == '__main__':
    main()
