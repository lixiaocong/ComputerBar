using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Effects;
using ComputerBar.Core;
using Forms = System.Windows.Forms;
using Brush = System.Windows.Media.Brush;
using Button = System.Windows.Controls.Button;
using Color = System.Windows.Media.Color;

namespace ComputerBar.Windows;

public sealed class PopoverWindow : Window
{
    private const double HostColumnWidth = 342;
    private const double HostColumnSpacing = 28;
    private const double MetricBarWidth = 300;
    private const double WindowChromeWidth = 56;

    private readonly RefreshCoordinator _coordinator;
    private readonly Action _showSettings;
    private readonly StackPanel _content = new();
    private readonly List<FrameworkElement> _hostColumns = [];
    private WrapPanel? _hostPanel;
    private bool _isPositioning;
    private int _activeColumnCount = 1;

    public PopoverWindow(RefreshCoordinator coordinator, Action showSettings)
    {
        _coordinator = coordinator;
        _showSettings = showSettings;
        Width = HostColumnWidth + WindowChromeWidth;
        MinHeight = 220;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        Topmost = true;
        ShowActivated = true;
        SizeToContent = SizeToContent.Height;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        Deactivated += (_, _) =>
        {
            if (!_isPositioning && IsVisible)
            {
                Hide();
            }
        };
        PreviewKeyDown += (_, e) =>
        {
            if (e.Key == System.Windows.Input.Key.Escape)
            {
                Hide();
                e.Handled = true;
            }
        };

        Content = new Border
        {
            Margin = new Thickness(8),
            CornerRadius = new CornerRadius(20),
            BorderThickness = new Thickness(1),
            BorderBrush = Brush(Color.FromRgb(215, 210, 218)),
            Background = Brush(Color.FromArgb(248, 255, 248, 252)),
            Padding = new Thickness(18),
            Effect = new DropShadowEffect
            {
                BlurRadius = 24,
                ShadowDepth = 4,
                Direction = 270,
                Opacity = 0.24,
                Color = Color.FromRgb(42, 38, 48)
            },
            Child = _content
        };
    }

    public void ShowNearAnchor(System.Drawing.Point anchorPoint)
    {
        _isPositioning = true;
        try
        {
            WindowState = WindowState.Normal;
            SizeToContent = SizeToContent.Manual;

            var originalOpacity = Opacity;
            if (!IsVisible)
            {
                Opacity = 0;
                Show();
                UpdateLayout();
            }

            var workingArea = Forms.Screen.FromPoint(anchorPoint).WorkingArea;
            var fromDevice = PresentationSource.FromVisual(this)?.CompositionTarget?.TransformFromDevice ?? Matrix.Identity;
            var workTopLeft = fromDevice.Transform(new Point(workingArea.Left, workingArea.Top));
            var workBottomRight = fromDevice.Transform(new Point(workingArea.Right, workingArea.Bottom));
            var anchor = fromDevice.Transform(new Point(anchorPoint.X, anchorPoint.Y));
            var workLeft = workTopLeft.X;
            var workTop = workTopLeft.Y;
            var workRight = workBottomRight.X;
            var workBottom = workBottomRight.Y;
            var workWidth = workRight - workLeft;
            var workHeight = workBottom - workTop;

            var columns = PreferredColumnCount(workWidth);
            _activeColumnCount = columns;
            ApplyHostLayout(_activeColumnCount);
            Width = PreferredWidth(columns, workWidth);
            var root = (FrameworkElement)Content;
            root.Measure(new Size(Width, double.PositiveInfinity));
            Height = Math.Min(root.DesiredSize.Height, Math.Max(220, workHeight - 16));

            Left = Clamp(anchor.X - Width / 2, workLeft + 8, workRight - Width - 8);
            Top = anchor.Y - Height - 12;
            if (Top < workTop + 8)
            {
                Top = anchor.Y + 12;
            }

            Top = Height > workHeight - 16
                ? workTop + 8
                : Clamp(Top, workTop + 8, workBottom - Height - 8);

            Opacity = originalOpacity;
            Show();
            ForceVisible();
            Topmost = false;
            Topmost = true;
            Activate();
            Focus();
        }
        finally
        {
            _isPositioning = false;
        }
    }

