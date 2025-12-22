package tui

import (
	"bufio"
	"fmt"
	"os/exec"
	"strings"
	"time"
)

// FetchNetworkInfo fetches network connection info for a port
func FetchNetworkInfo(port int, pid int) []LogEntry {
	var entries []LogEntry

	// Get network connections using lsof
	networkEntries := fetchLsofInfo(port)
	entries = append(entries, networkEntries...)

	// Get process info
	processEntries := fetchProcessInfo(pid)
	entries = append(entries, processEntries...)

	// Sort by time (newest last)
	// Already in order from fetching

	return entries
}

// fetchLsofInfo gets network connection details using lsof
func fetchLsofInfo(port int) []LogEntry {
	var entries []LogEntry

	// Run lsof to get connection details
	cmd := exec.Command("lsof", "-i", fmt.Sprintf(":%d", port), "-n", "-P")
	output, err := cmd.Output()
	if err != nil {
		entries = append(entries, LogEntry{
			Time:    time.Now(),
			Source:  LogSourceNetwork,
			Content: fmt.Sprintf("Error running lsof: %v", err),
		})
		return entries
	}

	// Parse lsof output
	scanner := bufio.NewScanner(strings.NewReader(string(output)))
	lineNum := 0
	for scanner.Scan() {
		line := scanner.Text()
		lineNum++

		// Skip header
		if lineNum == 1 {
			continue
		}

		// Parse connection info
		fields := strings.Fields(line)
		if len(fields) >= 9 {
			state := fields[len(fields)-1]
			conn := fields[len(fields)-2]

			entry := LogEntry{
				Time:    time.Now(),
				Source:  LogSourceNetwork,
				Content: fmt.Sprintf("%s → %s", conn, state),
			}
			entries = append(entries, entry)
		}
	}

	// Add summary
	if len(entries) == 0 {
		entries = append(entries, LogEntry{
			Time:    time.Now(),
			Source:  LogSourceNetwork,
			Content: "No active connections",
		})
	}

	return entries
}

// fetchProcessInfo gets process details
func fetchProcessInfo(pid int) []LogEntry {
	var entries []LogEntry

	// Get process info using ps
	cmd := exec.Command("ps", "-p", fmt.Sprintf("%d", pid), "-o", "pid,ppid,user,stat,%cpu,%mem,etime,command")
	output, err := cmd.Output()
	if err != nil {
		return entries
	}

	scanner := bufio.NewScanner(strings.NewReader(string(output)))
	lineNum := 0
	for scanner.Scan() {
		line := scanner.Text()
		lineNum++

		if lineNum == 1 {
			continue // Skip header
		}

		fields := strings.Fields(line)
		if len(fields) >= 7 {
			entry := LogEntry{
				Time:    time.Now(),
				Source:  LogSourceStdout,
				Content: fmt.Sprintf("CPU: %s%% MEM: %s%% Uptime: %s", fields[4], fields[5], fields[6]),
			}
			entries = append(entries, entry)
		}
	}

	// Get open files count
	cmd = exec.Command("lsof", "-p", fmt.Sprintf("%d", pid))
	output, err = cmd.Output()
	if err == nil {
		lines := strings.Split(string(output), "\n")
		fileCount := len(lines) - 2 // Subtract header and empty line
		if fileCount < 0 {
			fileCount = 0
		}
		entries = append(entries, LogEntry{
			Time:    time.Now(),
			Source:  LogSourceStdout,
			Content: fmt.Sprintf("Open files: %d", fileCount),
		})
	}

	// Get network stats using netstat (macOS)
	cmd = exec.Command("netstat", "-anp", "tcp")
	output, _ = cmd.Output()
	scanner = bufio.NewScanner(strings.NewReader(string(output)))
	connCount := 0
	for scanner.Scan() {
		line := scanner.Text()
		if strings.Contains(line, fmt.Sprintf(".%d ", pid)) || strings.Contains(line, "LISTEN") {
			connCount++
		}
	}

	return entries
}

// StreamProcessLogs streams process stdout/stderr (limited functionality on macOS)
// Note: On macOS, direct stdout/stderr streaming is limited without special permissions
func StreamProcessLogs(pid int) <-chan LogEntry {
	ch := make(chan LogEntry)

	go func() {
		defer close(ch)

		// On macOS, we can't easily attach to another process's stdout/stderr
		// Instead, we provide periodic status updates

		for i := 0; i < 5; i++ {
			// Check if process is still running
			cmd := exec.Command("ps", "-p", fmt.Sprintf("%d", pid), "-o", "stat")
			output, err := cmd.Output()
			if err != nil {
				ch <- LogEntry{
					Time:    time.Now(),
					Source:  LogSourceStderr,
					Content: "Process no longer running",
				}
				return
			}

			lines := strings.Split(string(output), "\n")
			if len(lines) >= 2 {
				stat := strings.TrimSpace(lines[1])
				ch <- LogEntry{
					Time:    time.Now(),
					Source:  LogSourceStdout,
					Content: fmt.Sprintf("Process state: %s", stat),
				}
			}

			time.Sleep(2 * time.Second)
		}
	}()

	return ch
}
