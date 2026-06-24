import os
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk, GdkPixbuf

from ..services.clipboard import copy_to_clipboard
from ..scanner import PortScanner

class PortDetailsDialog(Gtk.Dialog):
    def __init__(self, parent, p):
        super().__init__(title=f"Port {p['port']} Management", transient_for=parent, flags=0)
        self.set_default_size(440, 360)
        self.set_resizable(False)
        
        # Apply CSS class
        self.get_style_context().add_class("port-dialog")

        # Set window icon for taskbar/dock
        from ..config import get_icon_path
        icon_path = get_icon_path()
        if icon_path:
            try:
                self.set_icon_from_file(icon_path)
            except Exception:
                pass
        
        # Hide default action area to prevent drawing a square box at the very bottom
        self.get_action_area().hide()
        
        # Main layout box
        content_area = self.get_content_area()
        main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        content_area.pack_start(main_box, True, True, 0)
        
        # Header box with title
        header_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=16)
        header_box.get_style_context().add_class("header-box")
        main_box.pack_start(header_box, False, False, 0)
        
        # Try to load custom icon
        image = Gtk.Image()
        icon_loaded = False
        if icon_path:
            try:
                pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(icon_path, 48, 48, True)
                image.set_from_pixbuf(pixbuf)
                icon_loaded = True
            except Exception:
                pass
                
        if not icon_loaded:
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
        
        # Create a size group for homogeneous button widths
        button_size_group = Gtk.SizeGroup(mode=Gtk.SizeGroupMode.HORIZONTAL)
        
        # Row 1: Kill actions
        if p['pid'] != 0:
            kill_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            btn_kill = Gtk.Button(label="Kill Process (SIGTERM)")
            btn_kill.get_style_context().add_class("btn-kill")
            btn_kill.connect("clicked", lambda w: self.response(1))
            button_size_group.add_widget(btn_kill)
            
            btn_force = Gtk.Button(label="Force Kill (SIGKILL)")
            btn_force.get_style_context().add_class("btn-force")
            btn_force.connect("clicked", lambda w: self.response(2))
            button_size_group.add_widget(btn_force)
            
            kill_row.pack_start(btn_kill, True, True, 0)
            kill_row.pack_start(btn_force, True, True, 0)
            actions_box.pack_start(kill_row, False, False, 0)
            
            # Row 2: Copy actions
            utils_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            btn_copy_pid = Gtk.Button(label="Copy PID")
            btn_copy_pid.get_style_context().add_class("btn-secondary")
            btn_copy_pid.connect("clicked", lambda w: self.response(3))
            button_size_group.add_widget(btn_copy_pid)
            
            btn_copy_port = Gtk.Button(label="Copy Port")
            btn_copy_port.get_style_context().add_class("btn-secondary")
            btn_copy_port.connect("clicked", lambda w: self.response(4))
            button_size_group.add_widget(btn_copy_port)
            
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
        actions_box.pack_start(btn_close, True, True, 0)
        
        self.show_all()