    public void Render()
    {
        _content.Children.Clear();
        _hostColumns.Clear();
        _hostPanel = null;
        _content.Children.Add(Header());

        if (_coordinator.HostStatuses.Count == 0)
        {
            _content.Children.Add(EmptyTile());
            _content.Children.Add(Controls());
            return;
        }

        _hostPanel = new WrapPanel
        {
            Orientation = Orientation.Horizontal,
            Margin = new Thickness(0, 0, 0, 8)
        };

        foreach (var state in _coordinator.HostStatuses)
        {
            var column = HostColumn(state);
            _hostColumns.Add(column);
            _hostPanel.Children.Add(column);
        }

        _content.Children.Add(_hostPanel);
        ApplyHostLayout(_activeColumnCount);
        _content.Children.Add(Controls());
    }

    private int PreferredColumnCount(double workWidth)
    {
        var hostCount = Math.Max(1, _coordinator.HostStatuses.Count);
        var availableContentWidth = Math.Max(HostColumnWidth, workWidth - WindowChromeWidth - 16);
        var maxColumns = Math.Max(1, (int)Math.Floor((availableContentWidth + HostColumnSpacing) / (HostColumnWidth + HostColumnSpacing)));
        return Math.Min(hostCount, maxColumns);
    }

    private double PreferredWidth(int columns, double workWidth)
    {
        var contentWidth = columns * HostColumnWidth + Math.Max(0, columns - 1) * HostColumnSpacing;
        return Clamp(contentWidth + WindowChromeWidth, HostColumnWidth + WindowChromeWidth, Math.Max(HostColumnWidth + WindowChromeWidth, workWidth - 16));
    }

    private void ApplyHostLayout(int columns)
    {
        if (_hostPanel is null)
        {
            return;
        }

        columns = Math.Clamp(columns, 1, Math.Max(1, _hostColumns.Count));
        var contentWidth = columns * HostColumnWidth + Math.Max(0, columns - 1) * HostColumnSpacing;
        _hostPanel.Width = contentWidth;
        var lastRowStart = _hostColumns.Count - (_hostColumns.Count % columns == 0 ? columns : _hostColumns.Count % columns);
        for (var index = 0; index < _hostColumns.Count; index++)
        {
            var isLastColumnInRow = (index + 1) % columns == 0;
            var isLastRow = index >= lastRowStart;
            _hostColumns[index].Margin = new Thickness(
                0,
                0,
                isLastColumnInRow ? 0 : HostColumnSpacing,
                isLastRow ? 0 : 14);
        }
    }

    private UIElement Header()
    {
        var grid = new Grid { Margin = new Thickness(0, 0, 0, 16) };
        var titleStack = new StackPanel { Orientation = Orientation.Vertical };
        titleStack.Children.Add(Text("ComputerBar", 22, FontWeights.Bold, Brush(Color.FromRgb(47, 50, 66)), TextWrapping.NoWrap));
        titleStack.Children.Add(Text("Machine usage", 12, FontWeights.Medium, Brush(Color.FromRgb(118, 122, 138)), TextWrapping.NoWrap));
        grid.Children.Add(titleStack);
        return grid;
    }

