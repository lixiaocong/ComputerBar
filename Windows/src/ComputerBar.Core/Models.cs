using System.Globalization;
using System.Windows.Forms;

namespace ComputerBar.Core;

public enum ComputerHostKind
{
    Remote,
    Local
}

public sealed record ComputerHost(
    string Alias,
    string HostName,
    string? User,
    int? Port,
    ComputerHostKind Kind = ComputerHostKind.Remote)
{
    public const string LocalAlias = "__local__computerbar__";

    public string Id => Alias;
    public bool IsLocal => Kind == ComputerHostKind.Local;
    public string DisplayName => IsLocal ? "This PC" : Alias;

    public string EndpointDescription
    {
        get
        {
            var userPrefix = string.IsNullOrWhiteSpace(User) ? "" : $"{User}@";
            var portSuffix = Port is null ? "" : $":{Port}";
            return $"{userPrefix}{HostName}{portSuffix}";
        }
    }

    public static ComputerHost Local() => new(
        LocalAlias,
        Environment.MachineName,
        Environment.UserName,
        null,
        ComputerHostKind.Local);
}

public sealed record NodeStatus(
    ComputerHost Host,
    double CpuUsagePercent,
    double MemoryUsagePercent,
    ulong MemoryUsedBytes,
    ulong MemoryTotalBytes,
    double? VirtualMemoryUsagePercent,
    ulong? VirtualMemoryUsedBytes,
    ulong? VirtualMemoryTotalBytes,
    double DiskUsagePercent,
    ulong DiskUsedBytes,
    ulong DiskTotalBytes,
    IReadOnlyList<double> LoadAverages,
    double UptimeSeconds,
    DateTimeOffset CollectedAt)
{
    public string Id => Host.Id;
    public string CpuUsageText => PercentText(CpuUsagePercent);
    public string MemoryUsageText => PercentText(MemoryUsagePercent);
    public string VirtualMemoryUsageText => VirtualMemoryUsagePercent is { } percent ? PercentText(percent) : "--";
    public string DiskUsageText => PercentText(DiskUsagePercent);
    public bool HasVirtualMemoryUsage => VirtualMemoryUsagePercent is not null;
    public double HighlightUsagePercent => Math.Max(
        CpuUsagePercent,
        Math.Max(MemoryUsagePercent, Math.Max(VirtualMemoryUsagePercent ?? 0, DiskUsagePercent)));

    public string MemoryUsageSummary =>
        $"{FormatBytes(MemoryUsedBytes)} / {FormatBytes(MemoryTotalBytes)}";

    public string VirtualMemoryUsageSummary =>
        VirtualMemoryUsedBytes is { } used && VirtualMemoryTotalBytes is { } total
            ? $"{FormatBytes(used)} / {FormatBytes(total)}"
            : "--";

    public string DiskUsageSummary =>
        $"{FormatBytes(DiskUsedBytes)} / {FormatBytes(DiskTotalBytes)}";

    public string UsageSummary
    {
        get
        {
            var segments = new List<string>
            {
                $"CPU {CpuUsageText}",
                $"memory {MemoryUsageText}"
            };

            if (HasVirtualMemoryUsage)
            {
                segments.Add($"virtual memory {VirtualMemoryUsageText}");
            }

            segments.Add($"disk {DiskUsageText}");
            return string.Join(", ", segments);
        }
    }

    public string LoadAverageText => LoadAverages.Count == 0
        ? "--"
        : string.Join("  ", LoadAverages.Take(3).Select(value => value.ToString("0.00", CultureInfo.InvariantCulture)));

    public string UptimeText => CompactDuration(UptimeSeconds);
    public string UpdatedAtText => CollectedAt.ToLocalTime().ToString("T", CultureInfo.CurrentCulture);

    public static string PercentText(double value) =>
        $"{Math.Clamp((int)Math.Round(value), 0, 100)}%";

    public static string FormatBytes(ulong bytes)
    {
        string[] units = ["B", "KiB", "MiB", "GiB", "TiB"];
        var value = (double)bytes;
        var unit = 0;
        while (value >= 1024 && unit < units.Length - 1)
        {
            value /= 1024;
            unit++;
        }

        var format = unit == 0 ? "0" : value >= 10 ? "0.#" : "0.##";
        return $"{value.ToString(format, CultureInfo.InvariantCulture)} {units[unit]}";
    }

    public static string CompactDuration(double seconds)
    {
        var totalSeconds = Math.Max(0, (int)Math.Floor(seconds));
        var days = totalSeconds / 86_400;
        var hours = totalSeconds % 86_400 / 3_600;
        var minutes = totalSeconds % 3_600 / 60;
        var restSeconds = totalSeconds % 60;
        var parts = new List<string>(2);

        if (days > 0)
        {
            parts.Add($"{days}d");
        }

        if (hours > 0)
        {
            parts.Add($"{hours}h");
        }

        if (minutes > 0 && parts.Count < 2)
        {
            parts.Add($"{minutes}m");
        }

        if (parts.Count == 0)
        {
            parts.Add($"{restSeconds}s");
        }

        return string.Join(" ", parts);
    }
}

