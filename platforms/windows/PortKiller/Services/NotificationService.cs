using System;

namespace PortKiller.Services;

/// <summary>
/// Service for sending Windows notifications for watched port events.
/// Uses simple message boxes for now (can be enhanced with Windows 10/11 toast notifications later)
/// </summary>
public class NotificationService
{
    private static readonly Lazy<NotificationService> _instance = new(() => new NotificationService());
    public static NotificationService Instance => _instance.Value;

    private bool _isInitialized;

    private NotificationService()
    {
    }

    /// <summary>
    /// Initialize the notification service
    /// </summary>
    public void Initialize()
    {
        _isInitialized = true;
    }

    /// <summary>
    /// Send notification when a watched port starts
    /// </summary>
    public void NotifyPortStarted(int port, string processName)
    {
        if (!_isInitialized)
            return;

        try
        {
            // For now, we'll just write to debug output
            // You can enhance this with Windows.UI.Notifications or other notification libraries
            System.Diagnostics.Debug.WriteLine($"✅ Port {port} started - Process: {processName}");
        }
        catch
        {
            // Silently fail - notifications are not critical
        }
    }

    /// <summary>
    /// Send notification when a watched port stops
    /// </summary>
    public void NotifyPortStopped(int port)
    {
        if (!_isInitialized)
            return;

        try
        {
            System.Diagnostics.Debug.WriteLine($"❌ Port {port} stopped");
        }
        catch
        {
            // Silently fail
        }
    }

    /// <summary>
    /// Send a general notification
    /// </summary>
    public void Notify(string title, string message)
    {
        if (!_isInitialized)
            return;

        try
        {
            System.Diagnostics.Debug.WriteLine($"📢 {title}: {message}");
        }
        catch
        {
            // Silently fail
        }
    }

    public void Unregister()
    {
        _isInitialized = false;
    }
}