    private UIElement EmptyTile()
    {
        var panel = new StackPanel();
        if (_coordinator.ConfigErrorMessage is { } configError)
        {
            panel.Children.Add(Text("SSH config problem", 14, FontWeights.SemiBold, Brush(Color.FromRgb(47, 50, 66))));
            panel.Children.Add(Text(configError, 12, FontWeights.Normal, Brush(Color.FromRgb(118, 122, 138))));
        }
        else
        {
            panel.Children.Add(Text("No hosts selected.", 14, FontWeights.SemiBold, Brush(Color.FromRgb(47, 50, 66))));
            panel.Children.Add(Text("Open Settings to choose this PC or SSH hosts.", 12, FontWeights.Normal, Brush(Color.FromRgb(118, 122, 138))));
        }

        return new Border
        {
            CornerRadius = new CornerRadius(14),
            BorderThickness = new Thickness(1),
            BorderBrush = Brush(Color.FromRgb(233, 230, 235)),
            Background = Brush(Color.FromArgb(245, 255, 255, 255)),
            Padding = new Thickness(14, 12, 14, 12),
            Margin = new Thickness(0, 0, 0, 12),
            Child = panel
        };
    }

    private FrameworkElement HostColumn(NodeStatusState state)
    {
        var tint = PanelTint(state);
        var column = new StackPanel
        {
            Width = HostColumnWidth
        };
        column.Children.Add(HostHeader(state, tint));
        column.Children.Add(HostStatusCard(state, tint));
        return column;
    }

    private UIElement HostHeader(NodeStatusState state, Color tint)
    {
        var host = state.Host;
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var labelStack = new StackPanel { Orientation = Orientation.Vertical };
        labelStack.Children.Add(Text(HeaderEyebrow(host), 10, FontWeights.Black, Brush(tint), TextWrapping.NoWrap));
        labelStack.Children.Add(Text(host.DisplayName, 21, FontWeights.Bold, Brush(tint), TextWrapping.NoWrap, trim: true));
        labelStack.Children.Add(Text(HeaderSubtitle(host), 11, FontWeights.Medium, Brush(Color.FromRgb(118, 122, 138)), TextWrapping.NoWrap, trim: true));
        grid.Children.Add(labelStack);

        var statusStack = new StackPanel
        {
            Orientation = Orientation.Vertical,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(8, 0, 0, 0)
        };
        var (value, label) = HeaderMetric(state);
        statusStack.Children.Add(Text(value, 22, FontWeights.Bold, Brush(tint), TextWrapping.NoWrap));
        statusStack.Children.Add(Text(label, 11, FontWeights.SemiBold, Brush(Color.FromRgb(118, 122, 138)), TextWrapping.NoWrap));
        Grid.SetColumn(statusStack, 1);
        grid.Children.Add(statusStack);

        return new Border
        {
            CornerRadius = new CornerRadius(12),
            BorderThickness = new Thickness(1),
            BorderBrush = Brush(tint, 0.18),
            Background = Brush(tint, 0.08),
            Padding = new Thickness(10),
            Margin = new Thickness(0, 0, 0, 10),
            Child = grid
        };
    }

