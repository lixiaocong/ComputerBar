namespace ComputerBar.Core;

public interface ISettingsStore
{
    Task<ComputerBarSettings> LoadAsync(CancellationToken cancellationToken = default);
    Task SaveAsync(ComputerBarSettings settings, CancellationToken cancellationToken = default);
}

public interface IHostConfigService
{
    Task<IReadOnlyList<ComputerHost>> LoadHostsAsync(CancellationToken cancellationToken = default);
}

public interface INodeMonitorService
{
    Task<IReadOnlyList<NodeFetchResult>> FetchStatusesAsync(
        IReadOnlyList<ComputerHost> hosts,
        CancellationToken cancellationToken = default);
}

public interface ITrayIconRenderer
{
    IconRenderResult Render(IReadOnlyList<TrayHostStatus> statuses, int size = 32);
}
