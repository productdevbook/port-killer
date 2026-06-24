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
from ..services.cloudflare import cloudflare_service
from ..services.k8s import k8s_service

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
        dash_item = Gtk.MenuItem(label="🔍 Open Search & Dashboard...")
        dash_item.connect("activate", lambda w: self.dashboard_window.show_near_pointer())
        self.menu.append(dash_item)

        self.menu.append(Gtk.SeparatorMenuItem())

        # Scan ports, tunnels, and forwards
        ports = PortScanner.scan_ports()
        k8s_forwards = k8s_service.scan_active_forwards()
        
        # Get cloudflare tunnels
        cf_tunnels = list(cloudflare_service.active_tunnels.values())
        external_cf = cloudflare_service.scan_running_tunnels_from_ps()
        for ext in external_cf:
            if not any(t.port == ext['port'] for t in cf_tunnels):
                cf_tunnels.append(ext)

        # 1. Cloudflare Tunnels Submenu
        cf_label = f"☁️ Cloudflare Tunnels ({len(cf_tunnels)})"
        cf_item = Gtk.MenuItem(label=cf_label)
        cf_submenu = Gtk.Menu()
        cf_item.set_submenu(cf_submenu)
        
        if not cf_tunnels:
            no_cf = Gtk.MenuItem(label="No active tunnels")
            no_cf.set_sensitive(False)
            cf_submenu.append(no_cf)
        else:
            for t in cf_tunnels:
                port_val = t.port if hasattr(t, 'port') else t.get('port', 0)
                url_val = t.url if hasattr(t, 'url') else t.get('url', '')
                t_label = f"Port {port_val} → {url_val}"
                t_item = Gtk.MenuItem(label=t_label)
                t_item.connect("activate", lambda w: self.dashboard_window.show_near_pointer())
                cf_submenu.append(t_item)
        self.menu.append(cf_item)

        # 2. K8s Port Forwards Submenu
        k8s_label = f"☸️ K8s Port Forward ({len(k8s_forwards)})"
        k8s_item = Gtk.MenuItem(label=k8s_label)
        k8s_submenu = Gtk.Menu()
        k8s_item.set_submenu(k8s_submenu)
        
        if not k8s_forwards:
            no_k8s = Gtk.MenuItem(label="No active port forwards")
            no_k8s.set_sensitive(False)
            k8s_submenu.append(no_k8s)
        else:
            for k in k8s_forwards:
                k_label = f"{k.resource} → {k.local_port}:{k.remote_port} ({k.namespace})"
                k_item = Gtk.MenuItem(label=k_label)
                k_item.connect("activate", lambda w: self.dashboard_window.show_near_pointer())
                k8s_submenu.append(k_item)
        self.menu.append(k8s_item)

        # 3. Local Ports Submenu
        local_label = f"🌐 Local Ports ({len(ports)})"
        local_item = Gtk.MenuItem(label=local_label)
        local_submenu = Gtk.Menu()
        local_item.set_submenu(local_submenu)
        
        if not ports:
            no_ports = Gtk.MenuItem(label="No open ports")
            no_ports.set_sensitive(False)
            local_submenu.append(no_ports)
        else:
            for p in ports:
                port_label = f"{p['port']} → {p['process_name']}"
                if p['pid'] != 0:
                    port_label += f" (PID {p['pid']})"
                
                port_item = Gtk.MenuItem(label=port_label)
                port_item.connect("activate", lambda w, port_info=p: self.open_port_dialog(port_info))
                local_submenu.append(port_item)
        self.menu.append(local_item)

        self.menu.append(Gtk.SeparatorMenuItem())

        # Item 4: Refresh Data
        refresh_item = Gtk.MenuItem(label="Refresh Now")
        refresh_item.connect("activate", lambda w: self.build_menu())
        self.menu.append(refresh_item)

        # Item 5: Quit
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
