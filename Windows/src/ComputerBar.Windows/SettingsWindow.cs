using System;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using ComputerBar.Core;
using Brush = System.Windows.Media.Brush;
using Brushes = System.Windows.Media.Brushes;
using Button = System.Windows.Controls.Button;
using Color = System.Windows.Media.Color;
using FontFamily = System.Windows.Media.FontFamily;
using TextBox = System.Windows.Controls.TextBox;

namespace ComputerBar.Windows;

public sealed class SettingsWindow : Window
{
    private readonly RefreshCoordinator _coordinator;
    private readonly StackPanel _hostRows = new();
    private readonly StackPanel _trayRadios = new();
    private readonly TextBox _refreshInterval = new();
    private readonly TextBlock _configStatus = new();
    private readonly TextBlock _status = new();
    private bool _isRendering;

    public SettingsWindow(RefreshCoordinator coordinator)
    {
        _coordinator = coordinator;
        Title = "ComputerBar Settings";
        Width = 680;
        SizeToContent = SizeToContent.Height;
        MaxHeight = Math.Min(760, SystemParameters.WorkArea.Height - 80);
        MinWidth = 560;
        Content = BuildContent();
    }

    public void Render()
    {
        _isRendering = true;
        try
        {
            _refreshInterval.Text = _coordinator.Settings.RefreshIntervalSeconds.ToString();
            RenderConfigStatus();
            RenderHostRows();
            RenderTrayRadios();
        }
        finally
        {
            _isRendering = false;
        }
    }

    private UIElement BuildContent()
    {
        var stack = new StackPanel
        {
            Margin = new Thickness(18)
        };

        stack.Children.Add(Heading("Hosts"));
        _configStatus.Margin = new Thickness(0, 0, 0, 10);
        stack.Children.Add(_configStatus);
        stack.Children.Add(_hostRows);

        var hostButtons = new UniformGrid { Columns = 3, Margin = new Thickness(0, 10, 0, 18) };
        hostButtons.Children.Add(Button("Reload Hosts", async () => await RunAsync(async () => await _coordinator.ReloadHostsAsync())));
        hostButtons.Children.Add(Button("Select All", async () => await RunAsync(async () =>
        {
            await _coordinator.SelectAllHostsAsync();
            await _coordinator.RefreshNowAsync();
        })));
        hostButtons.Children.Add(Button("Clear Selection", async () => await RunAsync(async () => await _coordinator.ClearSelectionAsync())));
        stack.Children.Add(hostButtons);

        stack.Children.Add(Heading("Tray Icon Host"));
        stack.Children.Add(new TextBlock
        {
            Text = "Windows tray icon shows one selected machine as a usage pie.",
            Foreground = Brushes.DimGray,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 0, 0, 6)
        });
        _trayRadios.Margin = new Thickness(0, 0, 0, 18);
        stack.Children.Add(_trayRadios);

