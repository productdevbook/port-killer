import os
import json

CONFIG_DIR = os.path.expanduser("~/.config/port-killer")
CONFIG_FILE = os.path.join(CONFIG_DIR, "config.json")

DEFAULT_CONFIG = {
    "use_tree_view": True,
    "hide_system_processes": True,
    "favorites": []
}

class AppConfig:
    def __init__(self):
        self.data = DEFAULT_CONFIG.copy()
        self.load()

    def load(self):
        if os.path.exists(CONFIG_FILE):
            try:
                with open(CONFIG_FILE, "r") as f:
                    self.data.update(json.load(f))
            except Exception as e:
                print(f"Error loading config: {e}")

    def save(self):
        try:
            os.makedirs(CONFIG_DIR, exist_ok=True)
            with open(CONFIG_FILE, "w") as f:
                json.dump(self.data, f, indent=4)
        except Exception as e:
            print(f"Error saving config: {e}")

    @property
    def use_tree_view(self):
        return self.data.get("use_tree_view", True)

    @use_tree_view.setter
    def use_tree_view(self, val):
        self.data["use_tree_view"] = bool(val)
        self.save()

    @property
    def hide_system_processes(self):
        return self.data.get("hide_system_processes", True)

    @hide_system_processes.setter
    def hide_system_processes(self, val):
        self.data["hide_system_processes"] = bool(val)
        self.save()

    @property
    def favorites(self):
        return self.data.get("favorites", [])

    def add_favorite(self, port):
        if port not in self.data["favorites"]:
            self.data["favorites"].append(port)
            self.save()

    def remove_favorite(self, port):
        if port in self.data["favorites"]:
            self.data["favorites"].remove(port)
            self.save()

    def is_favorite(self, port):
        return port in self.data["favorites"]

# Global config instance
config = AppConfig()

def get_icon_path():
    import sys
    src_dir = os.path.dirname(os.path.abspath(__file__)) # /path/to/src
    parent_dir = os.path.dirname(src_dir) # /path/to
    
    candidates = [
        os.path.join(parent_dir, "AppIcon.svg"),
        os.path.join(src_dir, "AppIcon.svg"),
        os.path.join(os.path.dirname(os.path.abspath(sys.argv[0])), "AppIcon.svg"),
    ]
    for p in candidates:
        if os.path.exists(p):
            return p
    return None

