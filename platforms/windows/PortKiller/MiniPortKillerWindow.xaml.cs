using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using Microsoft.Extensions.DependencyInjection;
using PortKiller.Models;
using PortKiller.ViewModels;
using PortKiller.Services;

namespace PortKiller;

public partial class MiniPortKillerWindow : Window
{
    private readonly MainViewModel _viewModel;
    private readonly TunnelViewModel _tunnelViewModel;
    private bool _isProcessingAction = false;
    private System.Windows.Threading.DispatcherTimer? _tunnelUpdateTimer;
    private System.Windows.Threading.DispatcherTimer? _spinnerTimer;
    private System.Windows.Threading.DispatcherTimer? _successTimer;
    private double _spinnerAngle = 0;
    private bool _isManualRefresh = false; // Track manual refresh vs auto-refresh

    public MiniPortKillerWindow()
    {
        InitializeComponent();
        
        _viewModel = App.Services.GetRequiredService<MainViewModel>();
        _tunnelViewModel = App.Services.GetRequiredService<TunnelViewModel>();
        
        System.Diagnostics.Debug.WriteLine($"[MiniPortKiller] Constructor - TunnelViewModel has {_tunnelViewModel.Tunnels.Count} tunnels");
        
        // Subscribe to the Ports collection changes directly
        _viewModel.Ports.CollectionChanged += (s, e) =>
        {
            Dispatcher.Invoke(UpdatePortList);
        };

        // Also subscribe to scanning state changes to update immediately
        _viewModel.PropertyChanged += (s, e) =>
        {
            if (e.PropertyName == nameof(_viewModel.IsScanning))
            {
                Dispatcher.Invoke(() =>
                {
                    // Only show refresh UI state for manual refresh, not auto-refresh
                    if (_isManualRefresh)
                    {
                        if (_viewModel.IsScanning)
                        {
                            ShowRefreshingState();
                        }
                        else
                        {
                            ShowRefreshedState();
                            _isManualRefresh = false; // Reset flag after manual refresh completes
                        }
                    }
                    
                    // Always update port list when scanning completes
                    if (!_viewModel.IsScanning)
                    {
                        UpdatePortList();
                    }
                });
            }
        };

        // Subscribe to tunnel changes
        _tunnelViewModel.Tunnels.CollectionChanged += (s, e) =>
        {
            System.Diagnostics.Debug.WriteLine($"[MiniPortKiller] Tunnels.CollectionChanged event fired - Action: {e.Action}");
            Dispatcher.Invoke(UpdateTunnelsList);
        };

        // Set up timer to periodically check for active tunnels
        _tunnelUpdateTimer = new System.Windows.Threading.DispatcherTimer
        {
            Interval = TimeSpan.FromSeconds(2)
        };
        _tunnelUpdateTimer.Tick += (s, e) => UpdateTunnelsList();
        _tunnelUpdateTimer.Start();

        // Initial refresh when window opens
        Loaded += async (s, e) => 
        {
            await _viewModel.RefreshPortsCommand.ExecuteAsync(null);
            UpdatePortList();
            UpdateTunnelsList();
        };
        
        UpdatePortList();
        UpdateTunnelsList();
    }

    private void UpdatePortList()
    {
        // Safety check if controls aren't initialized yet
        if (SearchBox == null || PortsList == null || PortCountText == null || EmptyStateText == null) return;

        var searchText = SearchBox.Text?.ToLower() ?? "";
        
        // Get fresh data from ViewModel - convert to list to avoid collection modification issues
        var allPorts = _viewModel.Ports.ToList();
        
        System.Diagnostics.Debug.WriteLine($"[MiniPortKiller] UpdatePortList called - Total ports: {allPorts.Count}, Thread: {System.Threading.Thread.CurrentThread.ManagedThreadId}");
        
        var filteredPorts = allPorts
            .Where(p => string.IsNullOrEmpty(searchText) || 
                        p.DisplayPort.Contains(searchText) || 
                        (p.ProcessName != null && p.ProcessName.ToLower().Contains(searchText)) ||
                        p.Pid.ToString().Contains(searchText))
            .OrderBy(p => p.Port)
            .Take(15) // Limit for mini view
            .ToList();
        
        System.Diagnostics.Debug.WriteLine($"[MiniPortKiller] Filtered ports to display: {filteredPorts.Count}");
        
        // Update ItemsSource - WPF will handle the diff automatically
        PortsList.ItemsSource = filteredPorts;
        PortCountText.Text = allPorts.Count.ToString(); // Show total count, not filtered
        
        EmptyStateText.Visibility = filteredPorts.Any() ? Visibility.Collapsed : Visibility.Visible;
    }

