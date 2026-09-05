using System.Diagnostics;
using System.Runtime.InteropServices;

namespace ComputerBar.Core;

public sealed record NodeFetchResult(string Alias, NodeStatus? Status, string? ErrorMessage);

public sealed class NodeMonitorParseException(string message) : Exception(message);

public sealed class NodeMonitorService : INodeMonitorService
{
    private static readonly TimeSpan RemoteTimeout = TimeSpan.FromSeconds(10);

    public async Task<IReadOnlyList<NodeFetchResult>> FetchStatusesAsync(
        IReadOnlyList<ComputerHost> hosts,
        CancellationToken cancellationToken = default)
    {
        var tasks = hosts.Select(host => FetchStatusAsync(host, cancellationToken)).ToArray();
        return await Task.WhenAll(tasks);
    }

    public static NodeStatus ParseStatusOutput(
        string output,
        ComputerHost host,
        DateTimeOffset collectedAt)
    {
        var values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var rawLine in output.Split(["\r\n", "\n"], StringSplitOptions.None))
        {
            var line = rawLine.Trim();
            var separator = line.IndexOf('=');
            if (separator <= 0)
            {
                continue;
            }

            values[line[..separator]] = line[(separator + 1)..];
        }

        var cpuUsagePercent = ReadDouble(values, "cpu_percent");
        var totalKilobytes = ReadUInt64(values, "mem_total_kb");
        var availableKilobytes = ReadUInt64(values, "mem_available_kb");
        var diskTotalKilobytes = ReadUInt64(values, "disk_total_kb");
        var diskUsedKilobytes = ReadUInt64(values, "disk_used_kb");
        var uptimeSeconds = ReadDouble(values, "uptime_seconds");
        var swap = ReadOptionalSwapUsage(values);

        var memoryTotalBytes = totalKilobytes * 1024;
        var availableBytes = Math.Min(availableKilobytes * 1024, memoryTotalBytes);
        var memoryUsedBytes = memoryTotalBytes >= availableBytes ? memoryTotalBytes - availableBytes : 0;
        var memoryUsagePercent = memoryTotalBytes == 0
            ? 0
            : (double)memoryUsedBytes / memoryTotalBytes * 100;

        var diskTotalBytes = diskTotalKilobytes * 1024;
        var diskUsedBytes = Math.Min(diskUsedKilobytes * 1024, diskTotalBytes);
        var diskUsagePercent = diskTotalBytes == 0
            ? 0
            : (double)diskUsedBytes / diskTotalBytes * 100;

