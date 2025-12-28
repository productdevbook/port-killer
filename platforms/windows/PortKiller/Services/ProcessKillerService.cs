using System;
using System.Diagnostics;
using System.Runtime.Versioning;
using System.Threading.Tasks;

namespace PortKiller.Services;

/// <summary>
/// Service for terminating processes on Windows.
/// Equivalent to macOS kill command functionality.
/// </summary>
[SupportedOSPlatform("windows")]
public class ProcessKillerService
{
    /// <summary>
    /// Kills a process by PID.
    /// Windows doesn't have SIGTERM equivalent, so this terminates immediately.
    /// </summary>
    public async Task<bool> KillProcessAsync(int pid, bool force = false)
    {
        return await Task.Run(() =>
        {
            try
            {
                using var process = Process.GetProcessById(pid);
                
                if (!force)
                {
                    // Try graceful close first
                    if (process.CloseMainWindow())
                    {
                        // Give it time to close gracefully
                        process.WaitForExit(2000);
                        if (process.HasExited)
                            return true;
                    }
                }

                // Force kill
                process.Kill(entireProcessTree: true);
                return true;
            }
            catch (ArgumentException)
            {
                // Process doesn't exist
                return false;
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Error killing process {pid}: {ex.Message}");
                return false;
            }
        });
    }

    /// <summary>
    /// Attempts to kill a process gracefully with fallback to force kill.
    /// Strategy:
    /// 1. Try CloseMainWindow() for graceful shutdown
    /// 2. Wait 500ms
    /// 3. Force kill with Process.Kill()
    /// </summary>
    public async Task<bool> KillProcessGracefullyAsync(int pid)
    {
        try
        {
            using var process = Process.GetProcessById(pid);

            // Try graceful close first
            var closedGracefully = process.CloseMainWindow();
            if (closedGracefully)
            {
                // Give it time to clean up (500ms grace period)
                var exited = process.WaitForExit(500);
                if (exited)
                    return true;
            }

            // Force kill if still running
            if (!process.HasExited)
            {
                await Task.Delay(100); // Small delay before force kill
                process.Kill(entireProcessTree: true);
                return true;
            }

            return true;
        }
        catch (ArgumentException)
        {
            // Process doesn't exist anymore
            return false;
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error killing process {pid} gracefully: {ex.Message}");
            return false;
        }
    }

    /// <summary>
    /// Kills all processes listening on a specific port
    /// </summary>
    public async Task<int> KillProcessesOnPortAsync(int port)
    {
        var scanner = new PortScannerService();
        var ports = await scanner.ScanPortsAsync();
        var processesOnPort = ports.Where(p => p.Port == port && p.IsActive).ToList();

        int killedCount = 0;
        foreach (var portInfo in processesOnPort)
        {
            var success = await KillProcessGracefullyAsync(portInfo.Pid);
            if (success)
                killedCount++;
        }

        return killedCount;
    }

    /// <summary>
    /// Check if process exists and is running
    /// </summary>
    public bool ProcessExists(int pid)
    {
        try
        {
            using var process = Process.GetProcessById(pid);
            return !process.HasExited;
        }
        catch
        {
            return false;
        }
    }
}
