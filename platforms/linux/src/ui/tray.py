import os
import sys
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, GLib

# Import AppIndicator/AyatanaAppIndicator
try:
    gi.require_version('AppIndicator3', '0.1')
    from gi.repository import AppIndicator3 as appindicator
except (ValueError, ImportError):
    try:
        gi.require_version('AyatanaAppIndicator3', '0.1')
        from gi.repository import AyatanaAppIndicator3 as appindicator
    except (ValueError, ImportError):
        print("Error: AppIndicator3 or AyatanaAppIndicator3 is required.")
        sys.exit(1)

from .window import MenuBarWindow

APPINDICATOR_ID = 'portkiller'

class PortKillerTrayApp:
    def __init__(self):
        # Create the macOS-like dropdown window
        self.dashboard_window = MenuBarWindow()

        # Locate AppIcon.svg
        from ..config import get_icon_path
        icon_path = get_icon_path()
        if not icon_path:
            icon_path = "utilities-system-monitor"  # Fallback system icon

        self.indicator = appindicator.Indicator.new(
            APPINDICATOR_ID,
            icon_path,
            appindicator.IndicatorCategory.SYSTEM_SERVICES
        )
        self.indicator.set_status(appindicator.IndicatorStatus.ACTIVE)

        self.menu = Gtk.Menu()
        self.indicator.set_menu(self.menu)

        # Build initial tray menu
        self.build_menu()

    def build_menu(self):
        # Clear previous items
        for child in self.menu.get_children():
            self.menu.remove(child)

        # Item 1: Open Search & Dashboard
        dash_item = Gtk.MenuItem(label="🔍 Quick Search & Port Dashboard...")
        dash_item.connect("activate", lambda w: self.dashboard_window.show_near_pointer())
        self.menu.append(dash_item)

        self.menu.append(Gtk.SeparatorMenuItem())

        # Item 2: Refresh Data
        refresh_item = Gtk.MenuItem(label="Refresh Now")
        refresh_item.connect("activate", lambda w: self.dashboard_window.refresh_data())
        self.menu.append(refresh_item)

        # Item 3: Quit
        quit_item = Gtk.MenuItem(label="Quit PortKiller")
        quit_item.connect("activate", lambda w: Gtk.main_quit())
        self.menu.append(quit_item)

        self.menu.show_all()
