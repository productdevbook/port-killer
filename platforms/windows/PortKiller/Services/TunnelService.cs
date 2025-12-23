using System.Diagnostics;
using System.IO;
using System.Text.RegularExpressions;
using PortKiller.Models;

namespace PortKiller.Services;

/// <summary>
/// Service for managing Cloudflare tunnel processes
/// </summary>
public class TunnelService
{
    private readonly Dictionary<Guid, Process> _processes = new();
    private readonly Dictionary<Guid, Action<string>> _urlHandlers = new();
    private readonly Dictionary<Guid, Action<string>> _errorHandlers = new();

    // Possible cloudflared.exe installation paths
    private static readonly string[] CloudflaredPaths = {
        @"C:\Program Files\cloudflared\cloudflared.exe",
        @"C:\Program Files (x86)\cloudflared\cloudflared.exe",
        @"C:\ProgramData\chocolatey\bin\cloudflared.exe",
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"cloudflared\cloudflared.exe"),
        @"cloudflared.exe" // Try PATH
    };

    /// <summary>
    /// Checks if cloudflared is installed
    /// </summary>
    public bool IsCloudflaredInstalled => CloudflaredPath != null;

    /// <summary>
    /// Gets the path to cloudflared.exe if installed
    /// </summary>
    public string? CloudflaredPath
    {
        get
        {
            // Check explicit paths first
            var explicitPath = CloudflaredPaths.Take(CloudflaredPaths.Length - 1)
                .FirstOrDefault(File.Exists);
            
            if (explicitPath != null)
                return explicitPath;

            // Try to find in PATH
            try
            {
                var process = new Process
                {
                    StartInfo = new ProcessStartInfo
                    {
                        FileName = "where",
                        Arguments = "cloudflared",
                        RedirectStandardOutput = true,
                        UseShellExecute = false,
                        CreateNoWindow = true
                    }
                };
                
                process.Start();
                var output = process.StandardOutput.ReadToEnd();
                process.WaitForExit();

                if (process.ExitCode == 0 && !string.IsNullOrWhiteSpace(output))
                {
                    var firstPath = output.Split('\n')[0].Trim();
                    if (File.Exists(firstPath))
                        return firstPath;
                }
            }
            catch
            {
                // Ignore errors
            }

            return null;
        }
    }

    /// <summary>
    /// Starts a tunnel for the specified port
    /// </summary>
    public async Task<Process> StartTunnelAsync(CloudflareTunnel tunnel)
    {
        var cloudflaredPath = CloudflaredPath;
        if (cloudflaredPath == null)
            throw new InvalidOperationException("cloudflared is not installed");

        var process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = cloudflaredPath,
                Arguments = $"tunnel --url localhost:{tunnel.Port}",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            }
        };

        // Set up output handlers
        process.OutputDataReceived += (sender, e) => 
        {
            if (!string.IsNullOrEmpty(e.Data))
                ParseOutput(tunnel.Id, e.Data);
        };

        process.ErrorDataReceived += (sender, e) => 
        {
            if (!string.IsNullOrEmpty(e.Data))
                ParseOutput(tunnel.Id, e.Data);
        };

        try
        {
            process.Start();
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();

            _processes[tunnel.Id] = process;
            tunnel.ProcessId = process.Id;

            // Wait a moment to check if process started successfully
            await Task.Delay(1000);

            if (process.HasExited)
            {
                throw new InvalidOperationException($"Cloudflared process exited with code {process.ExitCode}");
            }

            return process;
        }
        catch (Exception ex)
        {
            _errorHandlers.TryGetValue(tunnel.Id, out var errorHandler);
            errorHandler?.Invoke($"Failed to start tunnel: {ex.Message}");
            throw;
        }
    }

    /// <summary>
    /// Stops a tunnel
    /// </summary>
    public async Task StopTunnelAsync(Guid tunnelId)
    {
        if (!_processes.TryGetValue(tunnelId, out var process))
            return;

        try
        {
            if (!process.HasExited)
            {
                // Try graceful shutdown first
                process.Kill(entireProcessTree: false);
                
                // Wait up to 2 seconds for graceful shutdown
                var exited = process.WaitForExit(2000);
                
                // Force kill if still running
                if (!exited && !process.HasExited)
                {
                    process.Kill(entireProcessTree: true);
                }
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error stopping tunnel {tunnelId}: {ex.Message}");
        }
        finally
        {
            process.Dispose();
            _processes.Remove(tunnelId);
            _urlHandlers.Remove(tunnelId);
            _errorHandlers.Remove(tunnelId);
        }

        await Task.CompletedTask;
    }

    /// <summary>
    /// Stops all active tunnels
    /// </summary>
    public async Task StopAllTunnelsAsync()
    {
        var tunnelIds = _processes.Keys.ToList();
        foreach (var id in tunnelIds)
        {
            await StopTunnelAsync(id);
        }
    }

    /// <summary>
    /// Registers a handler for when the tunnel URL is ready
    /// </summary>
    public void SetUrlHandler(Guid tunnelId, Action<string> handler)
    {
        _urlHandlers[tunnelId] = handler;
    }

    /// <summary>
    /// Registers a handler for errors
    /// </summary>
    public void SetErrorHandler(Guid tunnelId, Action<string> handler)
    {
        _errorHandlers[tunnelId] = handler;
    }

    /// <summary>
    /// Checks if a tunnel process is running
    /// </summary>
    public bool IsRunning(Guid tunnelId)
    {
        return _processes.TryGetValue(tunnelId, out var process) && !process.HasExited;
    }

    /// <summary>
    /// Parses cloudflared output to extract tunnel URL
    /// </summary>
    private void ParseOutput(Guid tunnelId, string line)
    {
        // cloudflared outputs URLs in format:
        // "https://something-random.trycloudflare.com"
        // Can appear in table format or plain text

        var urlPattern = @"https://[a-z0-9-]+\.trycloudflare\.com";
        var match = Regex.Match(line, urlPattern);

        if (match.Success)
        {
            var url = match.Value;
            _urlHandlers.TryGetValue(tunnelId, out var urlHandler);
            urlHandler?.Invoke(url);
        }

        // Check for errors
        var lowerLine = line.ToLower();
        if (lowerLine.Contains("error") || 
            lowerLine.Contains("failed") || 
            lowerLine.Contains("unable to") ||
            lowerLine.Contains("permission denied"))
        {
            _errorHandlers.TryGetValue(tunnelId, out var errorHandler);
            errorHandler?.Invoke(line);
        }
    }

    /// <summary>
    /// Cleans up any orphaned cloudflared processes from previous sessions
    /// </summary>
    public async Task CleanupOrphanedTunnelsAsync()
    {
        await Task.Run(() =>
        {
            try
            {
                var processes = Process.GetProcessesByName("cloudflared");
                foreach (var process in processes)
                {
                    try
                    {
                        // Check if it's a tunnel process
                        var commandLine = GetProcessCommandLine(process.Id);
                        if (commandLine != null && commandLine.Contains("tunnel") && commandLine.Contains("--url"))
                        {
                            process.Kill();
                            Debug.WriteLine($"Killed orphaned cloudflared process (PID: {process.Id})");
                        }
                    }
                    catch
                    {
                        // Process may have already exited
                    }
                    finally
                    {
                        process.Dispose();
                    }
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Error cleaning up orphaned tunnels: {ex.Message}");
            }
        });
    }

    /// <summary>
    /// Gets the command line of a process (for cleanup verification)
    /// </summary>
    private string? GetProcessCommandLine(int processId)
    {
        try
        {
            using var searcher = new System.Management.ManagementObjectSearcher(
                $"SELECT CommandLine FROM Win32_Process WHERE ProcessId = {processId}");
            
            foreach (System.Management.ManagementObject obj in searcher.Get())
            {
                return obj["CommandLine"]?.ToString();
            }
        }
        catch
        {
            // Ignore
        }
        return null;
    }
}
