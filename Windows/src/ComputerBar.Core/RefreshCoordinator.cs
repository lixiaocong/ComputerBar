namespace ComputerBar.Core;

public sealed class RefreshCoordinator(
    ISettingsStore settingsStore,
    IHostConfigService hostConfigService,
    INodeMonitorService monitorService)
{
    private readonly SemaphoreSlim _refreshGate = new(1, 1);
    private ComputerBarSettings _settings = ComputerBarSettings.Default;
    private IReadOnlyList<ComputerHost> _detectedHosts = [];
    private readonly Dictionary<string, NodeStatusState> _statesByAlias = new(StringComparer.OrdinalIgnoreCase);

    public event EventHandler? Updated;

    public ComputerBarSettings Settings => _settings;
    public IReadOnlyList<ComputerHost> DetectedHosts => _detectedHosts;
    public string? ConfigErrorMessage { get; private set; }
    public DateTimeOffset? LastHostReloadAt { get; private set; }
    public DateTimeOffset? LastRefreshAt { get; private set; }
    public bool IsRefreshing { get; private set; }

    public IReadOnlyList<ComputerHost> AvailableHosts
    {
        get
        {
            var local = ComputerHost.Local();
            var remote = _detectedHosts
                .Where(host => !string.Equals(host.Alias, local.Alias, StringComparison.OrdinalIgnoreCase))
                .ToArray();
            return [local, .. remote];
        }
    }

    public IReadOnlyList<ComputerHost> SelectedHosts
    {
        get
        {
            var byAlias = AvailableHosts.ToDictionary(host => host.Alias, StringComparer.OrdinalIgnoreCase);
            return _settings.SelectedAliases
                .Select(alias => byAlias.TryGetValue(alias, out var host) ? host : null)
                .OfType<ComputerHost>()
                .ToArray();
        }
    }

    public IReadOnlyList<NodeStatusState> HostStatuses =>
        SelectedHosts.Select(StatusStateFor).ToArray();

    public ComputerHost? TrayHost => SelectTrayHost();

    public IReadOnlyList<TrayHostStatus> TrayStatuses => BuildTrayStatuses();

    public string TooltipText => BuildTooltip();

    public async Task InitializeAsync(CancellationToken cancellationToken = default)
    {
        _settings = (await settingsStore.LoadAsync(cancellationToken)).Normalized();
        await ReloadHostsAsync(triggerRefresh: false, cancellationToken);
        Updated?.Invoke(this, EventArgs.Empty);
    }

    public async Task ReloadHostsAsync(
        bool triggerRefresh = true,
        CancellationToken cancellationToken = default)
    {
        try
        {
            _detectedHosts = await hostConfigService.LoadHostsAsync(cancellationToken);
            ConfigErrorMessage = null;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            _detectedHosts = [];
            ConfigErrorMessage = ex.Message;
        }

        LastHostReloadAt = DateTimeOffset.Now;
        NormalizeStateToAvailableHosts();
        Updated?.Invoke(this, EventArgs.Empty);

        if (triggerRefresh)
        {
            await RefreshNowAsync(cancellationToken);
        }
    }

    public async Task RefreshNowAsync(CancellationToken cancellationToken = default)
    {
        await _refreshGate.WaitAsync(cancellationToken);
        try
        {
            _settings = (await settingsStore.LoadAsync(cancellationToken)).Normalized();
            NormalizeStateToAvailableHosts();
            var hosts = HostsForRefresh();
            if (hosts.Count == 0)
            {
                LastRefreshAt = DateTimeOffset.Now;
                Updated?.Invoke(this, EventArgs.Empty);
                return;
            }

            IsRefreshing = true;
            foreach (var host in hosts)
            {
                var state = StatusStateFor(host);
                _statesByAlias[host.Alias] = state with { IsLoading = true };
            }
            Updated?.Invoke(this, EventArgs.Empty);

            var results = await monitorService.FetchStatusesAsync(hosts, cancellationToken);
            foreach (var result in results)
            {
                var host = AvailableHosts.FirstOrDefault(candidate =>
                    string.Equals(candidate.Alias, result.Alias, StringComparison.OrdinalIgnoreCase));
                if (host is null)
                {
                    continue;
                }

                var existing = StatusStateFor(host);
                _statesByAlias[result.Alias] = result.Status is { } status
                    ? existing with { IsLoading = false, Status = status, ErrorMessage = null }
                    : existing with { IsLoading = false, ErrorMessage = result.ErrorMessage };
            }

            LastRefreshAt = DateTimeOffset.Now;
            IsRefreshing = false;
            Updated?.Invoke(this, EventArgs.Empty);
        }
        finally
        {
            if (IsRefreshing)
            {
                IsRefreshing = false;
                Updated?.Invoke(this, EventArgs.Empty);
            }

            _refreshGate.Release();
        }
    }

    public NodeStatusState StatusStateFor(ComputerHost host)
    {
        if (_statesByAlias.TryGetValue(host.Alias, out var state))
        {
            return state with { Host = host };
        }

        return NodeStatusState.Idle(host);
    }

    public bool IsHostSelected(ComputerHost host) =>
        _settings.SelectedAliases.Contains(host.Alias, StringComparer.OrdinalIgnoreCase);

    public bool IsTrayHost(ComputerHost host)
    {
        var trayHost = TrayHost;
        return trayHost is not null
            && string.Equals(trayHost.Alias, host.Alias, StringComparison.OrdinalIgnoreCase);
    }

    public int? SelectionIndex(ComputerHost host)
    {
        for (var index = 0; index < _settings.SelectedAliases.Count; index++)
        {
            if (string.Equals(_settings.SelectedAliases[index], host.Alias, StringComparison.OrdinalIgnoreCase))
            {
                return index + 1;
            }
        }

        return null;
    }

    public async Task SetHostSelectedAsync(
        string alias,
        bool selected,
        CancellationToken cancellationToken = default)
    {
        var settings = (await settingsStore.LoadAsync(cancellationToken)).Normalized();
        var selectedAliases = settings.SelectedAliases.ToList();
        selectedAliases.RemoveAll(value => string.Equals(value, alias, StringComparison.OrdinalIgnoreCase));
        if (selected)
        {
            selectedAliases.Add(alias);
        }

        var trayAliases = settings.TrayHostAliases
            .Where(value => selectedAliases.Contains(value, StringComparer.OrdinalIgnoreCase))
            .ToArray();
        await SaveAndReloadSettingsAsync(settings with
        {
            SelectedAliases = selectedAliases,
            TrayHostAliases = trayAliases
        }, cancellationToken);
    }

    public async Task SelectAllHostsAsync(CancellationToken cancellationToken = default)
    {
        await SaveAndReloadSettingsAsync(_settings with
        {
            SelectedAliases = AvailableHosts.Select(host => host.Alias).ToArray()
        }, cancellationToken);
    }

    public async Task ClearSelectionAsync(CancellationToken cancellationToken = default)
    {
        await SaveAndReloadSettingsAsync(_settings with
        {
            SelectedAliases = [],
            TrayHostAliases = []
        }, cancellationToken);
    }

    public async Task SetTrayHostAsync(string? alias, CancellationToken cancellationToken = default)
    {
        var trayAliases = string.IsNullOrWhiteSpace(alias) ? [] : new[] { alias.Trim() };
        var selectedAliases = _settings.SelectedAliases.ToList();
        if (!string.IsNullOrWhiteSpace(alias)
            && !selectedAliases.Contains(alias, StringComparer.OrdinalIgnoreCase))
        {
            selectedAliases.Add(alias);
        }

        await SaveAndReloadSettingsAsync(_settings with
        {
            SelectedAliases = selectedAliases,
            TrayHostAliases = trayAliases
        }, cancellationToken);
    }

    public async Task SetRefreshIntervalAsync(int seconds, CancellationToken cancellationToken = default)
    {
        await SaveAndReloadSettingsAsync(_settings with
        {
            RefreshIntervalSeconds = seconds
        }, cancellationToken);
    }

    private async Task SaveAndReloadSettingsAsync(
        ComputerBarSettings settings,
        CancellationToken cancellationToken)
    {
        await settingsStore.SaveAsync(NormalizedAgainstAvailableHosts(settings), cancellationToken);
        _settings = (await settingsStore.LoadAsync(cancellationToken)).Normalized();
        NormalizeStateToAvailableHosts();
        Updated?.Invoke(this, EventArgs.Empty);
    }

    private ComputerBarSettings NormalizedAgainstAvailableHosts(ComputerBarSettings settings)
    {
        var availableAliases = AvailableHosts
            .Select(host => host.Alias)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var selected = settings.SelectedAliases
            .Where(availableAliases.Contains)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        var selectedAliasSet = selected.ToHashSet(StringComparer.OrdinalIgnoreCase);
        var tray = settings.TrayHostAliases
            .Where(selectedAliasSet.Contains)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Take(ComputerBarSettings.MaximumTrayHosts)
            .ToArray();

        return settings with
        {
            SelectedAliases = selected,
            TrayHostAliases = tray,
            RefreshIntervalSeconds = ComputerBarSettings.NormalizeRefreshInterval(settings.RefreshIntervalSeconds)
        };
    }

    private void NormalizeStateToAvailableHosts()
    {
        _settings = NormalizedAgainstAvailableHosts(_settings).Normalized();
        var availableAliases = AvailableHosts
            .Select(host => host.Alias)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var alias in _statesByAlias.Keys.Where(alias => !availableAliases.Contains(alias)).ToArray())
        {
            _statesByAlias.Remove(alias);
        }
    }

    private ComputerHost? SelectTrayHost()
    {
        var byAlias = AvailableHosts.ToDictionary(host => host.Alias, StringComparer.OrdinalIgnoreCase);
        foreach (var alias in _settings.TrayHostAliases)
        {
            if (byAlias.TryGetValue(alias, out var host))
            {
                return host;
            }
        }

        return SelectedHosts.FirstOrDefault();
    }

    private IReadOnlyList<ComputerHost> HostsForRefresh()
    {
        var hosts = new List<ComputerHost>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var host in SelectedHosts)
        {
            if (seen.Add(host.Alias))
            {
                hosts.Add(host);
            }
        }

        if (TrayHost is { } trayHost && seen.Add(trayHost.Alias))
        {
            hosts.Add(trayHost);
        }

        return hosts;
    }

    private IReadOnlyList<TrayHostStatus> BuildTrayStatuses()
    {
        if (TrayHost is not { } host)
        {
            return [new TrayHostStatus("--", null)];
        }

        var state = StatusStateFor(host);
        if (state.ErrorMessage is not null && state.Status is null)
        {
            return [new TrayHostStatus(TrayLabel(host), null, true, state.ErrorMessage)];
        }

        return [new TrayHostStatus(
            TrayLabel(host),
            state.Status?.HighlightUsagePercent,
            false,
            state.ErrorMessage)];
    }

    private string BuildTooltip()
    {
        if (TrayHost is not { } host)
        {
            return ConfigErrorMessage is null
                ? "ComputerBar - no hosts selected"
                : $"ComputerBar - {ConfigErrorMessage}";
        }

        var state = StatusStateFor(host);
        if (state.Status is { } status)
        {
            return $"{host.DisplayName}: CPU {status.CpuUsageText}, memory {status.MemoryUsageText}, disk {status.DiskUsageText}";
        }

        if (state.ErrorMessage is not null)
        {
            return $"{host.DisplayName}: {state.ErrorMessage}";
        }

        return $"{host.DisplayName}: waiting for first refresh";
    }

    public static string TrayLabel(ComputerHost host)
    {
        if (host.IsLocal)
        {
            return "pc";
        }

        var token = new string(host.Alias
            .ToLowerInvariant()
            .Where(char.IsLetterOrDigit)
            .Take(4)
            .ToArray());
        return token.Length == 0 ? "host" : token;
    }
}
