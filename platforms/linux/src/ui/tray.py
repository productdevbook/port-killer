import os
import sys
import subprocess
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

from .dialogs import PortDetailsDialog
from ..scanner import PortScanner
from ..services.cloudflare import cloudflare_service
from ..services.k8s import k8s_service
from ..services.clipboard import copy_to_clipboard

APPINDICATOR_ID = 'portkiller'

class PortKillerTrayApp:
    def __init__(self):
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

        # Cache variables to detect changes and prevent menu flickering/autoclose
        self.last_state = None

        # Build initial tray menu
        self.refresh_and_build()

        # Set up auto-refresh timer (every 5 seconds)
        GLib.timeout_add_seconds(5, self.auto_refresh)

    def refresh_and_build(self):
        # Scan ports, tunnels, and forwards
        ports = PortScanner.scan_ports()
        k8s_forwards = k8s_service.scan_active_forwards()
        
        # Get cloudflare tunnels
        cf_tunnels = list(cloudflare_service.active_tunnels.values())
        external_cf = cloudflare_service.scan_running_tunnels_from_ps()
        for ext in external_cf:
            if not any(t.port == ext['port'] for t in cf_tunnels):
                cf_tunnels.append(ext)

        # Rebuild Gtk Menu
        self.build_menu_with_data(ports, k8s_forwards, cf_tunnels)

    def build_menu_with_data(self, ports, k8s_forwards, cf_tunnels):
        # Clear previous items
        for child in self.menu.get_children():
            self.menu.remove(child)

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
                t_label = f"Port {port_val} → {url_val if url_val else 'Starting...'}"
                
                # Single tunnel options submenu
                single_t_item = Gtk.MenuItem(label=t_label)
                single_t_submenu = Gtk.Menu()
                single_t_item.set_submenu(single_t_submenu)
                
                if url_val:
                    copy_url_item = Gtk.MenuItem(label="📋 Copy Tunnel URL")
                    copy_url_item.connect("activate", lambda w, u=url_val: self.copy_and_notify(u, "Tunnel URL copied to clipboard!"))
                    single_t_submenu.append(copy_url_item)
                
                stop_tunnel_item = Gtk.MenuItem(label="💀 Stop Tunnel")
                stop_tunnel_item.connect("activate", lambda w, p=port_val: self.stop_cf_tunnel_and_notify(p))
                single_t_submenu.append(stop_tunnel_item)
                
                cf_submenu.append(single_t_item)
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
                
                # Single k8s options submenu
                single_k_item = Gtk.MenuItem(label=k_label)
                single_k_submenu = Gtk.Menu()
                single_k_item.set_submenu(single_k_submenu)
                
                copy_port_item = Gtk.MenuItem(label="📋 Copy Local Port")
                copy_port_item.connect("activate", lambda w, p=k.local_port: self.copy_and_notify(str(p), f"Port {p} copied to clipboard!"))
                single_k_submenu.append(copy_port_item)
                
                stop_forward_item = Gtk.MenuItem(label="💀 Stop Port Forward")
                stop_forward_item.connect("activate", lambda w, p=k.pid, r=k.resource: self.stop_k8s_forward_and_notify(p, r))
                single_k_submenu.append(stop_forward_item)
                
                k8s_submenu.append(single_k_item)
        self.menu.append(k8s_item)

        # 3. Local Ports Submenu (Restored direct clicks to open management Dialog)
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
                
                # Port item clicking opens the Dialog modal
                port_item = Gtk.MenuItem(label=port_label)
                port_item.connect("activate", lambda w, port_info=p: self.open_port_dialog(port_info))
                local_submenu.append(port_item)
        self.menu.append(local_item)

        self.menu.append(Gtk.SeparatorMenuItem())

        # Item 4: Refresh Data
        refresh_item = Gtk.MenuItem(label="Refresh Now")
        refresh_item.connect("activate", lambda w: self.refresh_and_build())
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
            self.copy_and_notify(str(p['port']), f"Process on port {p['port']} terminated (SIGTERM)!")
        elif response == 2:  # Force Kill (SIGKILL)
            PortScanner.kill_process(p['pid'], force=True)
            self.copy_and_notify(str(p['port']), f"Process on port {p['port']} force killed (SIGKILL)!")
        elif response == 3:  # Copy PID
            self.copy_and_notify(str(p['pid']), f"PID {p['pid']} copied to clipboard!")
        elif response == 4:  # Copy Port
            self.copy_and_notify(str(p['port']), f"Port {p['port']} copied to clipboard!")
            
        dialog.destroy()
        # Refresh lists soon after closing/killing
        GLib.timeout_add(200, self.refresh_and_build)

    def copy_and_notify(self, text, message):
        copy_to_clipboard(text)
        try:
            subprocess.run(["notify-send", "-a", "PortKiller", "Action Done", message])
        except Exception:
            pass

    def stop_cf_tunnel_and_notify(self, port):
        cloudflare_service.stop_tunnel(port)
        try:
            subprocess.run(["notify-send", "-a", "PortKiller", "Tunnel Stopped", f"Cloudflare Tunnel on port {port} stopped!"])
        except Exception:
            pass
        GLib.timeout_add(200, self.refresh_and_build)

    def stop_k8s_forward_and_notify(self, pid, resource):
        k8s_service.stop_port_forward(pid)
        try:
            subprocess.run(["notify-send", "-a", "PortKiller", "Port Forward Stopped", f"Kubernetes port-forward for {resource} stopped!"])
        except Exception:
            pass
        GLib.timeout_add(200, self.refresh_and_build)

    def auto_refresh(self):
        # Scan ports, tunnels, and forwards
        ports = PortScanner.scan_ports()
        k8s_forwards = k8s_service.scan_active_forwards()
        
        # Get cloudflare tunnels
        cf_tunnels = list(cloudflare_service.active_tunnels.values())
        external_cf = cloudflare_service.scan_running_tunnels_from_ps()
        for ext in external_cf:
            if not any(t.port == ext['port'] for t in cf_tunnels):
                cf_tunnels.append(ext)

        # Hash/Represent current state to compare with previous state
        current_state = {
            'ports': [(p['port'], p['pid'], p['process_name']) for p in ports],
            'k8s': [(k.pid, k.local_port, k.remote_port, k.resource) for k in k8s_forwards],
            'cf': [(t.port if hasattr(t, 'port') else t.get('port', 0),
                    t.url if hasattr(t, 'url') else t.get('url', '')) for t in cf_tunnels]
        }

        # Rebuild only if something changed (prevents menu from closing while user reads it)
        if self.last_state != current_state:
            self.last_state = current_state
            self.build_menu_with_data(ports, k8s_forwards, cf_tunnels)

        return True
