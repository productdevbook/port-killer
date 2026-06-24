import os
import re
import shutil
import subprocess

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
        # Find arguments that are not flags and not port mappings
        cmd_tokens = cmd.split()
        for i, token in enumerate(cmd_tokens):
            if token == "port-forward":
                # The resource is typically the next non-flag argument
                for j in range(i + 1, len(cmd_tokens)):
                    t = cmd_tokens[j]
                    if t.startswith("-"):
                        # If it's a flag that takes an argument, skip both
                        if t in ["-n", "--namespace", "--kubeconfig", "--context", "--address"]:
                            continue
                        continue
                    # Skip the previous token if it was a flag that takes an argument
                    if j > 0 and cmd_tokens[j - 1] in ["-n", "--namespace", "--kubeconfig", "--context", "--address"]:
                        continue
                    # Skip port mappings
                    if ":" in t or t.isdigit():
                        continue
                    resource = t
                    break
                break

        return K8sPortForward(pid, namespace, resource, local_port, remote_port, cmd)

    def stop_port_forward(self, pid):
        """
        Kill a specific port forward process by PID.
        """
        try:
            subprocess.run(["kill", "-9", str(pid)], check=True)
            return True
        except subprocess.SubprocessError:
            return False

    def kill_all(self):
        """
        Kill all active kubectl port-forward processes.
        """
        try:
            subprocess.run(["pkill", "-9", "-f", "kubectl.*port-forward"], check=True)
            return True
        except subprocess.SubprocessError:
            return False

# Global service instance
k8s_service = K8sService()