    private UIElement HostStatusCard(NodeStatusState state, Color tint)
    {
        var panel = new StackPanel { Orientation = Orientation.Vertical };
        panel.Children.Add(Text(state.Host.EndpointDescription, 11, FontWeights.Normal, Brush(Color.FromRgb(118, 122, 138)), TextWrapping.Wrap));

        if (state.Status is { } status)
        {
            panel.Children.Add(MetricBlock("CPU Usage", status.CpuUsageText, status.CpuUsagePercent, state.Host.IsLocal ? "Sampled from Windows system times" : "Sampled from /proc/stat"));
            panel.Children.Add(MetricBlock("Memory Usage", status.MemoryUsageText, status.MemoryUsagePercent, status.MemoryUsageSummary));
            panel.Children.Add(MetricBlock("Disk Usage", status.DiskUsageText, status.DiskUsagePercent, status.DiskUsageSummary));
            panel.Children.Add(DetailRow("Load Avg", status.LoadAverageText));
            panel.Children.Add(DetailRow("Uptime", status.UptimeText));
            panel.Children.Add(DetailRow("Updated", status.UpdatedAtText));

            if (state.ErrorMessage is not null)
            {
                var warning = Text(state.ErrorMessage, 11, FontWeights.Normal, Brush(Color.FromRgb(198, 112, 28)));
                warning.Margin = new Thickness(0, 8, 0, 0);
                panel.Children.Add(warning);
            }
        }
        else if (state.ErrorMessage is not null)
        {
            var error = Text(state.ErrorMessage, 12, FontWeights.Normal, Brush(Color.FromRgb(160, 45, 45)));
            error.Margin = new Thickness(0, 8, 0, 0);
            panel.Children.Add(error);
        }
        else
        {
            panel.Children.Add(PlaceholderMetricBlock("CPU Usage"));
            panel.Children.Add(PlaceholderMetricBlock("Memory Usage"));
            panel.Children.Add(PlaceholderMetricBlock("Disk Usage"));
            panel.Children.Add(DetailRow("Load Avg", "--"));
            panel.Children.Add(DetailRow("Uptime", "--"));
            panel.Children.Add(DetailRow("Updated", state.IsLoading ? "Refreshing..." : "--"));
        }

        return new Border
        {
            CornerRadius = new CornerRadius(12),
            BorderThickness = new Thickness(1),
            BorderBrush = Brush(tint, 0.14),
            Background = Brush(tint, 0.06),
            Padding = new Thickness(10),
            Child = panel
        };
    }

    private static UIElement MetricBlock(string title, string percentText, double value, string detail)
    {
        var tint = UsageTint(value);
        var panel = new StackPanel
        {
            Orientation = Orientation.Vertical,
            Margin = new Thickness(0, 10, 0, 0)
        };
        panel.Children.Add(Text(title, 13, FontWeights.SemiBold, Brush(tint), TextWrapping.NoWrap));
        panel.Children.Add(UsageBar(value, tint));

        var labels = new Grid { Margin = new Thickness(0, 4, 0, 0) };
        labels.ColumnDefinitions.Add(new ColumnDefinition());
        labels.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        labels.Children.Add(Text(detail, 11, FontWeights.Medium, Brush(Color.FromRgb(118, 122, 138)), TextWrapping.NoWrap, trim: true));
        var percent = Text(percentText, 11, FontWeights.SemiBold, Brush(tint), TextWrapping.NoWrap);
        percent.Margin = new Thickness(8, 0, 0, 0);
        Grid.SetColumn(percent, 1);
        labels.Children.Add(percent);
        panel.Children.Add(labels);
        return panel;
    }

    private static UIElement PlaceholderMetricBlock(string title)
    {
        var panel = new StackPanel
        {
            Orientation = Orientation.Vertical,
            Margin = new Thickness(0, 10, 0, 0)
        };
        panel.Children.Add(Text(title, 13, FontWeights.SemiBold, Brush(Color.FromRgb(47, 50, 66)), TextWrapping.NoWrap));
        panel.Children.Add(new Border
        {
            Height = 6,
            Width = MetricBarWidth,
            CornerRadius = new CornerRadius(3),
            Background = Brush(Color.FromRgb(104, 108, 122), 0.16),
            Margin = new Thickness(0, 6, 0, 0)
        });
        panel.Children.Add(Text("No data yet", 11, FontWeights.Normal, Brush(Color.FromRgb(118, 122, 138))));
        return panel;
    }

    private static UIElement UsageBar(double percent, Color tint)
    {
        var progress = Math.Clamp(percent, 0, 100) / 100;
        var width = progress <= 0 ? 0 : Math.Max(3, MetricBarWidth * progress);
        var grid = new Grid
        {
            Width = MetricBarWidth,
            Height = 6,
            Margin = new Thickness(0, 6, 0, 0),
            HorizontalAlignment = HorizontalAlignment.Left
        };
        grid.Children.Add(new Border
        {
            CornerRadius = new CornerRadius(3),
            Background = Brush(Color.FromRgb(104, 108, 122), 0.20)
        });
        grid.Children.Add(new Border
        {
            Width = width,
            CornerRadius = new CornerRadius(3),
            Background = Brush(tint),
            HorizontalAlignment = HorizontalAlignment.Left
        });
        return grid;
    }

