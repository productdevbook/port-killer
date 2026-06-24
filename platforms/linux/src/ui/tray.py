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
from .dialogs import PortDetailsDialog
from ..scanner import PortScanner

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

        # Set up auto-refresh timer (every 5 seconds)
        GLib.timeout_add_seconds(5, self.auto_refresh)

    def build_menu(self):
        # Clear previous items
        for child in self.menu.get_children():
            self.menu.remove(child)

        # Item 1: Open Search & Dashboard
        dash_item = Gtk.MenuItem(label="🔍 Quick Search & Port Dashboard...")
        dash_item.connect("activate", lambda w: self.dashboard_window.show_near_pointer())
        self.menu.append(dash_item)

        self.menu.append(Gtk.SeparatorMenuItem())

        # Render Active Ports directly in the menu for quick access
        ports = PortScanner.scan_ports()
        if not ports:
            empty_item = Gtk.MenuItem(label="No listening ports active")
            empty_item.set_sensitive(False)
            self.menu.append(empty_item)
        else:
            for p in ports:
                port_label = f"{p['port']} → {p['process_name']}"
                if p['pid'] != 0:
                    port_label += f" (PID {p['pid']})"
                
                port_item = Gtk.MenuItem(label=port_label)
                port_item.connect("activate", lambda w, port_info=p: self.open_port_dialog(port_info))
                self.menu.append(port_item)

        self.menu.append(Gtk.SeparatorMenuItem())

        # Item 2: Refresh Data
        refresh_item = Gtk.MenuItem(label="Refresh Now")
        refresh_item.connect("activate", lambda w: self.build_menu())
        self.menu.append(refresh_item)

        # Item 3: Quit
        quit_item = Gtk.MenuItem(label="Quit PortKiller")
        quit_item.connect("activate", lambda w: Gtk.main_quit())
        self.menu.append(quit_item)

        self.menu.show_all()

    def open_port_dialog(self, p):
        # Open port details dialog
        dialog = PortDetailsDialog(None, p)
        response = dialog.run()
        
        if response == 1:  # Kill Process (SIGTERM)
            PortScanner.kill_process(p['pid'], force=False)
        elif response == 2:  # Force Kill (SIGKILL)
            PortScanner.kill_process(p['pid'], force=True)
        elif response == 3:  # Copy PID
            from ..services.clipboard import copy_to_clipboard
            copy_to_clipboard(str(p['pid']))
        elif response == 4:  # Copy Port
            from ..services.clipboard import copy_to_clipboard
            copy_to_clipboard(str(p['port']))
            
        dialog.destroy()
        # Refresh lists soon after closing/killing
        GLib.timeout_add(200, self.build_menu)

    def auto_refresh(self):
        self.build_menu()
        return True
