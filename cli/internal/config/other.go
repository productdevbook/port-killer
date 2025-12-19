//go:build !darwin

package config

import (
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
)

type jsonStore struct {
	path string
}

func newPlatformStore() Store {
	return &jsonStore{
		path: getConfigPath(),
	}
}

func getConfigPath() string {
	var configDir string

	switch runtime.GOOS {
	case "windows":
		configDir = os.Getenv("APPDATA")
		if configDir == "" {
			configDir = filepath.Join(os.Getenv("USERPROFILE"), "AppData", "Roaming")
		}
	default: // linux and others
		configDir = os.Getenv("XDG_CONFIG_HOME")
		if configDir == "" {
			home, _ := os.UserHomeDir()
			configDir = filepath.Join(home, ".config")
		}
	}

	return filepath.Join(configDir, "portkiller", "config.json")
}

func (s *jsonStore) Load() (*Config, error) {
	cfg := &Config{
		Favorites:    []int{},
		WatchedPorts: []WatchedPort{},
	}

	data, err := os.ReadFile(s.path)
	if err != nil {
		if os.IsNotExist(err) {
			return cfg, nil
		}
		return nil, err
	}

	if err := json.Unmarshal(data, cfg); err != nil {
		return nil, err
	}

	return cfg, nil
}

func (s *jsonStore) Save(cfg *Config) error {
	// Ensure directory exists
	dir := filepath.Dir(s.path)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}

	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(s.path, data, 0644)
}

// loadFromPlist is a no-op on non-darwin platforms
func loadFromPlist() *Config {
	return nil
}
