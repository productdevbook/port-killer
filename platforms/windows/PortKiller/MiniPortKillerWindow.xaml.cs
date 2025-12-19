using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using Microsoft.Extensions.DependencyInjection;
using PortKiller.Models;
using PortKiller.ViewModels;

namespace PortKiller;

public partial class MiniPortKillerWindow : Window
{
    private readonly MainViewModel _viewModel;
    private bool _isProcessingAction = false;

    public MiniPortKillerWindow()
    {
        InitializeComponent();
        
        _viewModel = App.Services.GetRequiredService<MainViewModel>();
        
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
                if (!_viewModel.IsScanning)
                {
                    Dispatcher.Invoke(UpdatePortList);
                }
            }
        };

        // Initial refresh when window opens
        Loaded += async (s, e) => 
        {
            await _viewModel.RefreshPortsCommand.ExecuteAsync(null);
            UpdatePortList();
        };
        
        UpdatePortList();
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
}
