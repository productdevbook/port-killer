package scanner

// Port represents a listening port and its associated process
type Port struct {
	Port    int    `json:"port"`
	PID     int    `json:"pid"`
	Process string `json:"process"`
	User    string `json:"user"`
	Address string `json:"address"`
	Command string `json:"command,omitempty"`
}

// Scanner interface for platform-specific implementations
type Scanner interface {
	Scan() ([]Port, error)
	Kill(pid int, force bool) error
}

// New returns a platform-specific scanner
func New() Scanner {
	return newPlatformScanner()
}
