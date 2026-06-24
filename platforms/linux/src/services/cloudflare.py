import os
import re
import shutil
import subprocess
import threading
import time

class CloudflareTunnel:
    def __init__(self, port):
        self.port = port
        self.url = None
        self.status = "starting"  # starting, active, error, stopping
        self.error = None
        self.process = None
        self.thread = None

    def start(self):
        cloudflared_bin = shutil.which("cloudflared")
        if not cloudflared_bin:
            # Check common paths
            for path in ["/usr/local/bin/cloudflared", "/usr/bin/cloudflared", "/opt/bin/cloudflared"]:
                if os.path.exists(path):
                    cloudflared_bin = path
                    break
        
        if not cloudflared_bin:
            self.status = "error"
            self.error = "cloudflared binary not found in PATH or standard locations."
            return False

        try:
            # Start cloudflared quick tunnel
            self.process = subprocess.Popen(
                [cloudflared_bin, "tunnel", "--url", f"localhost:{self.port}"],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1
            )
            
            # Start background thread to read output
            self.thread = threading.Thread(target=self._read_output, daemon=True)
            self.thread.start()
            return True
        except Exception as e:
            self.status = "error"
            self.error = str(e)
            return False

    def _read_output(self):
        pattern = r"https://[a-zA-Z0-9-]+\.trycloudflare\.com"
        while self.process and self.process.poll() is None:
            line = self.process.stdout.readline()
            if not line:
                break
            
            # Parse URL
            match = re.search(pattern, line)
            if match:
                self.url = match.group(0)
                self.status = "active"
            
            # Parse error
            line_lower = line.lower()
            if "error" in line_lower or "failed" in line_lower:
                if self.status != "active":
                    self.status = "error"
                    self.error = line.strip()

        if self.process and self.process.poll() is not None:
            if self.status != "error":
                self.status = "error"
                self.error = f"Process exited with code {self.process.returncode}"

    def stop(self):
        self.status = "stopping"
        if self.process:
            try:
                self.process.terminate()
                # Wait up to 1 second
                for _ in range(10):
                    if self.process.poll() is not None:
                        break
                    time.sleep(0.1)
                
                if self.process.poll() is None:
                    self.process.kill()
            except Exception:
                pass
        self.status = "stopped"

class CloudflareService:
    def __init__(self):
        self.active_tunnels = {}  # port -> CloudflareTunnel

    @property
    def is_installed(self):
        return shutil.which("cloudflared") is not None or any(
            os.path.exists(p) for p in ["/usr/local/bin/cloudflared", "/usr/bin/cloudflared"]
        )

    def start_tunnel(self, port):
        if port in self.active_tunnels:
            tunnel = self.active_tunnels[port]
            if tunnel.status != "error":
                return tunnel
        
        tunnel = CloudflareTunnel(port)
        self.active_tunnels[port] = tunnel
        tunnel.start()
        return tunnel

    def stop_tunnel(self, port):
        if port in self.active_tunnels:
            self.active_tunnels[port].stop()
            del self.active_tunnels[port]

    def stop_all(self):
        for port in list(self.active_tunnels.keys()):
            self.stop_tunnel(port)

    def get_tunnel(self, port):
        return self.active_tunnels.get(port)

    def scan_running_tunnels_from_ps(self):
        """
        Scan the operating system process list to see if any cloudflared tunnels
        were launched externally.
        """
        external_tunnels = []
        try:
            # Query running processes matching cloudflared
            result = subprocess.run(
                ["ps", "-aux"],
                capture_output=True,
                text=True
            )
            if result.returncode != 0:
                return external_tunnels

            # Pattern to parse cloudflared tunnel command
            # e.g., cloudflared tunnel --url localhost:3000
            for line in result.stdout.splitlines():
                if "cloudflared" in line and "tunnel" in line and "--url" in line:
                    # Find local port
                    port_match = re.search(r"localhost:(\d+)", line)
                    if port_match:
                        port = int(port_match.group(1))
                        # Get PID
                        parts = line.split()
                        if len(parts) >= 2:
                            pid = int(parts[1])
                            # Check if we already manage this port. If not, add as external
                            if port not in self.active_tunnels:
                                external_tunnels.append({
                                    "port": port,
                                    "pid": pid,
                                    "status": "active",
                                    "url": "External (check terminal)",
                                    "command": " ".join(parts[10:])
                                })
        except Exception as e:
            print(f"Error scanning cloudflared processes: {e}")
        
        return external_tunnels

# Global service instance
cloudflare_service = CloudflareService()
