using System;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using ComputerBar.Core;

namespace ComputerBar.Windows;

public partial class App : System.Windows.Application
{
    private const string SingleInstanceMutexName = @"Local\ComputerBar.Windows.SingleInstance.v1";

    private TrayController? _trayController;
    private RefreshCoordinator? _coordinator;
    private CancellationTokenSource? _timerCts;
    private Mutex? _singleInstanceMutex;
    private bool _ownsSingleInstanceMutex;

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        if (!TryAcquireSingleInstance())
        {
            Shutdown();
            return;
        }

        var settingsStore = new JsonSettingsStore(ComputerBarPaths.Default);
        var hostConfig = new SshConfigService();
        var monitor = new NodeMonitorService();
        _coordinator = new RefreshCoordinator(settingsStore, hostConfig, monitor);
        _trayController = new TrayController(_coordinator, new TrayIconRenderer());

        await _coordinator.InitializeAsync();
        _trayController.Show();
        _ = RefreshIgnoringErrorsAsync();
        StartRefreshLoop();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _timerCts?.Cancel();
        _trayController?.Dispose();
        ReleaseSingleInstance();
        base.OnExit(e);
    }

    private bool TryAcquireSingleInstance()
    {
        _singleInstanceMutex = new Mutex(
            initiallyOwned: true,
            name: SingleInstanceMutexName,
            createdNew: out _ownsSingleInstanceMutex);
        if (_ownsSingleInstanceMutex)
        {
            return true;
        }

        _singleInstanceMutex.Dispose();
        _singleInstanceMutex = null;
        return false;
    }

    private void ReleaseSingleInstance()
    {
        if (_singleInstanceMutex is null)
        {
            return;
        }

        if (_ownsSingleInstanceMutex)
        {
            _singleInstanceMutex.ReleaseMutex();
        }

        _singleInstanceMutex.Dispose();
        _singleInstanceMutex = null;
        _ownsSingleInstanceMutex = false;
    }

    private void StartRefreshLoop()
    {
        _timerCts = new CancellationTokenSource();
        _ = Task.Run(async () =>
        {
            while (!_timerCts.IsCancellationRequested)
            {
                var delay = TimeSpan.FromSeconds(_coordinator?.Settings.RefreshIntervalSeconds ?? 1);
                await Task.Delay(delay, _timerCts.Token);
                await RefreshIgnoringErrorsAsync();
            }
        }, _timerCts.Token);
    }

    private async Task RefreshIgnoringErrorsAsync()
    {
        if (_coordinator is null)
        {
            return;
        }

        try
        {
            await _coordinator.RefreshNowAsync();
        }
        catch
        {
            // Host-level failures are represented in RefreshCoordinator states.
        }
    }
}