        var loadAverages = values.TryGetValue("loadavg", out var loadAverageText)
            ? loadAverageText.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)
                .Select(value => double.TryParse(value, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var parsed) ? parsed : 0)
                .Concat([0d, 0d, 0d])
                .Take(3)
                .ToArray()
            : [0d, 0d, 0d];

        return new NodeStatus(
            host,
            Clamp(cpuUsagePercent),
            Clamp(memoryUsagePercent),
            memoryUsedBytes,
            memoryTotalBytes,
            swap?.UsagePercent,
            swap?.UsedBytes,
            swap?.TotalBytes,
            Clamp(diskUsagePercent),
            diskUsedBytes,
            diskTotalBytes,
            loadAverages,
            uptimeSeconds,
            collectedAt);
    }

    private async Task<NodeFetchResult> FetchStatusAsync(
        ComputerHost host,
        CancellationToken cancellationToken)
    {
        try
        {
            var status = host.IsLocal
                ? await FetchLocalStatusAsync(host, cancellationToken)
                : await FetchRemoteStatusAsync(host, cancellationToken);
            return new NodeFetchResult(host.Alias, status, null);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return new NodeFetchResult(host.Alias, null, ex.Message);
        }
    }

    private static async Task<NodeStatus> FetchLocalStatusAsync(
        ComputerHost host,
        CancellationToken cancellationToken)
    {
        var firstCpu = ReadCpuTimes();
        await Task.Delay(200, cancellationToken);
        var secondCpu = ReadCpuTimes();
        var cpuUsagePercent = CpuUsagePercent(firstCpu, secondCpu);
        var memory = ReadMemoryUsage();
        var disk = ReadDiskUsage();

        return new NodeStatus(
            host,
            cpuUsagePercent,
            memory.UsagePercent,
            memory.UsedBytes,
            memory.TotalBytes,
            null,
            null,
            null,
            disk.UsagePercent,
            disk.UsedBytes,
            disk.TotalBytes,
            [],
            Environment.TickCount64 / 1000d,
            DateTimeOffset.Now);
    }

    private static async Task<NodeStatus> FetchRemoteStatusAsync(
        ComputerHost host,
        CancellationToken cancellationToken)
    {
        var output = await ProcessRunner.RunAsync(
            "ssh",
            [
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=4",
                "-o", "ServerAliveInterval=4",
                "-o", "ServerAliveCountMax=1",
                host.Alias,
                "sh",
                "-s"
            ],
            RemoteScript,
            RemoteTimeout,
            cancellationToken);

        if (output.ExitCode != 0)
        {
            throw new InvalidOperationException(SanitizedErrorMessage(
                output.StandardError,
                $"SSH exited with code {output.ExitCode}."));
        }

        return ParseStatusOutput(output.StandardOutput, host, DateTimeOffset.Now);
    }

    private static double ReadDouble(IReadOnlyDictionary<string, string> values, string key)
    {
        if (!values.TryGetValue(key, out var value))
        {
            throw new NodeMonitorParseException($"Missing field in SSH monitor output: {key}");
        }

        if (!double.TryParse(value, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var parsed))
        {
            throw new NodeMonitorParseException($"Invalid field in SSH monitor output: {key}");
        }

        return parsed;
    }

    private static ulong ReadUInt64(IReadOnlyDictionary<string, string> values, string key)
    {
        if (!values.TryGetValue(key, out var value))
        {
            throw new NodeMonitorParseException($"Missing field in SSH monitor output: {key}");
        }

        if (!ulong.TryParse(value, out var parsed))
        {
            throw new NodeMonitorParseException($"Invalid field in SSH monitor output: {key}");
        }

        return parsed;
    }

    private static (ulong UsedBytes, ulong TotalBytes, double UsagePercent)? ReadOptionalSwapUsage(
        IReadOnlyDictionary<string, string> values)
    {
        if (!values.TryGetValue("swap_total_kb", out var rawTotal)
            || !values.TryGetValue("swap_free_kb", out var rawFree))
        {
            return null;
        }

        if (!ulong.TryParse(rawTotal, out var totalKilobytes))
        {
            throw new NodeMonitorParseException("Invalid field in SSH monitor output: swap_total_kb");
        }

        if (!ulong.TryParse(rawFree, out var freeKilobytes))
        {
            throw new NodeMonitorParseException("Invalid field in SSH monitor output: swap_free_kb");
        }

        if (totalKilobytes == 0)
        {
            return null;
        }

        var totalBytes = totalKilobytes * 1024;
        var freeBytes = Math.Min(freeKilobytes * 1024, totalBytes);
        var usedBytes = totalBytes >= freeBytes ? totalBytes - freeBytes : 0;
        var usagePercent = totalBytes == 0
            ? 0
            : (double)usedBytes / totalBytes * 100;
        return (usedBytes, totalBytes, Clamp(usagePercent));
    }

    private static double Clamp(double value) => Math.Clamp(value, 0, 100);

    private static string SanitizedErrorMessage(string message, string fallback)
    {
        var trimmed = message.Trim();
        return trimmed.Length == 0 ? fallback : trimmed;
    }

    private static CpuTimes ReadCpuTimes()
    {
        if (!GetSystemTimes(out var idle, out var kernel, out var user))
        {
            throw new InvalidOperationException("Could not read Windows CPU usage.");
        }

        return new CpuTimes(idle.ToUInt64(), kernel.ToUInt64(), user.ToUInt64());
    }

    private static double CpuUsagePercent(CpuTimes first, CpuTimes second)
    {
        var idle = second.Idle - first.Idle;
        var kernel = second.Kernel - first.Kernel;
        var user = second.User - first.User;
        var total = kernel + user;
        if (total == 0)
        {
            return 0;
        }

        return Clamp((double)(total - idle) / total * 100);
    }

    private static MemoryUsage ReadMemoryUsage()
    {
        var status = new MemoryStatusEx();
        status.Length = (uint)Marshal.SizeOf<MemoryStatusEx>();
        if (!GlobalMemoryStatusEx(ref status))
        {
            throw new InvalidOperationException("Could not read Windows memory usage.");
        }

        var total = status.TotalPhys;
        var free = Math.Min(status.AvailPhys, total);
        var used = total >= free ? total - free : 0;
        var usage = total == 0 ? 0 : (double)used / total * 100;
        return new MemoryUsage(used, total, Clamp(usage));
    }

    private static DiskUsage ReadDiskUsage()
    {
        var systemRoot = Path.GetPathRoot(Environment.GetFolderPath(Environment.SpecialFolder.System));
        var drives = DriveInfo.GetDrives()
            .Where(drive => drive.DriveType == DriveType.Fixed && drive.IsReady)
            .ToArray();
        var drive = drives.FirstOrDefault(candidate =>
            !string.IsNullOrWhiteSpace(systemRoot)
            && string.Equals(candidate.Name, systemRoot, StringComparison.OrdinalIgnoreCase))
            ?? drives.FirstOrDefault();

        if (drive is null)
        {
            throw new InvalidOperationException("Could not find a ready fixed disk.");
        }

        var total = (ulong)Math.Max(0, drive.TotalSize);
        var free = (ulong)Math.Max(0, drive.AvailableFreeSpace);
        free = Math.Min(free, total);
        var used = total >= free ? total - free : 0;
        var usage = total == 0 ? 0 : (double)used / total * 100;
        return new DiskUsage(used, total, Clamp(usage));
    }

    private sealed record CpuTimes(ulong Idle, ulong Kernel, ulong User);
    private sealed record MemoryUsage(ulong UsedBytes, ulong TotalBytes, double UsagePercent);
    private sealed record DiskUsage(ulong UsedBytes, ulong TotalBytes, double UsagePercent);

    [StructLayout(LayoutKind.Sequential)]
    private struct FileTime
    {
        public uint LowDateTime;
        public uint HighDateTime;

        public readonly ulong ToUInt64() => ((ulong)HighDateTime << 32) | LowDateTime;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private struct MemoryStatusEx
    {
        public uint Length;
        public uint MemoryLoad;
        public ulong TotalPhys;
        public ulong AvailPhys;
        public ulong TotalPageFile;
        public ulong AvailPageFile;
        public ulong TotalVirtual;
        public ulong AvailVirtual;
        public ulong AvailExtendedVirtual;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetSystemTimes(
        out FileTime idleTime,
        out FileTime kernelTime,
        out FileTime userTime);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern bool GlobalMemoryStatusEx(ref MemoryStatusEx buffer);

    private const string RemoteScript = """
    set -eu

    cpu_a="$(grep '^cpu ' /proc/stat)"
    sleep 0.2
    cpu_b="$(grep '^cpu ' /proc/stat)"

    mem_total_kb="$(awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo)"
    mem_available_kb="$(awk '/^MemAvailable:/ { print $2; exit }' /proc/meminfo || true)"
    swap_total_kb="$(awk '/^SwapTotal:/ { print $2; exit }' /proc/meminfo || true)"
    swap_free_kb="$(awk '/^SwapFree:/ { print $2; exit }' /proc/meminfo || true)"
    disk_total_kb="$(df -kP / | awk 'NR == 2 { print $2; exit }')"
    disk_used_kb="$(df -kP / | awk 'NR == 2 { print $3; exit }')"

    if [ -z "${mem_available_kb:-}" ]; then
      mem_available_kb="$(awk '
        /^MemFree:/ { free = $2 }
        /^Buffers:/ { buffers = $2 }
        /^Cached:/ { cached = $2 }
        END { print free + buffers + cached }
      ' /proc/meminfo)"
    fi
    swap_total_kb="${swap_total_kb:-0}"
    swap_free_kb="${swap_free_kb:-0}"

    loadavg="$(cut -d ' ' -f 1-3 /proc/loadavg)"
    uptime_seconds="$(cut -d ' ' -f 1 /proc/uptime)"

    cpu_percent="$(
      awk -v first="$cpu_a" -v second="$cpu_b" '
      BEGIN {
          count_a = split(first, a)
          count_b = split(second, b)
          total_a = 0
          total_b = 0
          for (i = 2; i <= count_a; i++) {
              total_a += a[i]
          }
          for (i = 2; i <= count_b; i++) {
              total_b += b[i]
          }
          idle_a = a[5] + a[6]
          idle_b = b[5] + b[6]
          delta_total = total_b - total_a
          delta_idle = idle_b - idle_a
          if (delta_total <= 0) {
              print "0.00"
          } else {
              printf "%.2f", ((delta_total - delta_idle) / delta_total) * 100
          }
      }'
    )"

    printf 'cpu_percent=%s\n' "$cpu_percent"
    printf 'mem_total_kb=%s\n' "$mem_total_kb"
    printf 'mem_available_kb=%s\n' "$mem_available_kb"
    printf 'swap_total_kb=%s\n' "$swap_total_kb"
    printf 'swap_free_kb=%s\n' "$swap_free_kb"
    printf 'disk_total_kb=%s\n' "$disk_total_kb"
    printf 'disk_used_kb=%s\n' "$disk_used_kb"
    printf 'loadavg=%s\n' "$loadavg"
    printf 'uptime_seconds=%s\n' "$uptime_seconds"
    """;
}

internal sealed record ProcessOutput(int ExitCode, string StandardOutput, string StandardError);

internal static class ProcessRunner
{
    public static async Task<ProcessOutput> RunAsync(
        string fileName,
        IReadOnlyList<string> arguments,
        string? standardInput,
        TimeSpan timeout,
        CancellationToken cancellationToken = default)
    {
        using var process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = fileName,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                RedirectStandardInput = standardInput is not null
            }
        };

        foreach (var argument in arguments)
        {
            process.StartInfo.ArgumentList.Add(argument);
        }

        process.Start();

        if (standardInput is not null)
        {
            await process.StandardInput.WriteAsync(standardInput.AsMemory(), cancellationToken);
            await process.StandardInput.FlushAsync(cancellationToken);
            process.StandardInput.Close();
        }

        var stdout = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var stderr = process.StandardError.ReadToEndAsync(cancellationToken);

        using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeoutCts.CancelAfter(timeout);

        try
        {
            await process.WaitForExitAsync(timeoutCts.Token);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                process.Kill(entireProcessTree: true);
            }
            catch (InvalidOperationException)
            {
            }

            throw new TimeoutException($"{fileName} timed out after {timeout.TotalSeconds:0.#} seconds.");
        }

        return new ProcessOutput(
            process.ExitCode,
            await stdout,
            await stderr);
    }
}
