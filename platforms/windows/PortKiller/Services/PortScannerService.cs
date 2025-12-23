using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Security.Principal;
using System.Threading.Tasks;
using PortKiller.Models;

namespace PortKiller.Services;

/// <summary>
/// Service for scanning listening TCP ports on Windows.
/// Uses GetExtendedTcpTable Win32 API for best performance and accuracy.
/// </summary>
[SupportedOSPlatform("windows")]
public class PortScannerService
{
    // Win32 API imports for TCP table
    [DllImport("iphlpapi.dll", SetLastError = true)]
    private static extern uint GetExtendedTcpTable(
        IntPtr pTcpTable,
        ref int dwOutBufLen,
        bool sort,
        int ipVersion,
        TCP_TABLE_CLASS tblClass,
        int reserved);

    private enum TCP_TABLE_CLASS
    {
        TCP_TABLE_BASIC_LISTENER = 0,
        TCP_TABLE_BASIC_CONNECTIONS = 1,
        TCP_TABLE_BASIC_ALL = 2,
        TCP_TABLE_OWNER_PID_LISTENER = 3,
        TCP_TABLE_OWNER_PID_CONNECTIONS = 4,
        TCP_TABLE_OWNER_PID_ALL = 5,
        TCP_TABLE_OWNER_MODULE_LISTENER = 6,
        TCP_TABLE_OWNER_MODULE_CONNECTIONS = 7,
        TCP_TABLE_OWNER_MODULE_ALL = 8
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MIB_TCPROW_OWNER_PID
    {
        public uint state;
        public uint localAddr;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 4)]
        public byte[] localPort;
        public uint remoteAddr;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 4)]
        public byte[] remotePort;
        public int owningPid;

        public ushort LocalPort => BitConverter.ToUInt16(new byte[2] { localPort[1], localPort[0] }, 0);
        public string LocalAddress => new System.Net.IPAddress(localAddr).ToString();
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MIB_TCPTABLE_OWNER_PID
    {
        public uint dwNumEntries;
        [MarshalAs(UnmanagedType.ByValArray, ArraySubType = UnmanagedType.Struct, SizeConst = 1)]
        public MIB_TCPROW_OWNER_PID[] table;
    }

    // IPv6 structures
    [StructLayout(LayoutKind.Sequential)]
    private struct MIB_TCP6ROW_OWNER_PID
    {
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 16)]
        public byte[] localAddr;
        public uint localScopeId;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 4)]
        public byte[] localPort;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 16)]
        public byte[] remoteAddr;
        public uint remoteScopeId;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 4)]
        public byte[] remotePort;
        public uint state;
        public int owningPid;

        public ushort LocalPort => BitConverter.ToUInt16(new byte[2] { localPort[1], localPort[0] }, 0);
        public string LocalAddress => new System.Net.IPAddress(localAddr).ToString();
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MIB_TCP6TABLE_OWNER_PID
    {
        public uint dwNumEntries;
        [MarshalAs(UnmanagedType.ByValArray, ArraySubType = UnmanagedType.Struct, SizeConst = 1)]
        public MIB_TCP6ROW_OWNER_PID[] table;
    }

    private const int AF_INET = 2;  // IPv4
    private const int AF_INET6 = 23; // IPv6
    private const uint MIB_TCP_STATE_LISTEN = 2;

    /// <summary>
    /// Scans all listening TCP ports using Windows API.
    /// Equivalent to macOS lsof command.
    /// </summary>
    public async Task<List<PortInfo>> ScanPortsAsync()
    {
        return await Task.Run(() =>
        {
            try
            {
                var ports = new List<PortInfo>();
                var processCache = new Dictionary<int, (string name, string command, string user)>();

                // Scan IPv4 ports
                var tcpRows = GetAllTcpConnections();
                var listeningRows = tcpRows.Where(row => row.state == MIB_TCP_STATE_LISTEN).ToList();

                foreach (var row in listeningRows)
                {
                    try
                    {
                        var pid = row.owningPid;
                        var port = row.LocalPort;
                        var address = row.LocalAddress;

                        // Get process info (with caching)
                        if (!processCache.TryGetValue(pid, out var processInfo))
                        {
                            processInfo = GetProcessInfo(pid);
                            processCache[pid] = processInfo;
                        }

                        var portInfo = PortInfo.Active(
                            port: port,
                            pid: pid,
                            processName: processInfo.name,
                            address: address,
                            user: processInfo.user,
                            command: processInfo.command);
                        
                        // Explicitly set IsKilling to false when creating new Active ports
                        portInfo.IsKilling = false;
                        portInfo.IsConfirmingKill = false;

                        ports.Add(portInfo);
                    }
                    catch
                    {
                        // Skip ports we can't get info for
                        continue;
                    }
                }

                // Scan IPv6 ports
                var tcp6Rows = GetAllTcp6Connections();
                var listening6Rows = tcp6Rows.Where(row => row.state == MIB_TCP_STATE_LISTEN).ToList();

                foreach (var row in listening6Rows)
                {
                    try
                    {
                        var pid = row.owningPid;
                        var port = row.LocalPort;
                        var address = row.LocalAddress;

                        // Get process info (with caching)
                        if (!processCache.TryGetValue(pid, out var processInfo))
                        {
                            processInfo = GetProcessInfo(pid);
                            processCache[pid] = processInfo;
                        }

                        var portInfo = PortInfo.Active(
                            port: port,
                            pid: pid,
                            processName: processInfo.name,
                            address: address,
                            user: processInfo.user,
                            command: processInfo.command);
                        
                        portInfo.IsKilling = false;
                        portInfo.IsConfirmingKill = false;

                        ports.Add(portInfo);
                    }
                    catch
                    {
                        // Skip ports we can't get info for
                        continue;
                    }
                }

                // Remove duplicates (same port + pid)
                return ports
                    .GroupBy(p => new { p.Port, p.Pid })
                    .Select(g => g.First())
                    .OrderBy(p => p.Port)
                    .ToList();
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Error scanning ports: {ex.Message}");
                return new List<PortInfo>();
            }
        });
    }

    /// <summary>
    /// Gets all TCP connections using Win32 API
    /// </summary>
    private List<MIB_TCPROW_OWNER_PID> GetAllTcpConnections()
    {
        var tcpRows = new List<MIB_TCPROW_OWNER_PID>();
        int bufferSize = 0;

        // First call to get buffer size
        uint result = GetExtendedTcpTable(
            IntPtr.Zero,
            ref bufferSize,
            true,
            AF_INET,
            TCP_TABLE_CLASS.TCP_TABLE_OWNER_PID_ALL,
            0);

        IntPtr tcpTablePtr = Marshal.AllocHGlobal(bufferSize);

        try
        {
            // Second call to get actual data
            result = GetExtendedTcpTable(
                tcpTablePtr,
                ref bufferSize,
                true,
                AF_INET,
                TCP_TABLE_CLASS.TCP_TABLE_OWNER_PID_ALL,
                0);

            if (result != 0)
                return tcpRows;

            var table = Marshal.PtrToStructure<MIB_TCPTABLE_OWNER_PID>(tcpTablePtr);
            var rowPtr = (IntPtr)((long)tcpTablePtr + Marshal.SizeOf(table.dwNumEntries));

            for (int i = 0; i < table.dwNumEntries; i++)
            {
                var row = Marshal.PtrToStructure<MIB_TCPROW_OWNER_PID>(rowPtr);
                tcpRows.Add(row);
                rowPtr = (IntPtr)((long)rowPtr + Marshal.SizeOf<MIB_TCPROW_OWNER_PID>());
            }
        }
        finally
        {
            Marshal.FreeHGlobal(tcpTablePtr);
        }

        return tcpRows;
    }

    /// <summary>
    /// Gets all IPv6 TCP connections using Win32 API
    /// </summary>
    private List<MIB_TCP6ROW_OWNER_PID> GetAllTcp6Connections()
    {
        var tcpRows = new List<MIB_TCP6ROW_OWNER_PID>();
        int bufferSize = 0;

        // First call to get buffer size
        uint result = GetExtendedTcpTable(
            IntPtr.Zero,
            ref bufferSize,
            true,
            AF_INET6,
            TCP_TABLE_CLASS.TCP_TABLE_OWNER_PID_ALL,
            0);

        if (bufferSize == 0)
            return tcpRows;

        IntPtr tcpTablePtr = Marshal.AllocHGlobal(bufferSize);

        try
        {
            // Second call to get actual data
            result = GetExtendedTcpTable(
                tcpTablePtr,
                ref bufferSize,
                true,
                AF_INET6,
                TCP_TABLE_CLASS.TCP_TABLE_OWNER_PID_ALL,
                0);

            if (result != 0)
                return tcpRows;

            var numEntries = Marshal.ReadInt32(tcpTablePtr);
            var rowPtr = (IntPtr)((long)tcpTablePtr + sizeof(int));

            for (int i = 0; i < numEntries; i++)
            {
                var row = Marshal.PtrToStructure<MIB_TCP6ROW_OWNER_PID>(rowPtr);
                tcpRows.Add(row);
                rowPtr = (IntPtr)((long)rowPtr + Marshal.SizeOf<MIB_TCP6ROW_OWNER_PID>());
            }
        }
        finally
        {
            Marshal.FreeHGlobal(tcpTablePtr);
        }

        return tcpRows;
    }

    /// <summary>
    /// Gets detailed process information (name, command line, user)
    /// </summary>
    private (string name, string command, string user) GetProcessInfo(int pid)
    {
        try
        {
            using var process = Process.GetProcessById(pid);
            var name = process.ProcessName;
            
            // Try to get full command line
            string command;
            try
            {
                // Use WMI to get command line
                command = GetProcessCommandLine(pid) ?? process.MainModule?.FileName ?? name;
                
                // Truncate if too long
                if (command.Length > 200)
                    command = command.Substring(0, 200) + "...";
            }
            catch
            {
                command = name;
            }

            // Get process owner (user)
            string user;
            try
            {
                user = GetProcessOwner(process) ?? Environment.UserName;
            }
            catch
            {
                user = Environment.UserName;
            }

            return (name, command, user);
        }
        catch
        {
            return ("Unknown", "Unknown", "Unknown");
        }
    }

    /// <summary>
    /// Gets the command line of a process using WMI
    /// </summary>
    private string? GetProcessCommandLine(int pid)
    {
        try
        {
            using var searcher = new System.Management.ManagementObjectSearcher(
                $"SELECT CommandLine FROM Win32_Process WHERE ProcessId = {pid}");
            using var objects = searcher.Get();
            
            foreach (System.Management.ManagementObject obj in objects)
            {
                return obj["CommandLine"]?.ToString();
            }
        }
        catch
        {
            // Ignore - we'll fallback to process name
        }
        return null;
    }

    /// <summary>
    /// Gets the owner (username) of a process
    /// </summary>
    private string? GetProcessOwner(Process process)
    {
        try
        {
            var processHandle = process.Handle;
            if (OpenProcessToken(processHandle, 8, out IntPtr tokenHandle))
            {
                try
                {
                    using var identity = new WindowsIdentity(tokenHandle);
                    return identity.Name;
                }
                finally
                {
                    CloseHandle(tokenHandle);
                }
            }
        }
        catch
        {
            // Ignore - we'll fallback
        }
        return null;
    }

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(IntPtr hObject);
}
