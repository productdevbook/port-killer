//go:build darwin

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

type darwinScanner struct{}

func newPlatformScanner() Scanner {
	return &darwinScanner{}
}

func (s *darwinScanner) Scan() ([]Port, error) {
	// Run lsof to get listening TCP ports
	cmd := exec.Command("lsof", "-iTCP", "-sTCP:LISTEN", "-P", "-n", "+c", "0")
	output, err := cmd.Output()
	if err != nil {
		// lsof returns exit code 1 when no results, that's ok
		if exitErr, ok := err.(*exec.ExitError); ok && exitErr.ExitCode() == 1 {
			return []Port{}, nil
		}
		return nil, err
	}

	return parseLsofOutput(output)
}

func parseLsofOutput(output []byte) ([]Port, error) {
	var ports []Port
	seen := make(map[string]bool)

	scanner := bufio.NewScanner(bytes.NewReader(output))
	// Skip header line
	if scanner.Scan() {
		// Header skipped
	}

	// Regex to parse the NAME column (e.g., "127.0.0.1:3000" or "*:8080" or "[::1]:3000")
	// NAME can end with " (LISTEN)" which we need to handle
	addrRegex := regexp.MustCompile(`^(\*|\[?[^\]]+\]?):(\d+)`)

	for scanner.Scan() {
		line := scanner.Text()
		fields := strings.Fields(line)
		if len(fields) < 9 {
			continue
		}

		// lsof output: COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME [(LISTEN)]
		process := fields[0]
		pid, err := strconv.Atoi(fields[1])
		if err != nil {
			continue
		}
		user := fields[2]
		// NAME is at index 8 (9th field), not the last field (which could be "(LISTEN)")
		name := fields[8]

		// Parse address and port from NAME
		matches := addrRegex.FindStringSubmatch(name)
		if matches == nil {
			continue
		}

		address := matches[1]
		port, err := strconv.Atoi(matches[2])
		if err != nil {
			continue
		}

		// Deduplicate by port+pid
		key := strconv.Itoa(port) + ":" + strconv.Itoa(pid)
		if seen[key] {
			continue
		}
		seen[key] = true

		// Unescape process name (e.g., "Code\x20Helper" -> "Code Helper")
		process = unescapeProcessName(process)

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

func unescapeProcessName(name string) string {
	// Replace \x20 with space, etc.
	result := name
	result = strings.ReplaceAll(result, "\\x20", " ")
	result = strings.ReplaceAll(result, "\\x2d", "-")
	return result
}

func (s *darwinScanner) Kill(pid int, force bool) error {
	signal := syscall.SIGTERM
	if force {
		signal = syscall.SIGKILL
	}

	if err := syscall.Kill(pid, signal); err != nil {
		return err
	}

	// If not force, wait a bit and check if process is still running
	if !force {
		time.Sleep(500 * time.Millisecond)
		// Check if process still exists
		if err := syscall.Kill(pid, 0); err == nil {
			// Process still running, force kill
			return syscall.Kill(pid, syscall.SIGKILL)
		}
	}

	return nil
}
