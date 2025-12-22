package config

import (
	"crypto/rand"
	"fmt"
)

// WatchedPort represents a port being watched for state changes
type WatchedPort struct {
	ID            string `json:"id" plist:"id"`
	Port          int    `json:"port" plist:"port"`
	NotifyOnStart bool   `json:"notifyOnStart" plist:"notifyOnStart"`
	NotifyOnStop  bool   `json:"notifyOnStop" plist:"notifyOnStop"`
}

// Config holds CLI configuration synced with GUI
type Config struct {
	Favorites    []int         `json:"favorites" plist:"favoritesV2"`
	WatchedPorts []WatchedPort `json:"watchedPorts" plist:"watchedPorts"`
}

// Store interface for config persistence
type Store interface {
	Load() (*Config, error)
	Save(cfg *Config) error
}

// NewStore returns the shared config store
func NewStore() Store {
	store, err := NewSharedStore()
	if err != nil {
		// Fallback: return a store that will return empty config
		return &fallbackStore{}
	}

	// Migrate from plist if shared config is empty
	cfg, _ := store.Load()
	if len(cfg.Favorites) == 0 && len(cfg.WatchedPorts) == 0 {
		if plistCfg := loadFromPlist(); plistCfg != nil {
			if len(plistCfg.Favorites) > 0 || len(plistCfg.WatchedPorts) > 0 {
				store.Save(plistCfg)
			}
		}
	}

	return store
}

type fallbackStore struct{}

func (f *fallbackStore) Load() (*Config, error) {
	return &Config{Favorites: []int{}, WatchedPorts: []WatchedPort{}}, nil
}

func (f *fallbackStore) Save(cfg *Config) error {
	return nil
}

// IsFavorite checks if a port is in favorites
func (c *Config) IsFavorite(port int) bool {
	for _, p := range c.Favorites {
		if p == port {
			return true
		}
	}
	return false
}

// IsWatched checks if a port is being watched
func (c *Config) IsWatched(port int) bool {
	for _, w := range c.WatchedPorts {
		if w.Port == port {
			return true
		}
	}
	return false
}

// AddFavorite adds a port to favorites
func (c *Config) AddFavorite(port int) {
	if !c.IsFavorite(port) {
		c.Favorites = append(c.Favorites, port)
	}
}

// RemoveFavorite removes a port from favorites
func (c *Config) RemoveFavorite(port int) {
	var filtered []int
	for _, p := range c.Favorites {
		if p != port {
			filtered = append(filtered, p)
		}
	}
	c.Favorites = filtered
}

// AddWatched adds a port to watched list
func (c *Config) AddWatched(port int) {
	if !c.IsWatched(port) {
		c.WatchedPorts = append(c.WatchedPorts, WatchedPort{
			ID:            generateID(),
			Port:          port,
			NotifyOnStart: true,
			NotifyOnStop:  true,
		})
	}
}

// RemoveWatched removes a port from watched list
func (c *Config) RemoveWatched(port int) {
	var filtered []WatchedPort
	for _, w := range c.WatchedPorts {
		if w.Port != port {
			filtered = append(filtered, w)
		}
	}
	c.WatchedPorts = filtered
}

// generateID creates a UUID v4 compatible with macOS app
func generateID() string {
	uuid := make([]byte, 16)
	rand.Read(uuid)
	// Set version 4 and variant bits
	uuid[6] = (uuid[6] & 0x0f) | 0x40
	uuid[8] = (uuid[8] & 0x3f) | 0x80
	return fmt.Sprintf("%08X-%04X-%04X-%04X-%012X",
		uuid[0:4], uuid[4:6], uuid[6:8], uuid[8:10], uuid[10:16])
}
