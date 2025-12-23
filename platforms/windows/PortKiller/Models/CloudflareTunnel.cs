using System;
using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace PortKiller.Models;

/// <summary>
/// Status of a Cloudflare tunnel
/// </summary>
public enum TunnelStatus
{
    Idle,
    Starting,
    Active,
    Stopping,
    Error
}

/// <summary>
/// Represents a Cloudflare Quick Tunnel instance
/// </summary>
public class CloudflareTunnel : INotifyPropertyChanged
{
    private Guid _id;
    private int _port;
    private TunnelStatus _status;
    private string? _tunnelUrl;
    private string? _lastError;
    private DateTime? _startTime;
    private int? _processId;

    public Guid Id
    {
        get => _id;
        set => SetField(ref _id, value);
    }

    public int Port
    {
        get => _port;
        set => SetField(ref _port, value);
    }

    public TunnelStatus Status
    {
        get => _status;
        set
        {
            if (SetField(ref _status, value))
            {
                OnPropertyChanged(nameof(StatusText));
                OnPropertyChanged(nameof(StatusColor));
                OnPropertyChanged(nameof(IsActive));
                OnPropertyChanged(nameof(IsStarting));
                OnPropertyChanged(nameof(CanCopyUrl));
                OnPropertyChanged(nameof(CanOpenUrl));
            }
        }
    }

    public string? TunnelUrl
    {
        get => _tunnelUrl;
        set
        {
            if (SetField(ref _tunnelUrl, value))
            {
                OnPropertyChanged(nameof(DisplayUrl));
                OnPropertyChanged(nameof(CanCopyUrl));
                OnPropertyChanged(nameof(CanOpenUrl));
            }
        }
    }

    public string? LastError
    {
        get => _lastError;
        set => SetField(ref _lastError, value);
    }

    public DateTime? StartTime
    {
        get => _startTime;
        set
        {
            if (SetField(ref _startTime, value))
            {
                OnPropertyChanged(nameof(Uptime));
            }
        }
    }

    public int? ProcessId
    {
        get => _processId;
        set => SetField(ref _processId, value);
    }

    // Computed properties for UI binding
    public string StatusText => Status switch
    {
        TunnelStatus.Idle => "Idle",
        TunnelStatus.Starting => "Starting...",
        TunnelStatus.Active => "Active",
        TunnelStatus.Stopping => "Stopping...",
        TunnelStatus.Error => "Error",
        _ => "Unknown"
    };

    public string StatusColor => Status switch
    {
        TunnelStatus.Idle => "#808080",
        TunnelStatus.Starting => "#f39c12",
        TunnelStatus.Active => "#2ecc71",
        TunnelStatus.Stopping => "#f39c12",
        TunnelStatus.Error => "#e74c3c",
        _ => "#808080"
    };

    public bool IsActive => Status == TunnelStatus.Active;
    public bool IsStarting => Status == TunnelStatus.Starting;
    public bool CanCopyUrl => IsActive && !string.IsNullOrEmpty(TunnelUrl);
    public bool CanOpenUrl => IsActive && !string.IsNullOrEmpty(TunnelUrl);

    public string DisplayUrl => string.IsNullOrEmpty(TunnelUrl) 
        ? (Status == TunnelStatus.Starting ? "Generating URL..." : "No URL available")
        : TunnelUrl.Replace("https://", "");

    public string Uptime
    {
        get
        {
            if (StartTime == null || Status != TunnelStatus.Active)
                return "-";

            var elapsed = DateTime.Now - StartTime.Value;
            if (elapsed.TotalMinutes < 1)
                return $"{elapsed.Seconds}s";
            if (elapsed.TotalHours < 1)
                return $"{elapsed.Minutes}m {elapsed.Seconds}s";
            return $"{(int)elapsed.TotalHours}h {elapsed.Minutes}m";
        }
    }

    public CloudflareTunnel(int port)
    {
        Id = Guid.NewGuid();
        Port = port;
        Status = TunnelStatus.Idle;
    }

    // INotifyPropertyChanged implementation
    public event PropertyChangedEventHandler? PropertyChanged;

    public virtual void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }

    protected bool SetField<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        OnPropertyChanged(propertyName);
        return true;
    }
}
