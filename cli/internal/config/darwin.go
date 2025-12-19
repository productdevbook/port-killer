//go:build darwin

package config

import (
	"encoding/json"
	"os"
	"path/filepath"

	"howett.net/plist"
)

const plistPath = "Library/Preferences/com.portkiller.app.plist"

// plistConfig represents the structure of the GUI's plist file
type plistConfig struct {
	FavoritesV2  []int         `plist:"favoritesV2"`
	WatchedPorts []interface{} `plist:"watchedPorts"`
}

// loadFromPlist migrates config from plist to shared JSON store
func loadFromPlist() *Config {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil
	}

	path := filepath.Join(home, plistPath)
	data, err := os.ReadFile(path)
	if err != nil {
		return nil
	}

	var plistCfg plistConfig
	if _, err := plist.Unmarshal(data, &plistCfg); err != nil {
		return nil
	}

	cfg := &Config{
		Favorites:    plistCfg.FavoritesV2,
		WatchedPorts: []WatchedPort{},
	}

	// Parse watched ports
	for _, item := range plistCfg.WatchedPorts {
		var wp WatchedPort
		switch v := item.(type) {
		case map[string]interface{}:
			if id, ok := v["id"].(string); ok {
				wp.ID = id
			}
			if port, ok := v["port"].(uint64); ok {
				wp.Port = int(port)
			} else if port, ok := v["port"].(int64); ok {
				wp.Port = int(port)
			}
			if notifyStart, ok := v["notifyOnStart"].(bool); ok {
				wp.NotifyOnStart = notifyStart
			}
			if notifyStop, ok := v["notifyOnStop"].(bool); ok {
				wp.NotifyOnStop = notifyStop
			}
			if wp.Port > 0 {
				cfg.WatchedPorts = append(cfg.WatchedPorts, wp)
			}
		case string:
			if err := json.Unmarshal([]byte(v), &wp); err == nil {
				cfg.WatchedPorts = append(cfg.WatchedPorts, wp)
			}
		}
	}

	return cfg
}
