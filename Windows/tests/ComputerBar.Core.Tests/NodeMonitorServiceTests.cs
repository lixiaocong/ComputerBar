using ComputerBar.Core;

namespace ComputerBar.Core.Tests;

public sealed class NodeMonitorServiceTests
{
    [Fact]
    public void ParseStatusOutputBuildsNodeStatus()
    {
        var host = new ComputerHost("dev", "example.internal", "ubuntu", 22);
        var collectedAt = DateTimeOffset.FromUnixTimeSeconds(1_718_000_000);
        const string output = """
        cpu_percent=23.50
        mem_total_kb=2048000
        mem_available_kb=512000
        disk_total_kb=8192000
        disk_used_kb=2048000
        loadavg=0.10 0.20 0.30
        uptime_seconds=3661.12
        """;

        var status = NodeMonitorService.ParseStatusOutput(output, host, collectedAt);

        Assert.Equal(host, status.Host);
        Assert.Equal(23.5, status.CpuUsagePercent, 3);
        Assert.Equal(75, status.MemoryUsagePercent, 3);
        Assert.Equal(1_572_864_000UL, status.MemoryUsedBytes);
        Assert.Equal(2_097_152_000UL, status.MemoryTotalBytes);
        Assert.Equal(25, status.DiskUsagePercent, 3);
        Assert.Equal(2_097_152_000UL, status.DiskUsedBytes);
        Assert.Equal(8_388_608_000UL, status.DiskTotalBytes);
        Assert.Equal([0.10, 0.20, 0.30], status.LoadAverages);
        Assert.Equal(3_661.12, status.UptimeSeconds, 3);
        Assert.Equal(collectedAt, status.CollectedAt);
    }

    [Fact]
    public void ParseStatusOutputThrowsForMissingFields()
    {
        var host = new ComputerHost("dev", "example.internal", null, null);
        const string output = """
        mem_total_kb=2048000
        mem_available_kb=512000
        disk_total_kb=8192000
        disk_used_kb=2048000
        loadavg=0.10 0.20 0.30
        uptime_seconds=3661.12
        """;

        Assert.Throws<NodeMonitorParseException>(() =>
            NodeMonitorService.ParseStatusOutput(output, host, DateTimeOffset.Now));
    }
}
