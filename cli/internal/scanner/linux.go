//go:build linux

package scanner

import (
	"bufio"
	"bytes"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
	"syscall"
	"time"
)

type linuxScanner struct{}

func newPlatformScanner() Scanner {
	return &linuxScanner{}
}

func (s *linuxScanner) Scan() ([]Port, error) {
	// Try lsof first (same as macOS)
	cmd := exec.Command("lsof", "-iTCP", "-sTCP:LISTEN", "-P", "-n")
	output, err := cmd.Output()
	if err != nil {
		// lsof might not be installed, try ss
		return s.scanWithSS()
	}

	return parseLsofOutputLinux(output)
}

func (s *linuxScanner) scanWithSS() ([]Port, error) {
	// ss -tlnp: TCP, listening, numeric, show process
	cmd := exec.Command("ss", "-tlnp")
	output, err := cmd.Output()
	if err != nil {
		return nil, err
	}

	return parseSSOutput(output)
}

func parseLsofOutputLinux(output []byte) ([]Port, error) {
	var ports []Port
	seen := make(map[string]bool)

	scanner := bufio.NewScanner(bytes.NewReader(output))
	// Skip header
	scanner.Scan()

	addrRegex := regexp.MustCompile(`^(\*|\[?[^\]]+\]?):(\d+)$`)

	for scanner.Scan() {
		line := scanner.Text()
		fields := strings.Fields(line)
		if len(fields) < 9 {
			continue
		}

		process := fields[0]
		pid, _ := strconv.Atoi(fields[1])
		user := fields[2]
		name := fields[len(fields)-1]

		matches := addrRegex.FindStringSubmatch(name)
		if matches == nil {
			continue
		}

		address := matches[1]
		port, _ := strconv.Atoi(matches[2])

		key := strconv.Itoa(port) + ":" + strconv.Itoa(pid)
		if seen[key] {
			continue
		}
		seen[key] = true

		ports = append(ports, Port{
			Port:    port,
			PID:     pid,
			Process: process,
			User:    user,
			Address: address,
		})
	}

	return ports, nil
}

func parseSSOutput(output []byte) ([]Port, error) {
	var ports []Port
	seen := make(map[string]bool)

	scanner := bufio.NewScanner(bytes.NewReader(output))
	// Skip header
	scanner.Scan()

	// ss output: State Recv-Q Send-Q Local Address:Port Peer Address:Port Process
	// Example: LISTEN 0 128 0.0.0.0:22 0.0.0.0:* users:(("sshd",pid=1234,fd=3))
	pidRegex := regexp.MustCompile(`pid=(\d+)`)
	procRegex := regexp.MustCompile(`"([^"]+)"`)

	for scanner.Scan() {
		line := scanner.Text()
		fields := strings.Fields(line)
		if len(fields) < 5 {
			continue
		}

		// Parse local address:port
		localAddr := fields[3]
		lastColon := strings.LastIndex(localAddr, ":")
		if lastColon == -1 {
			continue
		}

		address := localAddr[:lastColon]
		port, _ := strconv.Atoi(localAddr[lastColon+1:])

		// Parse process info
		var pid int
		var process string
		if len(fields) >= 6 {
			procInfo := fields[5]
			if matches := pidRegex.FindStringSubmatch(procInfo); matches != nil {
				pid, _ = strconv.Atoi(matches[1])
			}
			if matches := procRegex.FindStringSubmatch(procInfo); matches != nil {
				process = matches[1]
			}
		}

		key := strconv.Itoa(port) + ":" + strconv.Itoa(pid)
		if seen[key] {
			continue
		}
		seen[key] = true

		ports = append(ports, Port{
			Port:    port,
			PID:     pid,
			Process: process,
			User:    "", // ss doesn't show user by default
			Address: address,
		})
	}

	return ports, nil
}

func (s *linuxScanner) Kill(pid int, force bool) error {
	signal := syscall.SIGTERM
	if force {
		signal = syscall.SIGKILL
	}

	if err := syscall.Kill(pid, signal); err != nil {
		return err
	}

	if !force {
		time.Sleep(500 * time.Millisecond)
		if err := syscall.Kill(pid, 0); err == nil {
			return syscall.Kill(pid, syscall.SIGKILL)
		}
	}

	return nil
}