    private static UIElement DetailRow(string label, string value)
    {
        var grid = new Grid { Margin = new Thickness(0, 7, 0, 0) };
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(Text(label, 11, FontWeights.SemiBold, Brush(Color.FromRgb(118, 122, 138)), TextWrapping.NoWrap));
        var valueText = Text(value, 11, FontWeights.Normal, Brush(Color.FromRgb(47, 50, 66)), TextWrapping.NoWrap, trim: true);
        valueText.Margin = new Thickness(8, 0, 0, 0);
        Grid.SetColumn(valueText, 1);
        grid.Children.Add(valueText);
        return grid;
    }

    private UIElement Controls()
    {
        var wrapper = new StackPanel
        {
            Orientation = Orientation.Vertical,
            Margin = new Thickness(0, 2, 0, 0)
        };
        wrapper.Children.Add(new Border
        {
            Height = 1,
            Background = Brush(Color.FromRgb(223, 219, 226), 0.85),
            Margin = new Thickness(0, 2, 0, 10)
        });

        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var settings = FooterButton("Settings");
        settings.Click += (_, _) => _showSettings();
        grid.Children.Add(settings);

        var exit = FooterButton("Exit", isDestructive: true);
        exit.Click += (_, _) => System.Windows.Application.Current.Shutdown();
        Grid.SetColumn(exit, 2);
        grid.Children.Add(exit);
        wrapper.Children.Add(grid);
        return wrapper;
    }

    private string HeaderEyebrow(ComputerHost host)
    {
        if (_coordinator.IsTrayHost(host))
        {
            return "TRAY ICON";
        }

        if (host.IsLocal)
        {
            return "LOCAL";
        }

        if (_coordinator.SelectionIndex(host) is { } index)
        {
            return $"HOST {index}";
        }

        return "HOST";
    }

    private static string HeaderSubtitle(ComputerHost host) =>
        host.IsLocal ? "this Windows PC" : host.EndpointDescription;

    private static (string Value, string Label) HeaderMetric(NodeStatusState state)
    {
        if (state.Status is { } status)
        {
            return (status.CpuUsageText, "cpu");
        }

        if (state.ErrorMessage is not null)
        {
            return ("!", "error");
        }

        return (state.IsLoading ? "..." : "--", state.IsLoading ? "loading" : "idle");
    }

    private Color PanelTint(NodeStatusState state)
    {
        if (state.ErrorMessage is not null && state.Status is null)
        {
            return Color.FromRgb(211, 61, 61);
        }

        if (state.Status is { } status)
        {
            return UsageTint(status.HighlightUsagePercent);
        }

        if (state.Host.IsLocal)
        {
            return Color.FromRgb(29, 127, 128);
        }

        return (_coordinator.SelectionIndex(state.Host) ?? 0) switch
        {
            2 => Color.FromRgb(61, 112, 210),
            3 => Color.FromRgb(198, 112, 28),
            4 => Color.FromRgb(115, 104, 190),
            _ => Color.FromRgb(41, 148, 89)
        };
    }

    private static Color UsageTint(double percent)
    {
        var rgb = ComputerUsageDisplayColor.ForUsagePercent(percent);
        return Color.FromRgb(ToByte(rgb.Red), ToByte(rgb.Green), ToByte(rgb.Blue));
    }

    private static TextBlock Text(
        string value,
        double size,
        FontWeight weight,
        Brush brush,
        TextWrapping wrapping = TextWrapping.Wrap,
        bool trim = false)
    {
        return new TextBlock
        {
            Text = value,
            FontSize = size,
            FontWeight = weight,
            Foreground = brush,
            TextWrapping = wrapping,
            TextTrimming = trim ? TextTrimming.CharacterEllipsis : TextTrimming.None
        };
    }

