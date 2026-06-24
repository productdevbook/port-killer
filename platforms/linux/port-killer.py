#!/usr/bin/env python3
import os
import sys
import subprocess
import gi

# Ensure we use GTK 3
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, GObject, GLib, Gdk, GdkPixbuf

# Import AppIndicator/AyatanaAppIndicator
try:
    gi.require_version('AppIndicator3', '0.1')
    from gi.repository import AppIndicator3 as appindicator
except (ValueError, ImportError):
    try:
        gi.require_version('AyatanaAppIndicator3', '0.1')
        from gi.repository import AyatanaAppIndicator3 as appindicator
    except (ValueError, ImportError):
        print("Error: AppIndicator3 or AyatanaAppIndicator3 is required for the system tray app.")
        print("Install it using: sudo apt install python3-gi python3-gi-cairo gir1.2-appindicator3-0.1")
        sys.exit(1)

# App configurations
APPINDICATOR_ID = 'portkiller'

# Custom CSS styling for the details dialog to make it look premium
CSS_DATA = b"""
    window.port-dialog {
        background-color: #1e1e2e;
        color: #cdd6f4;
        border-radius: 12px;
    }
    .header-box {
        background: linear-gradient(135deg, #89b4fa, #cba6f7);
        padding: 20px;
        border-radius: 12px 12px 0 0;
    }
    .header-title {
        font-family: 'Ubuntu', 'Liberation Sans', sans-serif;
        font-size: 24px;
        font-weight: 800;
        color: #11111b;
    }
    .header-subtitle {
        font-family: 'Ubuntu', 'Liberation Sans', sans-serif;
        font-size: 14px;
        font-weight: 500;
        color: #1e1e2e;
    }
    .content-box {
        padding: 16px;
        background-color: #1e1e2e;
    }
    .detail-label {
        font-family: 'Liberation Mono', 'Fira Code', 'DejaVu Sans Mono', monospace;
        font-size: 12px;
        color: #cdd6f4;
        background-color: #11111b;
        padding: 14px;
        border-radius: 8px;
        border: 1px solid #313244;
    }
    button {
        font-family: 'Ubuntu', 'Liberation Sans', sans-serif;
        font-size: 13px;
        font-weight: bold;
        padding: 10px 16px;
        border-radius: 8px;
        border: none;
        box-shadow: 0 2px 4px rgba(0, 0, 0, 0.15);
        transition: all 0.2s ease-in-out;
    }
    .btn-kill {
        background-color: #f38ba8;
        color: #11111b;
    }
    .btn-kill:hover {
        background-color: #eba0b2;
    }
    .btn-force {
        background-color: #fab387;
        color: #11111b;
    }
    .btn-force:hover {
        background-color: #f9e2af;
    }
    .btn-secondary {
        background-color: #313244;
        color: #cdd6f4;
        border: 1px solid #45475a;
    }
    .btn-secondary:hover {
        background-color: #45475a;
    }
    .btn-close {
        background-color: #45475a;
        color: #cdd6f4;
    }
    .btn-close:hover {
        background-color: #585b70;
    }
"""

