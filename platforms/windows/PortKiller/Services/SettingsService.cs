using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using PortKiller.Models;

namespace PortKiller.Services;

/// <summary>
/// Service for persisting and loading application settings.
/// Stores data in AppData\Local\PortKiller
/// </summary>
public class SettingsService
{
    private const string AppName = "PortKiller";
    private const string SettingsFileName = "settings.json";
    private readonly string _settingsPath;

    public SettingsService()
    {
        var appDataPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            AppName);
        
        Directory.CreateDirectory(appDataPath);
        _settingsPath = Path.Combine(appDataPath, SettingsFileName);
    }

    private class SettingsData
    {
        public List<int>? Favorites { get; set; }
        public List<WatchedPort>? WatchedPorts { get; set; }
        public int RefreshInterval { get; set; } = 5;
        public bool AutoStart { get; set; }
        public bool ShowNotifications { get; set; } = true;
    }

    private SettingsData LoadSettingsData()
    {
        try
        {
            if (File.Exists(_settingsPath))
            {
                var json = File.ReadAllText(_settingsPath);
                return JsonSerializer.Deserialize<SettingsData>(json) ?? new SettingsData();
            }
        }
        catch
        {
            // If load fails, return defaults
        }
        return new SettingsData();
    }

    private void SaveSettingsData(SettingsData data)
    {
        try
        {
            var json = JsonSerializer.Serialize(data, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(_settingsPath, json);
        }
        catch
        {
            // Silently fail - settings save is not critical
        }
    }

    // Favorites
    public HashSet<int> GetFavorites()
    {
        var data = LoadSettingsData();
        return data.Favorites != null ? new HashSet<int>(data.Favorites) : new HashSet<int>();
    }

    public void SaveFavorites(HashSet<int> favorites)
    {
        var data = LoadSettingsData();
        data.Favorites = favorites.ToList();
        SaveSettingsData(data);
    }

    // Watched Ports
    public List<WatchedPort> GetWatchedPorts()
    {
        var data = LoadSettingsData();
        return data.WatchedPorts ?? new List<WatchedPort>();
    }

    public void SaveWatchedPorts(List<WatchedPort> watchedPorts)
    {
        var data = LoadSettingsData();
        data.WatchedPorts = watchedPorts;
        SaveSettingsData(data);
    }

    // Refresh Interval
    public int GetRefreshInterval()
    {
        var data = LoadSettingsData();
        return data.RefreshInterval;
    }

    public void SaveRefreshInterval(int seconds)
    {
        var data = LoadSettingsData();
        data.RefreshInterval = seconds;
        SaveSettingsData(data);
    }

    // Auto Start
    public bool GetAutoStart()
    {
        var data = LoadSettingsData();
        return data.AutoStart;
    }

    public void SaveAutoStart(bool autoStart)
    {
        var data = LoadSettingsData();
        data.AutoStart = autoStart;
        SaveSettingsData(data);
    }

    // Show Notifications
    public bool GetShowNotifications()
    {
        var data = LoadSettingsData();
        return data.ShowNotifications;
    }

    public void SaveShowNotifications(bool show)
    {
        var data = LoadSettingsData();
        data.ShowNotifications = show;
        SaveSettingsData(data);
    }

    // Clear all settings
    public void ClearAllSettings()
    {
        try
        {
            if (File.Exists(_settingsPath))
            {
                File.Delete(_settingsPath);
            }
        }
        catch
        {
            // Ignore errors
        }
    }
}