    private void UpdateTunnelsList()
    {
        // Safety check if controls aren't initialized yet
        var tunnelsList = this.FindName("TunnelsList") as ItemsControl;
        var tunnelsSection = this.FindName("TunnelsSection") as StackPanel;
        
        if (tunnelsList == null || tunnelsSection == null)
        {
            System.Diagnostics.Debug.WriteLine($"[MiniPortKiller] UpdateTunnelsList - Controls not found. TunnelsList: {(tunnelsList != null)}, TunnelsSection: {(tunnelsSection != null)}");
            return;
        }

        // Get active tunnels
        var activeTunnels = _tunnelViewModel.Tunnels
            .Where(t => t.Status == TunnelStatus.Active)
            .OrderBy(t => t.Port)
            .ToList();
        
        System.Diagnostics.Debug.WriteLine($"[MiniPortKiller] UpdateTunnelsList called - Active tunnels: {activeTunnels.Count}");
        
        // Update ItemsSource
        tunnelsList.ItemsSource = activeTunnels;
        
        // Show/hide tunnels section based on whether there are active tunnels
        tunnelsSection.Visibility = activeTunnels.Any() ? Visibility.Visible : Visibility.Collapsed;
        
        System.Diagnostics.Debug.WriteLine($"[MiniPortKiller] TunnelsSection visibility set to: {tunnelsSection.Visibility}");
    }

