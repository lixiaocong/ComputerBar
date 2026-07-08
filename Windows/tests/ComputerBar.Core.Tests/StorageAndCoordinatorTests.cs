using ComputerBar.Core;

namespace ComputerBar.Core.Tests;

public sealed class StorageAndCoordinatorTests
{
    [Fact]
    public async Task JsonSettingsStoreRoundTripsAndNormalizesSettings()
    {
        var root = TestRoot();
        try
        {
            var store = new JsonSettingsStore(new ComputerBarPathSet(root));
            await store.SaveAsync(new ComputerBarSettings(
                ["dev", "dev", ComputerHost.LocalAlias],
                ["dev", ComputerHost.LocalAlias],
                999));

            var loaded = await store.LoadAsync();

            Assert.Equal(["dev", ComputerHost.LocalAlias], loaded.SelectedAliases);
            Assert.Equal(["dev"], loaded.TrayHostAliases);
            Assert.Equal(ComputerBarSettings.MaximumRefreshIntervalSeconds, loaded.RefreshIntervalSeconds);
        }
        finally
        {
            DeleteDirectory(root);
        }
    }

    [Fact]
    public async Task RefreshCoordinatorUsesOnlyOneTrayHost()
    {
        var settings = new InMemorySettingsStore(new ComputerBarSettings(
            [ComputerHost.LocalAlias, "dev"],
            ["dev", ComputerHost.LocalAlias],
            1));
        var coordinator = new RefreshCoordinator(
            settings,
            new StaticHostConfigService([new ComputerHost("dev", "example.internal", "ubuntu", 22)]),
            new StaticMonitorService());

        await coordinator.InitializeAsync();

        var tray = Assert.Single(coordinator.TrayStatuses);
        Assert.Equal("dev", tray.Label);
    }

    private static string TestRoot() =>
        Path.Combine(Path.GetTempPath(), "ComputerBarTests", Guid.NewGuid().ToString("N"));

    private static void DeleteDirectory(string path)
    {
        if (Directory.Exists(path))
        {
            Directory.Delete(path, recursive: true);
        }
    }

    private sealed class InMemorySettingsStore(ComputerBarSettings settings) : ISettingsStore
    {
        private ComputerBarSettings _settings = settings;

        public Task<ComputerBarSettings> LoadAsync(CancellationToken cancellationToken = default) =>
            Task.FromResult(_settings.Normalized());

        public Task SaveAsync(ComputerBarSettings settings, CancellationToken cancellationToken = default)
        {
            _settings = settings.Normalized();
            return Task.CompletedTask;
        }
    }

    private sealed class StaticHostConfigService(IReadOnlyList<ComputerHost> hosts) : IHostConfigService
    {
        public Task<IReadOnlyList<ComputerHost>> LoadHostsAsync(CancellationToken cancellationToken = default) =>
            Task.FromResult(hosts);
    }

    private sealed class StaticMonitorService : INodeMonitorService
    {
        public Task<IReadOnlyList<NodeFetchResult>> FetchStatusesAsync(
            IReadOnlyList<ComputerHost> hosts,
            CancellationToken cancellationToken = default)
        {
            var results = hosts.Select(host => new NodeFetchResult(
                host.Alias,
                new NodeStatus(host, 12, 34, 10, 100, null, null, null, 56, 20, 100, [], 10, DateTimeOffset.Now),
                null)).ToArray();
            return Task.FromResult<IReadOnlyList<NodeFetchResult>>(results);
        }
    }
}