class PortDetailsDialog(Gtk.Dialog):
    def __init__(self, parent, p):
        super().__init__(title=f"Port {p['port']} Management", transient_for=parent, flags=0)
        self.set_default_size(440, 380)
        self.set_resizable(False)
        
        # Apply CSS class
        self.get_style_context().add_class("port-dialog")
        
        # Main layout box
        content_area = self.get_content_area()
        main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        content_area.pack_start(main_box, True, True, 0)
        
        # Header box with gradient and title
        header_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=16)
        header_box.get_style_context().add_class("header-box")
        main_box.pack_start(header_box, False, False, 0)
        
        # Try to load custom icon
        image = Gtk.Image()
        script_dir = os.path.dirname(os.path.abspath(__file__))
        icon_path = os.path.join(script_dir, "AppIcon.svg")
        
        icon_loaded = False
        if os.path.exists(icon_path):
            try:
                pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(icon_path, 48, 48, True)
                image.set_from_pixbuf(pixbuf)
                icon_loaded = True
            except Exception:
                pass
                
        if not icon_loaded:
            # Fallback to standard system icon
            image.set_from_icon_name("utilities-system-monitor", Gtk.IconSize.DIALOG)
            
        header_box.pack_start(image, False, False, 0)
        
        # Header text
        header_text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        title_label = Gtk.Label(label=f"Port {p['port']}")
        title_label.get_style_context().add_class("header-title")
        title_label.set_xalign(0)
        
        subtitle_label = Gtk.Label(label=f"Process: {p['process_name']}")
        subtitle_label.get_style_context().add_class("header-subtitle")
        subtitle_label.set_xalign(0)
        
        header_text_box.pack_start(title_label, True, True, 0)
        header_text_box.pack_start(subtitle_label, True, True, 0)
        header_box.pack_start(header_text_box, True, True, 0)
        
        # Body box
        body_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        body_box.get_style_context().add_class("content-box")
        body_box.set_margin_start(16)
        body_box.set_margin_end(16)
        body_box.set_margin_top(16)
        main_box.pack_start(body_box, True, True, 0)
        
        # Details text
        details = (
            f"PID:      {p['pid'] if p['pid'] != 0 else 'Unknown'}\n"
            f"Address:  {p['address']}\n"
            f"Command:  {p['command']}"
        )
        details_label = Gtk.Label(label=details)
        details_label.get_style_context().add_class("detail-label")
        details_label.set_xalign(0)
        details_label.set_line_wrap(True)
        body_box.pack_start(details_label, True, True, 0)
        
        # Actions box
        actions_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        actions_box.set_margin_bottom(16)
        body_box.pack_start(actions_box, False, False, 0)
        
        # Row 1: Kill actions
        if p['pid'] != 0:
            kill_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            btn_kill = Gtk.Button(label="Kill Process (SIGTERM)")
            btn_kill.get_style_context().add_class("btn-kill")
            btn_kill.connect("clicked", lambda w: self.response(1))
            
            btn_force = Gtk.Button(label="Force Kill (SIGKILL)")
            btn_force.get_style_context().add_class("btn-force")
            btn_force.connect("clicked", lambda w: self.response(2))
            
            kill_row.pack_start(btn_kill, True, True, 0)
            kill_row.pack_start(btn_force, True, True, 0)
            actions_box.pack_start(kill_row, False, False, 0)
            
            # Row 2: Copy actions
            utils_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            btn_copy_pid = Gtk.Button(label="Copy PID")
            btn_copy_pid.get_style_context().add_class("btn-secondary")
            btn_copy_pid.connect("clicked", lambda w: self.response(3))
            
            btn_copy_port = Gtk.Button(label="Copy Port")
            btn_copy_port.get_style_context().add_class("btn-secondary")
            btn_copy_port.connect("clicked", lambda w: self.response(4))
            
            utils_row.pack_start(btn_copy_pid, True, True, 0)
            utils_row.pack_start(btn_copy_port, True, True, 0)
            actions_box.pack_start(utils_row, False, False, 0)
        else:
            btn_copy_port = Gtk.Button(label="Copy Port")
            btn_copy_port.get_style_context().add_class("btn-secondary")
            btn_copy_port.connect("clicked", lambda w: self.response(4))
            actions_box.pack_start(btn_copy_port, True, True, 0)
            
        # Row 3: Close
        btn_close = Gtk.Button(label="Close")
        btn_close.get_style_context().add_class("btn-close")
        btn_close.connect("clicked", lambda w: self.response(Gtk.ResponseType.CLOSE))
        actions_box.pack_start(btn_close, False, False, 0)
        
        self.show_all()