    private static Button FooterButton(string label, bool isDestructive = false)
    {
        var normal = Brush(Color.FromArgb(168, 255, 255, 255));
        var hover = Brush(Color.FromArgb(225, 255, 255, 255));
        var pressed = Brush(Color.FromRgb(235, 232, 239));
        var normalBorder = Brush(Color.FromRgb(218, 215, 222), 0.90);
        var hoverBorder = Brush(Color.FromRgb(193, 188, 200));
        var foreground = isDestructive
            ? Brush(Color.FromRgb(151, 54, 68))
            : Brush(Color.FromRgb(51, 55, 71));
        var button = new Button
        {
            Content = label,
            Padding = new Thickness(11, 5, 11, 5),
            MinWidth = 72,
            FontSize = 12,
            FontWeight = FontWeights.Medium,
            Foreground = foreground,
            Background = normal,
            BorderBrush = normalBorder,
            BorderThickness = new Thickness(1),
            Cursor = System.Windows.Input.Cursors.Hand,
            RenderTransform = new TranslateTransform(0, 0),
            Template = RoundedButtonTemplate(8)
        };
        button.MouseEnter += (_, _) =>
        {
            button.Background = hover;
            button.BorderBrush = hoverBorder;
        };
        button.MouseLeave += (_, _) =>
        {
            button.Background = normal;
            button.BorderBrush = normalBorder;
            button.RenderTransform = new TranslateTransform(0, 0);
        };
        button.PreviewMouseDown += (_, _) =>
        {
            button.Background = pressed;
            button.RenderTransform = new TranslateTransform(0, 1);
        };
        button.PreviewMouseUp += (_, _) =>
        {
            button.Background = button.IsMouseOver ? hover : normal;
            button.BorderBrush = button.IsMouseOver ? hoverBorder : normalBorder;
            button.RenderTransform = new TranslateTransform(0, 0);
        };
        return button;
    }

    private static ControlTemplate RoundedButtonTemplate(double radius)
    {
        var border = new FrameworkElementFactory(typeof(Border));
        border.SetValue(Border.CornerRadiusProperty, new CornerRadius(radius));
        border.SetBinding(Border.BackgroundProperty, new System.Windows.Data.Binding(nameof(Control.Background)) { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
        border.SetBinding(Border.BorderBrushProperty, new System.Windows.Data.Binding(nameof(Control.BorderBrush)) { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
        border.SetBinding(Border.BorderThicknessProperty, new System.Windows.Data.Binding(nameof(Control.BorderThickness)) { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });

        var presenter = new FrameworkElementFactory(typeof(ContentPresenter));
        presenter.SetValue(ContentPresenter.HorizontalAlignmentProperty, HorizontalAlignment.Center);
        presenter.SetValue(ContentPresenter.VerticalAlignmentProperty, VerticalAlignment.Center);
        presenter.SetBinding(ContentPresenter.MarginProperty, new System.Windows.Data.Binding(nameof(Control.Padding)) { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
        border.AppendChild(presenter);

        return new ControlTemplate(typeof(Button)) { VisualTree = border };
    }

    private static SolidColorBrush Brush(Color color, double opacity = 1)
    {
        var brush = new SolidColorBrush(color) { Opacity = opacity };
        brush.Freeze();
        return brush;
    }

    private static byte ToByte(double value) =>
        (byte)Math.Clamp((int)Math.Round(value * 255), 0, 255);

    private static double Clamp(double value, double min, double max)
    {
        if (max < min)
        {
            return min;
        }

        return Math.Min(Math.Max(value, min), max);
    }

    private void ForceVisible()
    {
        var handle = new WindowInteropHelper(this).Handle;
        if (handle == IntPtr.Zero)
        {
            return;
        }

        ShowWindow(handle, 5);
        SetForegroundWindow(handle);
    }

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);
}
