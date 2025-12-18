//go:build windows

package scanner

import (
	"bufio"
	"bytes"
	"os/exec"
	"strconv"
	"strings"
)

type windowsScanner struct{}

func newPlatformScanner() Scanner {
	return &windowsScanner{}
}

func (s *windowsScanner) Scan() ([]Port, error) {
	// netstat -ano: all connections, numeric, owner PID
	cmd := exec.Command("netstat", "-ano", "-p", "TCP")
	output, err := cmd.Output()
	if err != nil {
		return nil, err
	}

	ports, err := parseNetstatOutput(output)
	if err != nil {
		return nil, err
	}

	// Get process names for PIDs
	return s.enrichWithProcessNames(ports)
}

func parseNetstatOutput(output []byte) ([]Port, error) {
	var ports []Port
	seen := make(map[string]bool)

	scanner := bufio.NewScanner(bytes.NewReader(output))

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if !strings.Contains(line, "LISTENING") {
			continue
		}

		fields := strings.Fields(line)
		if len(fields) < 5 {
			continue
		}

		// Proto Local Address Foreign Address State PID
		// TCP 0.0.0.0:3000 0.0.0.0:0 LISTENING 1234
		localAddr := fields[1]
		pid, _ := strconv.Atoi(fields[4])

		// Parse address:port
		lastColon := strings.LastIndex(localAddr, ":")
		if lastColon == -1 {
			continue
		}

		address := localAddr[:lastColon]
		port, _ := strconv.Atoi(localAddr[lastColon+1:])

		key := strconv.Itoa(port) + ":" + strconv.Itoa(pid)
		if seen[key] {
			continue
		}
		seen[key] = true

		ports = append(ports, Port{
			Port:    port,
			PID:     pid,
			Address: address,
		})
	}

	return ports, nil
}

func (s *windowsScanner) enrichWithProcessNames(ports []Port) ([]Port, error) {
	// Use tasklist to get process names
	cmd := exec.Command("tasklist", "/FO", "CSV", "/NH")
	output, err := cmd.Output()
	if err != nil {
		return ports, nil // Return without names if tasklist fails
	}

	pidToName := make(map[int]string)
	scanner := bufio.NewScanner(bytes.NewReader(output))
	for scanner.Scan() {
		line := scanner.Text()
		// CSV format: "process.exe","1234","Console","1","10,000 K"
		fields := strings.Split(line, ",")
		if len(fields) < 2 {
			continue
		}
		name := strings.Trim(fields[0], "\"")
		pid, _ := strconv.Atoi(strings.Trim(fields[1], "\""))
		pidToName[pid] = name
	}

	for i := range ports {
		if name, ok := pidToName[ports[i].PID]; ok {
			ports[i].Process = name
		}
	}

	return ports, nil
}

func (s *windowsScanner) Kill(pid int, force bool) error {
	args := []string{"/PID", strconv.Itoa(pid)}
	if force {
		args = append(args, "/F")
	}

	cmd := exec.Command("taskkill", args...)
	return cmd.Run()
}