        stack.Children.Add(Heading("Refresh"));
        var refreshPanel = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(0, 0, 0, 8)
        };
        _refreshInterval.Width = 82;
        _refreshInterval.Height = 34;
        _refreshInterval.Padding = new Thickness(8, 0, 8, 0);
        _refreshInterval.VerticalContentAlignment = VerticalAlignment.Center;
        _refreshInterval.Margin = new Thickness(0, 0, 8, 0);
        refreshPanel.Children.Add(_refreshInterval);
        refreshPanel.Children.Add(Button("Save Interval", async () => await RunAsync(async () =>
        {
            if (int.TryParse(_refreshInterval.Text, out var seconds))
            {
                await _coordinator.SetRefreshIntervalAsync(seconds);
            }
        })));
        refreshPanel.Children.Add(Button("Refresh Now", async () => await RunAsync(async () => await _coordinator.RefreshNowAsync())));
        stack.Children.Add(refreshPanel);

        _status.Foreground = Brushes.DimGray;
        _status.Margin = new Thickness(0, 8, 0, 0);
        _status.TextWrapping = TextWrapping.Wrap;
        _status.Visibility = Visibility.Collapsed;
        stack.Children.Add(_status);

        return new ScrollViewer
        {
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            MaxHeight = Math.Min(740, SystemParameters.WorkArea.Height - 90),
            Content = stack
        };
    }

    private void RenderConfigStatus()
    {
        if (_coordinator.ConfigErrorMessage is { } configError)
        {
            _configStatus.Text = configError;
            _configStatus.Foreground = Brushes.DarkOrange;
        }
        else
        {
            _configStatus.Text = $"SSH config: {ComputerBarPaths.DefaultSshConfigFile}";
            _configStatus.Foreground = Brushes.DimGray;
        }
    }

    private void RenderHostRows()
    {
        _hostRows.Children.Clear();
        foreach (var host in _coordinator.AvailableHosts)
        {
            _hostRows.Children.Add(HostRow(host));
        }
    }

    private UIElement HostRow(ComputerHost host)
    {
        var isSelected = _coordinator.IsHostSelected(host);
        var state = _coordinator.StatusStateFor(host);
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition());

        var checkbox = new CheckBox
        {
            IsChecked = isSelected,
            VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(0, 4, 12, 0)
        };
        checkbox.Checked += async (_, _) => await ToggleHostAsync(host, true);
        checkbox.Unchecked += async (_, _) => await ToggleHostAsync(host, false);
        grid.Children.Add(checkbox);

        var details = new StackPanel { Orientation = Orientation.Vertical };
        var title = new TextBlock
        {
            Text = host.DisplayName,
            FontWeight = FontWeights.SemiBold,
            FontSize = 14
        };
        details.Children.Add(title);
        details.Children.Add(new TextBlock
        {
            Text = host.EndpointDescription,
            FontFamily = new FontFamily("Consolas"),
            FontSize = 11,
            Foreground = Brushes.DimGray,
            TextWrapping = TextWrapping.Wrap
        });
        details.Children.Add(new TextBlock
        {
            Text = HostStatusSummary(state),
            Foreground = Brushes.DimGray,
            FontSize = 11,
            TextWrapping = TextWrapping.Wrap
        });
        Grid.SetColumn(details, 1);
        grid.Children.Add(details);

        return new Border
        {
            CornerRadius = new CornerRadius(10),
            BorderThickness = new Thickness(1),
            BorderBrush = Brush(Color.FromRgb(228, 226, 232)),
            Background = Brush(Color.FromRgb(250, 250, 252)),
            Padding = new Thickness(10),
            Margin = new Thickness(0, 0, 0, 8),
            Child = grid
        };
    }

    private void RenderTrayRadios()
    {
        _trayRadios.Children.Clear();
        var automatic = new RadioButton
        {
            Content = "Automatic first selected host",
            IsChecked = _coordinator.Settings.TrayHostAliases.Count == 0,
            GroupName = "TrayHost",
            Margin = new Thickness(0, 3, 0, 3)
        };
        automatic.Checked += async (_, _) =>
        {
            if (!_isRendering)
            {
                await RunAsync(async () => await _coordinator.SetTrayHostAsync(null));
            }
        };
        _trayRadios.Children.Add(automatic);

        foreach (var host in _coordinator.SelectedHosts)
        {
            var radio = new RadioButton
            {
                Content = $"{host.DisplayName} - {host.EndpointDescription}",
                IsChecked = _coordinator.Settings.TrayHostAliases.Contains(host.Alias, StringComparer.OrdinalIgnoreCase),
                GroupName = "TrayHost",
                Tag = host.Alias,
                Margin = new Thickness(0, 3, 0, 3)
            };
            radio.Checked += async (_, _) =>
            {
                if (!_isRendering)
                {
                    await RunAsync(async () => await _coordinator.SetTrayHostAsync((string)radio.Tag));
                }
            };
            _trayRadios.Children.Add(radio);
        }
    }

    private async Task ToggleHostAsync(ComputerHost host, bool selected)
    {
        if (_isRendering)
        {
            return;
        }

        await RunAsync(async () =>
        {
            await _coordinator.SetHostSelectedAsync(host.Alias, selected);
            if (selected)
            {
                await _coordinator.RefreshNowAsync();
            }
        });
    }

    private async Task RunAsync(Func<Task> action)
    {
        try
        {
            ShowStatus("Working...", Brushes.DimGray);
            await action();
            Render();
            HideStatus();
        }
        catch (Exception ex)
        {
            ShowStatus(ex.Message, Brushes.Firebrick);
        }
    }

    private void ShowStatus(string? message, Brush brush)
    {
        if (string.IsNullOrWhiteSpace(message))
        {
            HideStatus();
            return;
        }

        _status.Text = message.Trim();
        _status.Foreground = brush;
        _status.Visibility = Visibility.Visible;
    }

    private void HideStatus()
    {
        _status.Text = "";
        _status.Visibility = Visibility.Collapsed;
    }

    private static string HostStatusSummary(NodeStatusState state)
    {
        if (state.Status is { } status)
        {
            return status.UsageSummary;
        }

        if (state.ErrorMessage is not null)
        {
            return state.ErrorMessage;
        }

        return state.IsLoading ? "Refreshing..." : "No data yet.";
    }

    private static TextBlock Heading(string text) =>
        new()
        {
            Text = text,
            FontSize = 16,
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(0, 8, 0, 8)
        };

    private static Button Button(string text, Func<Task> action)
    {
        var button = new Button
        {
            Content = text,
            Margin = new Thickness(3),
            Padding = new Thickness(10, 5, 10, 5),
            MinHeight = 34
        };
        button.Click += async (_, _) => await action();
        return button;
    }

    private static SolidColorBrush Brush(Color color, double opacity = 1)
    {
        var brush = new SolidColorBrush(color) { Opacity = opacity };
        brush.Freeze();
        return brush;
    }
}