public sealed record NodeStatusState(
    ComputerHost Host,
    bool IsLoading = false,
    NodeStatus? Status = null,
    string? ErrorMessage = null)
{
    public string Id => Host.Id;

    public static NodeStatusState Idle(ComputerHost host) => new(host);
}

public sealed record TrayHostStatus(
    string Label,
    double? UsagePercent,
    bool IsError = false,
    string? ErrorMessage = null);

public sealed class IconRenderResult(Icon icon, int width, int height, bool hasNonTransparentPixels)
{
    public Icon Icon { get; } = icon;
    public int Width { get; } = width;
    public int Height { get; } = height;
    public bool HasNonTransparentPixels { get; } = hasNonTransparentPixels;
}

public sealed record ComputerBarSettings(
    IReadOnlyList<string> SelectedAliases,
    IReadOnlyList<string> TrayHostAliases,
    int RefreshIntervalSeconds)
{
    public const int DefaultRefreshIntervalSeconds = 1;
    public const int MinimumRefreshIntervalSeconds = 1;
    public const int MaximumRefreshIntervalSeconds = 60;
    public const int MaximumTrayHosts = 1;

    public static ComputerBarSettings Default { get; } = new(
        [ComputerHost.LocalAlias],
        [],
        DefaultRefreshIntervalSeconds);

    public ComputerBarSettings Normalized() => this with
    {
        SelectedAliases = DistinctAliases(SelectedAliases),
        TrayHostAliases = DistinctAliases(TrayHostAliases).Take(MaximumTrayHosts).ToArray(),
        RefreshIntervalSeconds = NormalizeRefreshInterval(RefreshIntervalSeconds)
    };

    public static int NormalizeRefreshInterval(int seconds) =>
        Math.Clamp(seconds, MinimumRefreshIntervalSeconds, MaximumRefreshIntervalSeconds);

    private static IReadOnlyList<string> DistinctAliases(IEnumerable<string>? aliases)
    {
        if (aliases is null)
        {
            return [];
        }

        var normalized = new List<string>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var alias in aliases.Select(alias => alias.Trim()).Where(alias => alias.Length > 0))
        {
            if (seen.Add(alias))
            {
                normalized.Add(alias);
            }
        }

        return normalized;
    }
}

public static class ComputerUsageDisplayColor
{
    public static UsageRgb ForUsagePercent(double percent) => percent switch
    {
        >= 95 => new UsageRgb(1.0, 0.23, 0.18),
        >= 80 => new UsageRgb(1.0, 0.58, 0.0),
        _ => new UsageRgb(0.16, 0.76, 0.35)
    };
}

public sealed record UsageRgb(double Red, double Green, double Blue);
