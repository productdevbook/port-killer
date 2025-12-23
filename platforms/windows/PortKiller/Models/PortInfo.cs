using System;
using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace PortKiller.Models;

/// <summary>
/// Information about a network port and its associated process.
/// Represents a listening TCP port with details about the process that owns it.
/// </summary>
public class PortInfo : INotifyPropertyChanged
{
    private bool _isConfirmingKill;
    private bool _isKilling;

    public event PropertyChangedEventHandler? PropertyChanged;

    /// <summary>
    /// Unique identifier for this port info instance
    /// </summary>
    public Guid Id { get; init; } = Guid.NewGuid();

    /// <summary>
    /// The port number (e.g., 3000, 8080)
    /// </summary>
    public int Port { get; init; }

    /// <summary>
    /// Process ID of the process using this port
    /// </summary>
    public int Pid { get; init; }

    /// <summary>
    /// Name of the process using this port
    /// </summary>
    public string ProcessName { get; init; } = string.Empty;

    /// <summary>
    /// Network address the port is bound to (e.g., "0.0.0.0", "127.0.0.1")
    /// </summary>
    public string Address { get; init; } = string.Empty;

    /// <summary>
    /// Username of the process owner
    /// </summary>
    public string User { get; init; } = string.Empty;

    /// <summary>
    /// Full command line that started the process
    /// </summary>
    public string Command { get; init; } = string.Empty;

    /// <summary>
    /// Whether this port is currently active/listening
    /// </summary>
    public bool IsActive { get; init; }

    /// <summary>
    /// UI State: Showing confirmation buttons
    /// </summary>
    public bool IsConfirmingKill
    {
        get => _isConfirmingKill;
        set
        {
            if (_isConfirmingKill != value)
            {
                _isConfirmingKill = value;
                OnPropertyChanged();
            }
        }
    }

    /// <summary>
    /// UI State: Process is being killed (spinner)
    /// </summary>
    public bool IsKilling
    {
        get => _isKilling;
        set
        {
            if (_isKilling != value)
            {
                _isKilling = value;
                OnPropertyChanged();
            }
        }
    }

    /// <summary>
    /// Formatted port number for display (e.g., ":3000")
    /// </summary>
    public string DisplayPort => $":{Port}";

    /// <summary>
    /// Detected process type based on the process name
    /// </summary>
    public ProcessType ProcessType => ProcessTypeExtensions.Detect(ProcessName);

    /// <summary>
    /// Create an inactive placeholder for a favorited/watched port
    /// </summary>
    public static PortInfo Inactive(int port) => new()
    {
        Port = port,
        Pid = 0,
        ProcessName = "Not running",
        Address = "-",
        User = "-",
        Command = string.Empty,
        IsActive = false
    };

    /// <summary>
    /// Create an active port from scan results
    /// </summary>
    public static PortInfo Active(
        int port,
        int pid,
        string processName,
        string address,
        string user,
        string command) => new()
    {
        Port = port,
        Pid = pid,
        ProcessName = processName,
        Address = address,
        User = user,
        Command = command,
        IsActive = true
    };

    protected virtual void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
