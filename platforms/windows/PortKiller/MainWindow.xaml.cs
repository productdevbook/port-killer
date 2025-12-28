using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using Microsoft.Extensions.DependencyInjection;
using PortKiller.Models;
using PortKiller.ViewModels;
using PortKiller.Helpers;

namespace PortKiller;

public partial class MainWindow : Window
{
    private readonly MainViewModel _viewModel;
    private readonly TunnelViewModel _tunnelViewModel;
    private Hardcodet.Wpf.TaskbarNotification.TaskbarIcon? _trayIcon;
    private bool _isShuttingDown = false;

    public MainWindow()
    {
        InitializeComponent();

        _viewModel = App.Services.GetRequiredService<MainViewModel>();
        _tunnelViewModel = App.Services.GetRequiredService<TunnelViewModel>();
        InitializeAsync();
        
        // Setup keyboard shortcuts
        SetupKeyboardShortcuts();
        
        // Initialize system tray icon
        InitializeTrayIcon();
        
        // Ensure window is visible and activated on startup
        Loaded += (s, e) =>
        {
            Show();
            Activate();
            WindowState = WindowState.Normal;
        };
    }

    private void InitializeTrayIcon()
    {
        _trayIcon = new Hardcodet.Wpf.TaskbarNotification.TaskbarIcon
        {
            ToolTipText = "PortKiller",
            Visibility = Visibility.Visible
        };

        // Create icon from text (simple fallback)
        _trayIcon.Icon = CreateTrayIcon();

        // Setup context menu
        var contextMenu = new ContextMenu
        {
            Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(42, 42, 42)),
            Foreground = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(224, 224, 224))
        };

        var openItem = new MenuItem { Header = "🪟  Open Main Window", FontWeight = FontWeights.SemiBold };
        openItem.Click += TrayOpenMain_Click;
        contextMenu.Items.Add(openItem);
        
        contextMenu.Items.Add(new Separator());

        var refreshItem = new MenuItem { Header = "○  Refresh", InputGestureText = "Ctrl+R" };
        refreshItem.Click += TrayRefresh_Click;
        contextMenu.Items.Add(refreshItem);

        var killAllItem = new MenuItem { Header = "✕  Kill All", InputGestureText = "Ctrl+K" };
        killAllItem.Click += TrayKillAll_Click;
        contextMenu.Items.Add(killAllItem);

        contextMenu.Items.Add(new Separator());

        var settingsItem = new MenuItem { Header = "⚙  Settings" };
        settingsItem.Click += TraySettings_Click;
        contextMenu.Items.Add(settingsItem);

        var quitItem = new MenuItem { Header = "×  Quit", InputGestureText = "Ctrl+Q" };
        quitItem.Click += TrayQuit_Click;
        contextMenu.Items.Add(quitItem);

        _trayIcon.ContextMenu = contextMenu;
        _trayIcon.TrayLeftMouseDown += TrayIcon_Click;
    }

    private System.Drawing.Icon CreateTrayIcon()
    {
        // Create a simple icon with a network symbol
        var bitmap = new System.Drawing.Bitmap(16, 16);
        using (var g = System.Drawing.Graphics.FromImage(bitmap))
        {
            g.Clear(System.Drawing.Color.Transparent);
            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            
            // Draw a simple network/port icon (circle with dot)
            using (var pen = new System.Drawing.Pen(System.Drawing.Color.White, 2))
            {
                g.DrawEllipse(pen, 3, 3, 10, 10);
                g.FillEllipse(System.Drawing.Brushes.White, 6, 6, 4, 4);
            }
        }
        
        return System.Drawing.Icon.FromHandle(bitmap.GetHicon());
    }

    private async void InitializeAsync()
    {
        await _viewModel.InitializeAsync();
        UpdateUI();

        // Subscribe to property changes
        _viewModel.PropertyChanged += (s, e) =>
        {
            if (e.PropertyName == nameof(_viewModel.FilteredPorts) ||
                e.PropertyName == nameof(_viewModel.IsScanning))
            {
                Dispatcher.Invoke(UpdateUI);
            }
            
            if (e.PropertyName == nameof(_viewModel.Ports))
            {
                Dispatcher.Invoke(UpdateTrayMenu);
            }
        };
    }

    private void UpdateUI()
    {
        // Update ports list
        PortsListView.ItemsSource = _viewModel.FilteredPorts;

        // Update empty state
        EmptyState.Visibility = _viewModel.FilteredPorts.Count == 0 ? Visibility.Visible : Visibility.Collapsed;

        // Update status
        StatusText.Text = _viewModel.IsScanning
            ? "Scanning ports..."
            : $"{_viewModel.FilteredPorts.Count} port(s) listening";
    }

    // Window Controls
    private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ClickCount == 2)
        {
            WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
        }
        else
        {
            DragMove();
        }
    }

    private void MinimizeButton_Click(object sender, RoutedEventArgs e)
    {
        WindowState = WindowState.Minimized;
    }

    private void MaximizeButton_Click(object sender, RoutedEventArgs e)
    {
        WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e)
    {
        Close();
    }

    private async void RefreshButton_Click(object sender, RoutedEventArgs e)
    {
        await _viewModel.RefreshPortsCommand.ExecuteAsync(null);
    }

    private void SearchBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        _viewModel.Search(SearchBox.Text);
    }

    private void SidebarButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button button && button.Tag is string tag)
        {
            if (Enum.TryParse<SidebarItem>(tag, out var sidebarItem))
            {
                _viewModel.SelectedSidebarItem = sidebarItem;
                HeaderText.Text = sidebarItem.GetTitle();
                
                // Toggle between ports view and tunnels view
                if (sidebarItem == SidebarItem.CloudflareTunnels)
                {
                    PortsPanel.Visibility = Visibility.Collapsed;
                    DetailPanel.Visibility = Visibility.Collapsed;
                    TunnelsPanel.Visibility = Visibility.Visible;
                    UpdateTunnelsUI();
                }
                else
                {
                    TunnelsPanel.Visibility = Visibility.Collapsed;
                    PortsPanel.Visibility = Visibility.Visible;
                }
                
                // Highlight selected button (optional enhancement)
                foreach (var child in ((button.Parent as Panel)?.Children ?? new UIElementCollection(null, null)))
                {
                    if (child is Button btn)
                    {
                        btn.Background = System.Windows.Media.Brushes.Transparent;
                    }
                }
                button.Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromArgb(25, 52, 152, 219));
            }
        }
    }

    private void PortItem_Click(object sender, MouseButtonEventArgs e)
    {
        if (sender is Border border && border.Tag is PortInfo port)
        {
            _viewModel.SelectedPort = port;
            ShowPortDetails(port);
        }
    }

    private void ShowPortDetails(PortInfo port)
    {
        DetailPanel.Visibility = Visibility.Visible;

        DetailPort.Text = port.DisplayPort;
        DetailProcess.Text = port.ProcessName;
        DetailPid.Text = port.Pid.ToString();
        DetailAddress.Text = port.Address;
        DetailUser.Text = port.User;
        DetailCommand.Text = port.Command;

        // Update favorite button
        FavoriteButton.Content = _viewModel.IsFavorite(port.Port)
            ? "⭐ Remove from Favorites"
            : "⭐ Add to Favorites";

        // Update watch button
        WatchButton.Content = _viewModel.IsWatched(port.Port)
            ? "👁 Unwatch Port"
            : "👁 Watch Port";
    }

    private async void KillButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button button && button.Tag is PortInfo port)
        {
            var dialog = new ConfirmDialog(
                $"Are you sure you want to kill the process on port {port.Port}?",
                $"Process: {port.ProcessName}\nPID: {port.Pid}\n\nThis action cannot be undone.",
                "Kill Process")
            {
                Owner = this
            };
            
            dialog.ShowDialog();

            if (dialog.Result)
            {
                await _viewModel.KillProcessCommand.ExecuteAsync(port);
            }
        }
    }

    private void FavoriteButton_Click(object sender, RoutedEventArgs e)
    {
        if (_viewModel.SelectedPort != null)
        {
            _viewModel.ToggleFavoriteCommand.Execute(_viewModel.SelectedPort.Port);
            ShowPortDetails(_viewModel.SelectedPort);
        }
    }

    private void WatchButton_Click(object sender, RoutedEventArgs e)
    {
        if (_viewModel.SelectedPort != null)
        {
            var port = _viewModel.SelectedPort.Port;

            if (_viewModel.IsWatched(port))
            {
                _viewModel.RemoveWatchedPortCommand.Execute(port);
            }
            else
            {
                _viewModel.AddWatchedPortCommand.Execute(port);
            }

            ShowPortDetails(_viewModel.SelectedPort);
        }
    }

    private async void ShareTunnelButton_Click(object sender, RoutedEventArgs e)
    {
        if (_viewModel.SelectedPort == null)
            return;

        var port = _viewModel.SelectedPort.Port;

        // Navigate to Cloudflare Tunnels panel in sidebar
        _viewModel.SelectedSidebarItem = SidebarItem.CloudflareTunnels;
        HeaderText.Text = SidebarItem.CloudflareTunnels.GetTitle();
        
        // Toggle to tunnels view
        PortsPanel.Visibility = Visibility.Collapsed;
        DetailPanel.Visibility = Visibility.Collapsed;
        TunnelsPanel.Visibility = Visibility.Visible;
        UpdateTunnelsUI();

        // Start tunnel for the selected port
        await _tunnelViewModel.StartTunnelAsync(port);
    }

    // Window loaded event - enable blur for sidebar only
    private void Window_Loaded(object sender, RoutedEventArgs e)
    {
        try
        {
            // Enable acrylic blur effect for the entire window (sidebar will show blur through transparency)
            WindowBlurHelper.EnableAcrylicBlur(this, blurOpacity: 180, blurColor: 0x1A1A1A);
        }
        catch (Exception ex)
        {
            // Blur not supported on this system
            System.Diagnostics.Debug.WriteLine($"Blur effect not supported: {ex.Message}");
        }
    }

    // Keyboard shortcuts
    private void SetupKeyboardShortcuts()
    {
        var refreshGesture = new KeyGesture(Key.R, ModifierKeys.Control);
        var killAllGesture = new KeyGesture(Key.K, ModifierKeys.Control);
        var quitGesture = new KeyGesture(Key.Q, ModifierKeys.Control);

        InputBindings.Add(new KeyBinding(_viewModel.RefreshPortsCommand, refreshGesture));
        InputBindings.Add(new KeyBinding(ApplicationCommands.Close, quitGesture));
        
        CommandBindings.Add(new CommandBinding(ApplicationCommands.Close, (s, e) => Close()));
    }

    // System tray icon handlers
    private void TrayIcon_Click(object sender, RoutedEventArgs e)
    {
        // Show mini popup window near tray
        var miniWindow = new MiniPortKillerWindow();
        miniWindow.ShowNearTray();
    }

    private async void TrayRefresh_Click(object sender, RoutedEventArgs e)
    {
        await _viewModel.RefreshPortsCommand.ExecuteAsync(null);
    }

    private async void TrayKillAll_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new ConfirmDialog(
            "Are you sure you want to kill ALL processes on listening ports?",
            $"This will terminate {_viewModel.Ports.Count} process(es).\n\nThis action cannot be undone.",
            "Kill All Processes")
        {
            Owner = this
        };
        
        dialog.ShowDialog();

        if (dialog.Result)
        {
            foreach (var port in _viewModel.Ports.ToList())
            {
                try
                {
                    await _viewModel.KillProcessCommand.ExecuteAsync(port);
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"Failed to kill process on port {port.Port}: {ex.Message}");
                }
            }
        }
    }

    // Cloudflare Tunnels Methods
    private void UpdateTunnelsUI()
    {
        // Bind tunnels list to view model
        TunnelsListView.ItemsSource = _tunnelViewModel.Tunnels;
        
        // Update empty state
        TunnelsEmptyState.Visibility = _tunnelViewModel.Tunnels.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        
        // Update status bar
        var count = _tunnelViewModel.ActiveTunnelCount;
        TunnelStatusText.Text = $"{count} active tunnel(s)";
        TunnelStatusDot.Fill = count > 0 
            ? new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(46, 204, 113))
            : new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(128, 128, 128));
        
        // Update Stop All button visibility
        StopAllTunnelsButton.Visibility = _tunnelViewModel.Tunnels.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        
        // Update cloudflared installed indicator
        CloudflaredWarning.Visibility = _tunnelViewModel.IsCloudflaredInstalled ? Visibility.Collapsed : Visibility.Visible;
        CloudflaredInstalledIndicator.Visibility = _tunnelViewModel.IsCloudflaredInstalled ? Visibility.Visible : Visibility.Collapsed;
        
        // Subscribe to collection changes if not already
        _tunnelViewModel.Tunnels.CollectionChanged -= OnTunnelsCollectionChanged;
        _tunnelViewModel.Tunnels.CollectionChanged += OnTunnelsCollectionChanged;
    }

    private void OnTunnelsCollectionChanged(object? sender, System.Collections.Specialized.NotifyCollectionChangedEventArgs e)
    {
        Dispatcher.Invoke(() =>
        {
            TunnelsEmptyState.Visibility = _tunnelViewModel.Tunnels.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
            
            var count = _tunnelViewModel.ActiveTunnelCount;
            TunnelStatusText.Text = $"{count} active tunnel(s)";
            TunnelStatusDot.Fill = count > 0 
                ? new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(46, 204, 113))
                : new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(128, 128, 128));
            
            StopAllTunnelsButton.Visibility = _tunnelViewModel.Tunnels.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        });
    }

    private void RefreshTunnels_Click(object sender, RoutedEventArgs e)
    {
        _tunnelViewModel.RecheckInstallation();
        UpdateTunnelsUI();
    }

    private async void StopAllTunnels_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new ConfirmDialog(
            $"Are you sure you want to stop all {_tunnelViewModel.Tunnels.Count} tunnel(s)?",
            "All public URLs will be terminated immediately.\n\nThis action cannot be undone.",
            "Stop All Tunnels")
        {
            Owner = this
        };
        
        dialog.ShowDialog();

        if (dialog.Result)
        {
            await _tunnelViewModel.StopAllTunnelsAsync();
            UpdateTunnelsUI();
        }
    }

    private async void TunnelStop_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { Tag: CloudflareTunnel tunnel })
            return;

        await _tunnelViewModel.StopTunnelAsync(tunnel);
    }

    private void TunnelCopy_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { Tag: CloudflareTunnel tunnel })
            return;

        if (!string.IsNullOrEmpty(tunnel.TunnelUrl))
        {
            _tunnelViewModel.CopyUrlToClipboard(tunnel.TunnelUrl);
        }
    }

    private void TunnelOpen_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { Tag: CloudflareTunnel tunnel })
            return;

        if (!string.IsNullOrEmpty(tunnel.TunnelUrl))
        {
            _tunnelViewModel.OpenUrlInBrowser(tunnel.TunnelUrl);
        }
    }

    private void TrayOpenMain_Click(object sender, RoutedEventArgs e)
    {
        Show();
        WindowState = WindowState.Normal;
        Activate();
    }

    private void TraySettings_Click(object sender, RoutedEventArgs e)
    {
        _viewModel.SelectedSidebarItem = SidebarItem.Settings;
        HeaderText.Text = "Settings";
        Show();
        WindowState = WindowState.Normal;
        Activate();
    }

    private void TrayQuit_Click(object sender, RoutedEventArgs e)
    {
        _isShuttingDown = true;
        Application.Current.Shutdown();
    }

    // Override close button to minimize to tray instead
    protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        if (!_isShuttingDown)
        {
            e.Cancel = true;
            Hide();
        }
        base.OnClosing(e);
    }

    protected override void OnClosed(EventArgs e)
    {
        _trayIcon?.Dispose();
        base.OnClosed(e);
    }

    // Update tray menu with active ports
    private void UpdateTrayMenu()
    {
        if (_trayIcon == null || _trayIcon.ContextMenu == null) return;

        var contextMenu = _trayIcon.ContextMenu;
        
        // Remove old port menu items (everything before first separator)
        var firstSeparatorIndex = contextMenu.Items.Cast<object>()
            .TakeWhile(item => item is not Separator)
            .Count();
        
        // Remove old port items
        for (int i = contextMenu.Items.Count - 1; i >= 0; i--)
        {
            if (contextMenu.Items[i] is MenuItem menuItem && menuItem.Tag is PortInfo)
            {
                contextMenu.Items.RemoveAt(i);
            }
        }

        // Add header if there are ports
        var ports = _viewModel.Ports.Take(10).ToList(); // Limit to 10 ports
        
        if (ports.Any())
        {
            // Find the first separator and insert ports before it
            var separatorIndex = -1;
            for (int i = 0; i < contextMenu.Items.Count; i++)
            {
                if (contextMenu.Items[i] is Separator)
                {
                    separatorIndex = i;
                    break;
                }
            }

            if (separatorIndex > 0)
            {
                // Insert ports after "Active Ports" header
                int insertIndex = 1;
                foreach (var port in ports)
                {
                    var portMenuItem = new MenuItem
                    {
                        Header = $"● :{port.Port}  {port.ProcessName} (PID: {port.Pid})",
                        Tag = port
                    };
                    portMenuItem.Click += async (s, e) =>
                    {
                        var menuItem = s as MenuItem;
                        if (menuItem?.Tag is PortInfo portInfo)
                        {
                            var dialog = new ConfirmDialog(
                                $"Kill process on port {portInfo.Port}?",
                                $"Process: {portInfo.ProcessName}\nPID: {portInfo.Pid}",
                                "Kill Process")
                            {
                                Owner = this
                            };
                            
                            dialog.ShowDialog();

                            if (dialog.Result)
                            {
                                await _viewModel.KillProcessCommand.ExecuteAsync(portInfo);
                            }
                        }
                    };
                    contextMenu.Items.Insert(insertIndex++, portMenuItem);
                }
            }
        }
    }
}
