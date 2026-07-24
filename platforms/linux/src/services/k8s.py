import os
import re
import shutil
import signal
import subprocess

# kubectl flags whose value is a separate following token
VALUE_FLAGS = ("-n", "--namespace", "--kubeconfig", "--context", "--address")


class K8sPortForward:
    def __init__(self, pid, namespace, resource, local_port, remote_port, raw_cmd):
        self.pid = pid
        self.namespace = namespace
        self.resource = resource
        self.local_port = local_port
        self.remote_port = remote_port
        self.raw_cmd = raw_cmd

class K8sService:
    @property
    def is_installed(self):
        return shutil.which("kubectl") is not None

    def scan_active_forwards(self):
        """
        Scans running processes to find active kubectl port-forward sessions.
        Returns a list of K8sPortForward objects.
        """
        forwards = []
        if not self.is_installed:
            return forwards

        try:
            # Query running processes matching kubectl
            result = subprocess.run(
                ["ps", "-axo", "pid,command"],
                capture_output=True,
                text=True
            )
            if result.returncode != 0:
                return forwards

            # Parse output
            for line in result.stdout.splitlines():
                trimmed = line.strip()
                if not trimmed or "ps -axo" in trimmed:
                    continue
                
                parts = trimmed.split(None, 1)
                if len(parts) < 2:
                    continue
                
                pid_str, cmd = parts[0], parts[1]
                if "kubectl" in cmd and "port-forward" in cmd:
                    try:
                        pid = int(pid_str)
                        fw = self._parse_port_forward_cmd(pid, cmd)
                        if fw:
                            forwards.append(fw)
                    except ValueError:
                        continue
        except Exception as e:
            print(f"Error scanning K8s port-forwards: {e}")

        return forwards

    def _parse_port_forward_cmd(self, pid, cmd):
        """
        Parses a kubectl port-forward command line.
        e.g., "kubectl port-forward svc/my-service 8080:80 -n dev"
        """
        # Exclude grep, self-processes
        if "grep" in cmd:
            return None

        # Parse Namespace
        namespace = "default"
        ns_match = re.search(r"(?:-n|--namespace)(?:=|\s+)([^\s]+)", cmd)
        if ns_match:
            namespace = ns_match.group(1)

        # Parse Local and Remote Port
        # E.g. "8080:80" or "8080" (if target port is same) or " :80" (random local port)
        local_port = 0
        remote_port = 0
        port_match = re.search(r"(\d+):(\d+)", cmd)
        if port_match:
            local_port = int(port_match.group(1))
            remote_port = int(port_match.group(2))
        else:
            # Maybe single port mapping, e.g. "8080"
            single_port_match = re.search(r"\s+(\d+)(?:\s+|$)", cmd)
            if single_port_match:
                local_port = int(single_port_match.group(1))
                remote_port = local_port

        # Parse Resource Name
        # E.g. "svc/my-service", "pod/my-pod", "deployment/my-dep", or just "my-pod"
        resource = "Unknown Resource"
        cmd_tokens = cmd.split()
        if "port-forward" in cmd_tokens:
            start = cmd_tokens.index("port-forward") + 1
            for j in range(start, len(cmd_tokens)):
                t = cmd_tokens[j]
                # Skip flags themselves
                if t.startswith("-"):
                    continue
                # Skip the value of a flag that takes a separate argument
                if cmd_tokens[j - 1] in VALUE_FLAGS:
                    continue
                # Skip port mappings ("8080:80") and bare port numbers
                if ":" in t or t.isdigit():
                    continue
                resource = t
                break

        return K8sPortForward(pid, namespace, resource, local_port, remote_port, cmd)

    def stop_port_forward(self, pid):
        """
        Kill a specific port forward process by PID.
        """
        if pid <= 0:
            return False
        try:
            os.kill(pid, signal.SIGTERM)
            return True
        except ProcessLookupError:
            # Already gone; treat as success
            return True
        except (PermissionError, OSError) as e:
            print(f"Error stopping port-forward {pid}: {e}")
            return False

    def kill_all(self):
        """
        Kill all active kubectl port-forward processes.

        Only PIDs identified by scan_active_forwards() are signalled. A broad
        `pkill -f "kubectl.*port-forward"` would match any process whose command
        line merely contains that text (an editor, a shell script, a grep) and
        kill it too.
        """
        ok = True
        for fw in self.scan_active_forwards():
            if not self.stop_port_forward(fw.pid):
                ok = False
        return ok

# Global service instance
k8s_service = K8sService()
