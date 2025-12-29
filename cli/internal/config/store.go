package config

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
)

const (
	configDir  = ".portkiller"
	configFile = "config.json"
)

// SharedConfig represents the shared configuration between CLI and GUI
type SharedConfig struct {
	Favorites    []int         `json:"favorites"`
	WatchedPorts []WatchedPort `json:"watchedPorts"`
}

type sharedStore struct {
	path string
	mu   sync.RWMutex
}

// NewSharedStore creates a new shared config store at ~/.portkiller/config.json
func NewSharedStore() (Store, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil, err
	}

	dir := filepath.Join(home, configDir)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return nil, err
	}

	return &sharedStore{
		path: filepath.Join(dir, configFile),
	}, nil
}

func (s *sharedStore) Load() (*Config, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

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

	var shared SharedConfig
	if err := json.Unmarshal(data, &shared); err != nil {
		return nil, err
	}

	cfg.Favorites = shared.Favorites
	cfg.WatchedPorts = shared.WatchedPorts

	return cfg, nil
}

func (s *sharedStore) Save(cfg *Config) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	shared := SharedConfig{
		Favorites:    cfg.Favorites,
		WatchedPorts: cfg.WatchedPorts,
	}

	// Ensure non-nil slices for clean JSON
	if shared.Favorites == nil {
		shared.Favorites = []int{}
	}
	if shared.WatchedPorts == nil {
		shared.WatchedPorts = []WatchedPort{}
	}

	data, err := json.MarshalIndent(shared, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(s.path, data, 0644)
}
