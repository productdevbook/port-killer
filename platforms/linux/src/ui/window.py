import os
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk, GLib, GdkPixbuf

from ..config import config
from ..scanner import PortScanner
from ..services.cloudflare import cloudflare_service
from ..services.k8s import k8s_service
from ..services.clipboard import copy_to_clipboard
from .dialogs import PortDetailsDialog

class MenuBarWindow(Gtk.Window):
    def __init__(self):
        super().__init__(type=Gtk.WindowType.TOPLEVEL)
        self.set_keep_above(True)
        self.set_decorated(False)
        self.set_default_size(340, 400)
        self.set_resizable(False)
        
        # Style classes
        self.get_style_context().add_class("menu-bar-window")
        
        # Focus loss hiding
        self.add_events(Gdk.EventMask.FOCUS_CHANGE_MASK)
        self.connect("focus-out-event", self._on_focus_out)
        
        # Search state
        self.search_query = ""
        self.confirming_kill_all = False
        self.expanded_processes = set()  # Set of PIDs expanded in tree view
        
        # Main layout
        main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.add(main_box)
        
        # 1. Search Bar Area
        search_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        search_box.get_style_context().add_class("search-box")
        main_box.pack_start(search_box, False, False, 0)
        
        self.search_entry = Gtk.SearchEntry()
        self.search_entry.set_placeholder_text("Search ports or processes...")
        self.search_entry.get_style_context().add_class("search-entry")
        self.search_entry.connect("search-changed", self._on_search_changed)
        search_box.pack_start(self.search_entry, True, True, 0)
        
        # 2. Scrollable Content Area
        self.scroll = Gtk.ScrolledWindow()
        self.scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.scroll.get_style_context().add_class("port-list-container")
        main_box.pack_start(self.scroll, True, True, 0)
        
        self.content_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.scroll.add(self.content_box)
        
        # Initial scan & render
        self.local_ports = []
        self.k8s_forwards = []
        self.cf_tunnels = []
        self.refresh_data()

    def _on_focus_out(self, widget, event):
        # Hide the window when the user clicks outside
        self.hide()
        return True

    def show_near_pointer(self):
        # Get mouse pointer position to place window
        display = Gdk.Display.get_default()
        seat = display.get_default_seat()
        pointer = seat.get_pointer()
        
        if pointer:
            screen, x, y = pointer.get_position()
            width, height = self.get_size()
            
            # Find current monitor geometry
            monitor = display.get_monitor_at_point(x, y)
            geom = monitor.get_geometry()
            
            # Position horizontally centered around mouse, clamped to screen bounds
            win_x = max(geom.x, min(x - width // 2, geom.x + geom.width - width))
            
            # Detect top or bottom panel alignment
            if y < geom.y + geom.height / 2:
                win_y = geom.y + 36  # Offset below top bar
            else:
                win_y = y - height - 12  # Offset above bottom bar
                
            self.move(win_x, win_y)
            
        self.show_all()
        self.present()
        self.grab_focus()
        
        # Trigger refresh on show
        self.refresh_data()

    def _on_search_changed(self, entry):
        self.search_query = entry.get_text().strip().lower()
        self.render_list()

    def refresh_data(self):
        # Scan system state
        self.local_ports = PortScanner.scan_ports()
        self.k8s_forwards = k8s_service.scan_active_forwards()
        
        # Get managed cloudflare tunnels + external ones
        self.cf_tunnels = list(cloudflare_service.active_tunnels.values())
        external_cf = cloudflare_service.scan_running_tunnels_from_ps()
        for ext in external_cf:
            # Avoid duplicate ports
            if not any(t.port == ext['port'] for t in self.cf_tunnels):
                self.cf_tunnels.append(ext)
                
        self.render_list()

    def render_list(self):
        # Clear previous items
        for child in self.content_box.get_children():
            self.content_box.remove(child)
            
        # Filter Local Ports
        filtered_ports = []
        for p in self.local_ports:
            # Search query matching
            query_match = (
                not self.search_query or
                self.search_query in str(p['port']) or
                self.search_query in p['process_name'].lower() or
                self.search_query in p['command'].lower()
            )
            
            # Hide system process filtering
            is_system = p.get('process_name', '').lower() in ["systemd", "init", "sshd", "dbus-daemon", "systemd-resolved"]
            system_match = not config.hide_system_processes or not is_system
            
            if query_match and system_match:
                filtered_ports.append(p)

        # Filter K8s Forwards
        filtered_k8s = []
        for k in self.k8s_forwards:
            query_match = (
                not self.search_query or
                self.search_query in str(k.local_port) or
                self.search_query in k.resource.lower() or
                self.search_query in k.namespace.lower()
            )
            if query_match:
                filtered_k8s.append(k)

        # Filter CF Tunnels
        filtered_cf = []
        for t in self.cf_tunnels:
            port_val = t.port if hasattr(t, 'port') else t.get('port', 0)
            url_val = t.url if hasattr(t, 'url') else t.get('url', '')
            query_match = (
                not self.search_query or
                self.search_query in str(port_val) or
                self.search_query in str(url_val).lower()
            )
            if query_match:
                filtered_cf.append(t)

        # Render Cloudflare Tunnels Section
        if filtered_cf:
            self.add_section_header("Cloudflare Tunnels", "cloud")
            for t in filtered_cf:
                self.add_tunnel_row(t)

        # Render K8s Port Forwards Section
        if filtered_k8s:
            self.add_section_header("K8s Port Forward", "network-workgroup")
            for k in filtered_k8s:
                self.add_k8s_row(k)

        # Render Local Ports Section
        if filtered_ports:
            self.add_section_header("Local Ports", "network-transmit-receive")
            
            if config.use_tree_view:
                # Group by process name / PID
                groups = {}
                for p in filtered_ports:
                    pid = p['pid']
                    if pid not in groups:
                        groups[pid] = {
                            'pid': pid,
                            'name': p['process_name'],
                            'ports': []
                        }
                    groups[pid]['ports'].append(p)
                
                # Render tree rows
                for pid, group in sorted(groups.items(), key=lambda x: x[1]['name'].lower()):
                    self.add_tree_group_row(group)
            else:
                # Flat List View
                # Sort favorites to top, then by port number
                sorted_flat = sorted(
                    filtered_ports,
                    key=lambda x: (not config.is_favorite(x['port']), x['port'])
                )
                for p in sorted_flat:
                    self.add_flat_port_row(p)

        # Empty State
        if not filtered_ports and not filtered_k8s and not filtered_cf:
            empty_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
            empty_box.set_margin_top(40)
            empty_box.set_margin_bottom(40)
            
            image = Gtk.Image.new_from_icon_name("network-error", Gtk.IconSize.DIALOG)
            label = Gtk.Label(label="No listening ports found")
            label.get_style_context().add_class("header-subtitle")
            
            empty_box.pack_start(image, False, False, 0)
            empty_box.pack_start(label, False, False, 0)
            self.content_box.pack_start(empty_box, True, True, 0)

        self.content_box.show_all()

    def add_section_header(self, title, icon_name):
        hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        hbox.get_style_context().add_class("section-header")
        
        icon = Gtk.Image.new_from_icon_name(icon_name, Gtk.IconSize.MENU)
        label = Gtk.Label(label=title.upper())
        label.get_style_context().add_class("section-label")
        
        hbox.pack_start(icon, False, False, 0)
        hbox.pack_start(label, False, False, 0)
        self.content_box.pack_start(hbox, False, False, 0)

    def add_tunnel_row(self, t):
        port_val = t.port if hasattr(t, 'port') else t.get('port', 0)
        url_val = t.url if hasattr(t, 'url') else t.get('url', '')
        status_val = t.status if hasattr(t, 'status') else t.get('status', 'active')
        
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        row.get_style_context().add_class("connection-row")
        
        details_vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        title = Gtk.Label(label=f"Port {port_val}")
        title.get_style_context().add_class("connection-title")
        title.set_xalign(0)
        
        detail_txt = f"{url_val} ({status_val})"
        detail = Gtk.Label(label=detail_txt)
        detail.get_style_context().add_class("connection-detail")
        detail.set_line_wrap(True)
        detail.set_xalign(0)
        
        details_vbox.pack_start(title, False, False, 0)
        details_vbox.pack_start(detail, False, False, 0)
        row.pack_start(details_vbox, True, True, 0)
        
        # Stop Button
        btn_stop = Gtk.Button()
        btn_stop.get_style_context().add_class("menu-btn")
        btn_stop.get_style_context().add_class("menu-btn-destructive")
        btn_stop.set_image(Gtk.Image.new_from_icon_name("media-playback-stop", Gtk.IconSize.MENU))
        btn_stop.connect("clicked", lambda w, p=port_val: self.stop_cf_tunnel(p))
        row.pack_start(btn_stop, False, False, 0)
        
        self.content_box.pack_start(row, False, False, 0)

    def stop_cf_tunnel(self, port):
        cloudflare_service.stop_tunnel(port)
        self.refresh_data()

    def add_k8s_row(self, k):
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        row.get_style_context().add_class("connection-row")
        
        details_vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        title = Gtk.Label(label=f"{k.resource} → {k.local_port}:{k.remote_port}")
        title.get_style_context().add_class("connection-title")
        title.set_xalign(0)
        
        detail = Gtk.Label(label=f"Namespace: {k.namespace} | PID: {k.pid}")
        detail.get_style_context().add_class("connection-detail")
        detail.set_xalign(0)
        
        details_vbox.pack_start(title, False, False, 0)
        details_vbox.pack_start(detail, False, False, 0)
        row.pack_start(details_vbox, True, True, 0)
        
        # Stop Button
        btn_stop = Gtk.Button()
        btn_stop.get_style_context().add_class("menu-btn")
        btn_stop.get_style_context().add_class("menu-btn-destructive")
        btn_stop.set_image(Gtk.Image.new_from_icon_name("media-playback-stop", Gtk.IconSize.MENU))
        btn_stop.connect("clicked", lambda w, p=k.pid: self.stop_k8s_forward(p))
        row.pack_start(btn_stop, False, False, 0)
        
        self.content_box.pack_start(row, False, False, 0)

    def stop_k8s_forward(self, pid):
        k8s_service.stop_port_forward(pid)
        self.refresh_data()

    def add_flat_port_row(self, p):
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        row.get_style_context().add_class("list-row")
        
        # Favorite Icon Button
        is_fav = config.is_favorite(p['port'])
        btn_fav = Gtk.Button()
        btn_fav.get_style_context().add_class("tree-expand-btn")
        fav_icon_name = "starred" if is_fav else "non-starred"
        btn_fav.set_image(Gtk.Image.new_from_icon_name(fav_icon_name, Gtk.IconSize.MENU))
        btn_fav.connect("clicked", lambda w, port=p['port']: self.toggle_favorite(port))
        row.pack_start(btn_fav, False, False, 0)
        
        # Port info
        lbl_port = Gtk.Label(label=f"{p['port']}")
        lbl_port.get_style_context().add_class("row-port")
        lbl_port.set_xalign(0)
        row.pack_start(lbl_port, False, False, 4)
        
        # Arrow separator
        lbl_arrow = Gtk.Label(label="→")
        lbl_arrow.set_xalign(0)
        row.pack_start(lbl_arrow, False, False, 4)
        
        # Process Name
        lbl_proc = Gtk.Label(label=f"{p['process_name']}")
        lbl_proc.get_style_context().add_class("row-process")
        lbl_proc.set_xalign(0)
        row.pack_start(lbl_proc, True, True, 4)
        
        # Action buttons
        btn_copy = Gtk.Button(label="Copy")
        btn_copy.get_style_context().add_class("menu-btn")
        btn_copy.connect("clicked", lambda w, port=p['port']: self.copy_port_direct(port))
        row.pack_start(btn_copy, False, False, 0)
        
        if p['pid'] != 0:
            btn_kill = Gtk.Button(label="Kill")
            btn_kill.get_style_context().add_class("menu-btn")
            btn_kill.get_style_context().add_class("menu-btn-destructive")
            btn_kill.connect("clicked", lambda w, pid=p['pid'], port=p['port']: self.kill_process_direct(pid, port))
            row.pack_start(btn_kill, False, False, 0)
        
        self.content_box.pack_start(row, False, False, 0)

    def toggle_favorite(self, port):
        if config.is_favorite(port):
            config.remove_favorite(port)
        else:
            config.add_favorite(port)
        self.render_list()

    def add_tree_group_row(self, group):
        pid = group['pid']
        is_expanded = pid in self.expanded_processes
        
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        row.get_style_context().add_class("list-row")
        
        # Expand/Collapse arrow
        btn_toggle = Gtk.Button()
        btn_toggle.get_style_context().add_class("tree-expand-btn")
        arrow_icon = "pan-down-symbolic" if is_expanded else "pan-end-symbolic"
        btn_toggle.set_image(Gtk.Image.new_from_icon_name(arrow_icon, Gtk.IconSize.MENU))
        btn_toggle.connect("clicked", lambda w, p=pid: self.toggle_expand_tree(p))
        row.pack_start(btn_toggle, False, False, 0)
        
        # Process Name & PID
        proc_title = f"{group['name']} (PID {pid if pid != 0 else '?'})"
        lbl_proc = Gtk.Label(label=proc_title)
        lbl_proc.get_style_context().add_class("row-process")
        lbl_proc.set_xalign(0)
        row.pack_start(lbl_proc, True, True, 4)
        
        # Kill Process Button
        if pid != 0:
            btn_kill = Gtk.Button(label="Kill")
            btn_kill.get_style_context().add_class("menu-btn")
            btn_kill.get_style_context().add_class("menu-btn-destructive")
            btn_kill.connect("clicked", lambda w, p=pid: self.kill_entire_process(p))
            row.pack_start(btn_kill, False, False, 0)
            
        self.content_box.pack_start(row, False, False, 0)
        
        # Render child ports if expanded
        if is_expanded:
            for p in group['ports']:
                child_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
                child_row.get_style_context().add_class("list-row")
                child_row.set_margin_start(24)  # Indent
                
                # Favorite Star
                is_fav = config.is_favorite(p['port'])
                btn_fav = Gtk.Button()
                btn_fav.get_style_context().add_class("tree-expand-btn")
                fav_icon_name = "starred" if is_fav else "non-starred"
                btn_fav.set_image(Gtk.Image.new_from_icon_name(fav_icon_name, Gtk.IconSize.MENU))
                btn_fav.connect("clicked", lambda w, port=p['port']: self.toggle_favorite(port))
                child_row.pack_start(btn_fav, False, False, 0)
                
                # Port
                lbl_port = Gtk.Label(label=f"Port {p['port']}")
                lbl_port.get_style_context().add_class("row-port")
                lbl_port.set_xalign(0)
                child_row.pack_start(lbl_port, True, True, 4)
                
                # Action buttons
                btn_copy = Gtk.Button(label="Copy")
                btn_copy.get_style_context().add_class("menu-btn")
                btn_copy.connect("clicked", lambda w, port=p['port']: self.copy_port_direct(port))
                child_row.pack_start(btn_copy, False, False, 0)
                
                if p['pid'] != 0:
                    btn_kill = Gtk.Button(label="Kill")
                    btn_kill.get_style_context().add_class("menu-btn")
                    btn_kill.get_style_context().add_class("menu-btn-destructive")
                    btn_kill.connect("clicked", lambda w, pid=p['pid'], port=p['port']: self.kill_process_direct(pid, port))
                    child_row.pack_start(btn_kill, False, False, 0)
                
                self.content_box.pack_start(child_row, False, False, 0)

    def toggle_expand_tree(self, pid):
        if pid in self.expanded_processes:
            self.expanded_processes.remove(pid)
        else:
            self.expanded_processes.add(pid)
        self.render_list()

    def kill_entire_process(self, pid):
        PortScanner.kill_process(pid, force=True)
        GLib.timeout_add(200, self.refresh_data)

    def copy_port_direct(self, port):
        copy_to_clipboard(str(port))
        try:
            import subprocess
            subprocess.run(["notify-send", "-a", "PortKiller", "Port Copied", f"Port {port} copied to clipboard!"])
        except Exception:
            pass

    def kill_process_direct(self, pid, port=None):
        if pid != 0:
            PortScanner.kill_process(pid, force=True)
            try:
                import subprocess
                msg = f"Process running on port {port} has been killed." if port else f"Process (PID {pid}) has been killed."
                subprocess.run(["notify-send", "-a", "PortKiller", "Process Terminated", msg])
            except Exception:
                pass
            GLib.timeout_add(200, self.refresh_data)


