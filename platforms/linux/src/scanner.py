import subprocess

class PortScanner:
    @staticmethod
    def scan_ports():
        ports = []
        try:
            # Try ss first (more complete on Linux as it shows all ports, even of other users)
            result = subprocess.run(
                ["ss", "-tlnp"],
                capture_output=True,
                text=True,
                check=True
            )
            ports = PortScanner.parse_ss_output(result.stdout)
        except (subprocess.SubprocessError, FileNotFoundError):
            # Fall back to lsof
            try:
                result = subprocess.run(
                    ["lsof", "-iTCP", "-sTCP:LISTEN", "-P", "-n"],
                    capture_output=True,
                    text=True,
                    check=True
                )
                ports = PortScanner.parse_lsof_output(result.stdout)
            except (subprocess.SubprocessError, FileNotFoundError):
                pass
        return ports

    @staticmethod
    def parse_lsof_output(output):
        ports = []
        seen = set()
        lines = output.strip().split('\n')
        if len(lines) <= 1:
            return ports
        
        commands = PortScanner.get_process_commands()

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
            
            addr_port = PortScanner.parse_address(address_str)
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

    @staticmethod
    def parse_ss_output(output):
        ports = []
        seen = set()
        lines = output.strip().split('\n')
        
        commands = PortScanner.get_process_commands()

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
                users = PortScanner.parse_ss_users(proc_col)
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

    @staticmethod
    def parse_ss_users(users_str):
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

    @staticmethod
    def parse_address(address_str):
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

    @staticmethod
    def get_process_commands():
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

    @staticmethod
    def kill_process(pid, force=False):
        try:
            sig = "-9" if force else "-15"
            subprocess.run(["kill", sig, str(pid)], check=True)
            return True
        except subprocess.SubprocessError:
            return False