    private void SearchBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        UpdatePortList();
    }

    private void KillSinglePort_Click(object sender, MouseButtonEventArgs e)
    {
        if (sender is Button btn && btn.Tag is PortInfo port)
        {
            // Stop event propagation
            e.Handled = true;
            port.IsConfirmingKill = true;
        }
    }

    private async void ConfirmKill_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is PortInfo port)
        {
            port.IsConfirmingKill = false;
            port.IsKilling = true;

            try
            {
                await _viewModel.KillProcessCommand.ExecuteAsync(port);
            }
            finally
            {
                // The port will be removed from the list by the ViewModel refresh
                // If it fails, we should reset the state
                if (_viewModel.Ports.Contains(port))
                {
                    port.IsKilling = false;
                }
            }
        }
    }

    private void CancelKill_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is PortInfo port)
        {
            port.IsConfirmingKill = false;
        }
    }

    private async void KillAll_Click(object sender, RoutedEventArgs e)
    {
        _isProcessingAction = true;
        
        try
        {
            if (!_viewModel.Ports.Any()) return;

            var dialog = new ConfirmDialog(
                $"Kill ALL {_viewModel.Ports.Count} active processes?",
                "This will terminate all processes currently using ports.")
            {
                Owner = this
            };
            
            dialog.ShowDialog();

            if (dialog.Result)
            {
                // Create a copy of the list to avoid collection modification errors
                var portsToKill = _viewModel.Ports.ToList();
                foreach (var port in portsToKill)
                {
                    await _viewModel.KillProcessCommand.ExecuteAsync(port);
                }
                
                // The auto-refresh in MainViewModel will update the UI automatically
                // via the CollectionChanged event subscription
            }
        }
        finally
        {
            _isProcessingAction = false;
        }
    }

    private async void RefreshButton_Click(object sender, RoutedEventArgs e)
    {
        System.Diagnostics.Debug.WriteLine("[MiniPortKiller] Refresh button clicked");
        _isManualRefresh = true; // Set flag to show refresh UI state
        await _viewModel.RefreshPortsCommand.ExecuteAsync(null);
        System.Diagnostics.Debug.WriteLine("[MiniPortKiller] Refresh command executed");
    }

    private void OpenApp_Click(object sender, RoutedEventArgs e)
    {
        Application.Current.MainWindow?.Show();
        Application.Current.MainWindow!.WindowState = WindowState.Normal;
        Application.Current.MainWindow?.Activate();
        Close();
    }

    private void Quit_Click(object sender, RoutedEventArgs e)
    {
        Application.Current.Shutdown();
    }

    private void Window_Deactivated(object sender, EventArgs e)
    {
        // Don't close if we're showing a MessageBox or processing an action
        if (_isProcessingAction)
            return;
            
        // Close when clicking outside, behaving like a popup menu
        Close();
    }

    public void ShowNearTray()
    {
        // Position near system tray (bottom-right)
        var workArea = SystemParameters.WorkArea;
        Left = workArea.Right - Width - 10;
        Top = workArea.Bottom - Height - 10;
        
        // Reset search
        if (SearchBox != null)
        {
            SearchBox.Text = "";
            SearchBox.Focus();
        }
        
        // Update the port list with current data
        UpdatePortList();
        
        Show();
        Activate();
        Focus();
    }

    private void CopyTunnelUrl_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is CloudflareTunnel tunnel)
        {
            if (!string.IsNullOrEmpty(tunnel.TunnelUrl))
            {
                try
                {
                    Clipboard.SetText(tunnel.TunnelUrl);
                    System.Diagnostics.Debug.WriteLine($"[MiniPortKiller] Copied tunnel URL: {tunnel.TunnelUrl}");
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"[MiniPortKiller] Failed to copy URL: {ex.Message}");
                }
            }
        }
    }

    private async void StopTunnel_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is CloudflareTunnel tunnel)
        {
            _isProcessingAction = true;
            try
            {
                System.Diagnostics.Debug.WriteLine($"[MiniPortKiller] Stopping tunnel on port {tunnel.Port}");
                await _tunnelViewModel.StopTunnelAsync(tunnel);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[MiniPortKiller] Failed to stop tunnel: {ex.Message}");
            }
            finally
            {
                _isProcessingAction = false;
            }
        }
    }

    // Refresh Status State Management (Raycast-style)
    private void ShowRefreshingState()
    {
        var refreshIcon = this.FindName("RefreshIcon") as System.Windows.Controls.TextBlock;
        var loadingSpinner = this.FindName("LoadingSpinner") as System.Windows.Controls.Border;
        var successDot = this.FindName("SuccessDot") as System.Windows.Shapes.Ellipse;
        var refreshStatusText = this.FindName("RefreshStatusText") as System.Windows.Controls.TextBlock;
        
        if (refreshIcon == null || loadingSpinner == null || successDot == null || refreshStatusText == null)
            return;

        // Stop any existing success timer
        _successTimer?.Stop();
        
        // Hide idle and success states
        refreshIcon.Visibility = Visibility.Collapsed;
        successDot.Visibility = Visibility.Collapsed;
        
        // Show loading spinner
        loadingSpinner.Visibility = Visibility.Visible;
        refreshStatusText.Text = "Refreshing...";
        
        // Start spinner animation
        StartSpinnerAnimation();
    }

    private void ShowRefreshedState()
    {
        var refreshIcon = this.FindName("RefreshIcon") as System.Windows.Controls.TextBlock;
        var loadingSpinner = this.FindName("LoadingSpinner") as System.Windows.Controls.Border;
        var successDot = this.FindName("SuccessDot") as System.Windows.Shapes.Ellipse;
        var refreshStatusText = this.FindName("RefreshStatusText") as System.Windows.Controls.TextBlock;
        
        if (refreshIcon == null || loadingSpinner == null || successDot == null || refreshStatusText == null)
            return;

        // Stop spinner animation
        StopSpinnerAnimation();
        
        // Hide loading spinner and idle state
        loadingSpinner.Visibility = Visibility.Collapsed;
        refreshIcon.Visibility = Visibility.Collapsed;
        
        // Show success state
        successDot.Visibility = Visibility.Visible;
        refreshStatusText.Text = "Refreshed";
        
        // Reset to idle state after 2 seconds
        _successTimer = new System.Windows.Threading.DispatcherTimer
        {
            Interval = TimeSpan.FromSeconds(2)
        };
        _successTimer.Tick += (s, e) =>
        {
            _successTimer?.Stop();
            ShowIdleState();
        };
        _successTimer.Start();
    }

    private void ShowIdleState()
    {
        var refreshIcon = this.FindName("RefreshIcon") as System.Windows.Controls.TextBlock;
        var loadingSpinner = this.FindName("LoadingSpinner") as System.Windows.Controls.Border;
        var successDot = this.FindName("SuccessDot") as System.Windows.Shapes.Ellipse;
        var refreshStatusText = this.FindName("RefreshStatusText") as System.Windows.Controls.TextBlock;
        
        if (refreshIcon == null || loadingSpinner == null || successDot == null || refreshStatusText == null)
            return;

        // Hide loading and success states
        loadingSpinner.Visibility = Visibility.Collapsed;
        successDot.Visibility = Visibility.Collapsed;
        
        // Show idle state
        refreshIcon.Visibility = Visibility.Visible;
        refreshStatusText.Text = "Refresh";
    }

    private void StartSpinnerAnimation()
    {
        var loadingSpinner = this.FindName("LoadingSpinner") as System.Windows.Controls.Border;
        
        _spinnerAngle = 0;
        _spinnerTimer = new System.Windows.Threading.DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(16) // ~60fps
        };
        _spinnerTimer.Tick += (s, e) =>
        {
            _spinnerAngle = (_spinnerAngle + 6) % 360;
            if (loadingSpinner?.RenderTransform is System.Windows.Media.RotateTransform rotation)
            {
                rotation.Angle = _spinnerAngle;
            }
        };
        _spinnerTimer.Start();
    }

    private void StopSpinnerAnimation()
    {
        _spinnerTimer?.Stop();
        _spinnerTimer = null;
    }

    // Context Menu Handlers
    private void ContextMenu_Opened(object sender, RoutedEventArgs e)
    {
        if (sender is ContextMenu contextMenu && contextMenu.PlacementTarget is Grid grid && grid.DataContext is PortInfo port)
        {
            // Update "Add to Favorites" / "Remove from Favorites"
            var favoriteMenuItem = contextMenu.Items.OfType<MenuItem>().FirstOrDefault(m => m.Name == "FavoriteMenuItem");
            if (favoriteMenuItem != null)
            {
                bool isFavorite = _viewModel.IsFavorite(port.Port);
                favoriteMenuItem.Header = isFavorite ? "Remove from Favorites" : "Add to Favorites";
            }

            // Update "Watch Port" / "Unwatch Port"
            var watchMenuItem = contextMenu.Items.OfType<MenuItem>().FirstOrDefault(m => m.Name == "WatchMenuItem");
            if (watchMenuItem != null)
            {
                bool isWatched = _viewModel.WatchedPorts.Any(w => w.Port == port.Port);
                watchMenuItem.Header = isWatched ? "Unwatch Port" : "Watch Port";
            }
        }
    }

    private void ContextMenu_AddToFavorites(object sender, RoutedEventArgs e)
    {
        if (sender is MenuItem menuItem && menuItem.Tag is PortInfo port)
        {
            _isProcessingAction = true;
            try
            {
                _viewModel.ToggleFavorite(port.Port);
                System.Diagnostics.Debug.WriteLine($"[MiniPortKiller] Toggled favorite for port {port.Port}");
            }
            finally
            {
                _isProcessingAction = false;
            }
        }
    }

    private void ContextMenu_WatchPort(object sender, RoutedEventArgs e)
    {
        if (sender is MenuItem menuItem && menuItem.Tag is PortInfo port)
        {
            _isProcessingAction = true;
            try
            {
                if (_viewModel.WatchedPorts.Any(w => w.Port == port.Port))
                {
                    _viewModel.RemoveWatchedPort(port.Port);
                    System.Diagnostics.Debug.WriteLine($"[MiniPortKiller] Removed watch for port {port.Port}");
                }
                else
                {
                    _viewModel.AddWatchedPort(port.Port);
                    System.Diagnostics.Debug.WriteLine($"[MiniPortKiller] Added watch for port {port.Port}");
                }
            }
            finally
            {
                _isProcessingAction = false;
            }
        }
    }

    private void ContextMenu_OpenInBrowser(object sender, RoutedEventArgs e)
    {
        if (sender is MenuItem menuItem && menuItem.Tag is PortInfo port)
        {
            _isProcessingAction = true;
            try
            {
                var url = $"http://localhost:{port.Port}";
                System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
                {
                    FileName = url,
                    UseShellExecute = true
                });
                System.Diagnostics.Debug.WriteLine($"[MiniPortKiller] Opened browser for port {port.Port}");
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[MiniPortKiller] Failed to open browser: {ex.Message}");
                MessageBox.Show($"Failed to open browser: {ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
            }
            finally
            {
                _isProcessingAction = false;
            }
        }
    }

    private void ContextMenu_CopyUrl(object sender, RoutedEventArgs e)
    {
        if (sender is MenuItem menuItem && menuItem.Tag is PortInfo port)
        {
            _isProcessingAction = true;
            try
            {
                var url = $"http://localhost:{port.Port}";
                Clipboard.SetText(url);
                System.Diagnostics.Debug.WriteLine($"[MiniPortKiller] Copied URL for port {port.Port}: {url}");
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[MiniPortKiller] Failed to copy URL: {ex.Message}");
            }
            finally
            {
                _isProcessingAction = false;
            }
        }
    }

    private async void ContextMenu_ShareViaTunnel(object sender, RoutedEventArgs e)
    {
        if (sender is MenuItem menuItem && menuItem.Tag is PortInfo port)
        {
            _isProcessingAction = true;
            
            // Find the row and show tunnel processing state
            StackPanel? tunnelProcessingPanel = null;
            TextBlock? pidText = null;
            Button? killButton = null;
            
            // Navigate up from MenuItem to find the parent Grid (port row)
            if (menuItem.Parent is ContextMenu contextMenu && 
                contextMenu.PlacementTarget is Grid portRowGrid)
            {
                // Find elements in the row
                tunnelProcessingPanel = FindChildByName<StackPanel>(portRowGrid, "TunnelProcessingPanel");
                pidText = FindChildByName<TextBlock>(portRowGrid, "PidText");
                killButton = FindChildByName<Button>(portRowGrid, "KillButton");
                
                // Show tunnel processing state and hide other elements
                if (tunnelProcessingPanel != null)
                {
                    tunnelProcessingPanel.Visibility = Visibility.Visible;
                }
                if (pidText != null)
                {
                    pidText.Visibility = Visibility.Collapsed;
                }
                if (killButton != null)
                {
                    killButton.Visibility = Visibility.Collapsed;
                }
            }
            
            try
            {
                System.Diagnostics.Debug.WriteLine($"[MiniPortKiller] Starting tunnel for port {port.Port}");
                await _tunnelViewModel.StartTunnelAsync(port.Port);
                System.Diagnostics.Debug.WriteLine($"[MiniPortKiller] Tunnel started for port {port.Port}");
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[MiniPortKiller] Failed to start tunnel: {ex.Message}");
                MessageBox.Show($"Failed to start tunnel: {ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
            }
            finally
            {
                // Hide tunnel processing state and restore elements
                if (tunnelProcessingPanel != null)
                {
                    tunnelProcessingPanel.Visibility = Visibility.Collapsed;
                }
                if (pidText != null)
                {
                    pidText.Visibility = Visibility.Visible;
                }
                if (killButton != null)
                {
                    killButton.Visibility = Visibility.Hidden;
                }
                _isProcessingAction = false;
            }
        }
    }

    // Helper method to find a child element by name in a visual tree
    private static T? FindChildByName<T>(DependencyObject parent, string name) where T : FrameworkElement
    {
        int childCount = System.Windows.Media.VisualTreeHelper.GetChildrenCount(parent);
        for (int i = 0; i < childCount; i++)
        {
            var child = System.Windows.Media.VisualTreeHelper.GetChild(parent, i);
            
            if (child is T typedChild && typedChild.Name == name)
            {
                return typedChild;
            }
            
            var result = FindChildByName<T>(child, name);
            if (result != null)
            {
                return result;
            }
        }
        return null;
    }
}