class PortKillerTrayApp:
    def __init__(self):
        icon_path = "utilities-system-monitor" # Use standard system theme icon for high reliability on GNOME/Wayland

        self.indicator = appindicator.Indicator.new(
            APPINDICATOR_ID,
            icon_path,
            appindicator.IndicatorCategory.SYSTEM_SERVICES
        )
        self.indicator.set_status(appindicator.IndicatorStatus.ACTIVE)

        self.menu = Gtk.Menu()
        self.indicator.set_menu(self.menu)

        # Initial build
        self.build_menu()

        # Set up auto-refresh timer (every 5 seconds)
        GLib.timeout_add_seconds(5, self.auto_refresh)

    def scan_ports(self):
        ports = []
        try:
            # Try ss first (more complete on Linux as it shows all ports, even of other users)
            result = subprocess.run(
                ["ss", "-tlnp"],
                capture_output=True,
                text=True,
                check=True
            )
            ports = self.parse_ss_output(result.stdout)
        except (subprocess.SubprocessError, FileNotFoundError):
            # Fall back to lsof
            try:
                result = subprocess.run(
                    ["lsof", "-iTCP", "-sTCP:LISTEN", "-P", "-n"],
                    capture_output=True,
                    text=True,
                    check=True
                )
                ports = self.parse_lsof_output(result.stdout)
            except (subprocess.SubprocessError, FileNotFoundError):
                pass
        return ports

    def parse_lsof_output(self, output):
        ports = []
        seen = set()
        lines = output.strip().split('\n')
        if len(lines) <= 1:
            return ports
        
        commands = self.get_process_commands()

        for line in lines[1:]:
            if not line.strip():
                continue
            parts = line.split()
            if len(parts) < 9:
                continue
            
            process_name = parts[0]
            try:
                pid = int(parts[1])
            except ValueError:
                continue
            
            # Find the name column with colon
            address_str = None
            for p in reversed(parts[8:]):
                if ':' in p and not p.startswith('0x') and not p.startswith('0t'):
                    address_str = p
                    break
            
            if not address_str:
                continue
            
            addr_port = self.parse_address(address_str)
            if not addr_port:
                continue
            address, port = addr_port
            
            command = commands.get(pid, process_name)
            if len(command) > 200:
                command = command[:200] + "..."
                
            if (port, pid) not in seen:
                seen.add((port, pid))
                ports.append({
                    'port': port,
                    'pid': pid,
                    'process_name': process_name,
                    'command': command,
                    'address': address
                })
                
        ports.sort(key=lambda x: x['port'])
        return ports

    def parse_ss_output(self, output):
        ports = []
        seen = set()
        lines = output.strip().split('\n')
        
        commands = self.get_process_commands()

        for line in lines:
            if not line.strip() or line.startswith('State'):
                continue
            parts = line.split()
            if len(parts) < 4:
                continue
                
            local_addr = parts[3]
            last_colon = local_addr.rfind(':')
            if last_colon == -1:
                continue
                
            address = local_addr[:last_colon]
            if not address:
                address = "*"
            try:
                port = int(local_addr[last_colon + 1:])
            except ValueError:
                continue
                
            pid = 0
            process_name = "Unknown"
            found_proc = False
            
            if len(parts) >= 6:
                proc_col = " ".join(parts[5:])
                users = self.parse_ss_users(proc_col)
                for name, p in users:
                    found_proc = True
                    command = commands.get(p, name)
                    if len(command) > 200:
                        command = command[:200] + "..."
                    if (port, p) not in seen:
                        seen.add((port, p))
                        ports.append({
                            'port': port,
                            'pid': p,
                            'process_name': name,
                            'command': command,
                            'address': address
                        })
            
            if not found_proc:
                if (port, pid) not in seen:
                    seen.add((port, pid))
                    ports.append({
                        'port': port,
                        'pid': pid,
                        'process_name': process_name,
                        'command': "Unknown",
                        'address': address
                    })
                
        ports.sort(key=lambda x: x['port'])
        return ports

    def parse_ss_users(self, users_str):
        results = []
        if "users:(" in users_str:
            content = users_str[users_str.find("users:(") + 7 : -1]
            for part in content.split("),("):
                clean = part.lstrip('(').rstrip(')')
                fields = clean.split(',')
                if len(fields) >= 2:
                    name = fields[0].strip('"')
                    pid_str = fields[1].strip()
                    if pid_str.startswith("pid="):
                        try:
                            pid = int(pid_str[4:])
                            results.append((name, pid))
                        except ValueError:
                            pass
        return results

    def parse_address(self, address_str):
        if address_str.startswith('['):
            bracket_end = address_str.find(']')
            if bracket_end == -1 or bracket_end + 1 >= len(address_str):
                return None
            after = address_str[bracket_end + 1:]
            if not after.startswith(':'):
                return None
            try:
                port = int(after[1:])
                return address_str[:bracket_end + 1], port
            except ValueError:
                return None
        else:
            last_colon = address_str.rfind(':')
            if last_colon == -1:
                return None
            try:
                port = int(address_str[last_colon + 1:])
                addr = address_str[:last_colon]
                if not addr:
                    addr = "*"
                return addr, port
            except ValueError:
                return None

    def get_process_commands(self):
        commands = {}
        try:
            result = subprocess.run(
                ["ps", "-axo", "pid,command"],
                capture_output=True,
                text=True,
                check=True
            )
            lines = result.stdout.strip().split('\n')
            for line in lines[1:]:
                trimmed = line.strip()
                if not trimmed:
                    continue
                parts = trimmed.split(None, 1)
                if len(parts) < 2:
                    continue
                try:
                    pid = int(parts[0])
                    commands[pid] = parts[1].strip()
                except ValueError:
                    continue
        except subprocess.SubprocessError:
            pass
        return commands

    def kill_process(self, pid, force=False):
        try:
            sig = "-9" if force else "-15"
            subprocess.run(["kill", sig, str(pid)], check=True)
            return True
        except subprocess.SubprocessError:
            return False

    def copy_to_clipboard(self, text):
        clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)
        clipboard.set_text(text, -1)

    def on_kill_process(self, pid, force):
        success = self.kill_process(pid, force)
        if success:
            # Refresh menu shortly after killing
            GLib.timeout_add(100, self.build_menu)

    def show_port_dialog(self, p):
        dialog = PortDetailsDialog(None, p)
        response = dialog.run()
        
        if response == 1:
            self.on_kill_process(p['pid'], force=False)
        elif response == 2:
            self.on_kill_process(p['pid'], force=True)
        elif response == 3:
            self.copy_to_clipboard(str(p['pid']))
        elif response == 4:
            self.copy_to_clipboard(str(p['port']))
            
        dialog.destroy()

    def build_menu(self):
        for child in self.menu.get_children():
            self.menu.remove(child)
            
        ports = self.scan_ports()
        
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
                port_item.connect("activate", lambda w, port_info=p: self.show_port_dialog(port_info))
                self.menu.append(port_item)
                
        self.menu.append(Gtk.SeparatorMenuItem())
        
        refresh_item = Gtk.MenuItem(label="Refresh Now")
        refresh_item.connect("activate", lambda w: self.build_menu())
        self.menu.append(refresh_item)
        
        quit_item = Gtk.MenuItem(label="Quit PortKiller")
        quit_item.connect("activate", Gtk.main_quit)
        self.menu.append(quit_item)
        
        self.menu.show_all()

    def auto_refresh(self):
        self.build_menu()
        return True

def main():
    # Load CSS Styles
    css_provider = Gtk.CssProvider()
    css_provider.load_from_data(CSS_DATA)
    screen = Gdk.Screen.get_default()
    Gtk.StyleContext.add_provider_for_screen(screen, css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    app = PortKillerTrayApp()
    Gtk.main()

if __name__ == '__main__':
    main()
