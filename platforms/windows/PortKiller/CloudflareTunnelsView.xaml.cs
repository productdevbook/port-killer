using System.Windows;
using System.Windows.Controls;
using Microsoft.Extensions.DependencyInjection;
using PortKiller.Models;
using PortKiller.ViewModels;

namespace PortKiller;

/// <summary>
/// Cloudflare Tunnels management window
/// </summary>
public partial class CloudflareTunnelsView : Window
{
    private readonly TunnelViewModel _viewModel;
    private StackPanel? _emptyState;

    public CloudflareTunnelsView()
    {
        InitializeComponent();
        
        _viewModel = App.Services.GetRequiredService<TunnelViewModel>();
        DataContext = _viewModel;

        // Get reference to empty state
        _emptyState = this.FindName("EmptyState") as StackPanel;

        // Update empty state visibility
        UpdateEmptyState();
        _viewModel.Tunnels.CollectionChanged += (s, e) => UpdateEmptyState();
    }

    private void UpdateEmptyState()
    {
        if (_emptyState != null)
        {
            _emptyState.Visibility = _viewModel.Tunnels.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        }
    }

    private async void StopButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { Tag: CloudflareTunnel tunnel })
            return;

        await _viewModel.StopTunnelAsync(tunnel);
    }

    private async void StopAllButton_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new ConfirmDialog(
            $"Are you sure you want to stop all {_viewModel.Tunnels.Count} tunnel(s)?",
            "All public URLs will be terminated immediately.\n\nThis action cannot be undone.",
            "Stop All Tunnels")
        {
            Owner = this
        };
        
        dialog.ShowDialog();

        if (dialog.Result)
        {
            await _viewModel.StopAllTunnelsAsync();
        }
    }

    private void CopyButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { Tag: CloudflareTunnel tunnel })
            return;

        if (!string.IsNullOrEmpty(tunnel.TunnelUrl))
        {
            _viewModel.CopyUrlToClipboard(tunnel.TunnelUrl);
        }
    }

    private void OpenButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { Tag: CloudflareTunnel tunnel })
            return;

        if (!string.IsNullOrEmpty(tunnel.TunnelUrl))
        {
            _viewModel.OpenUrlInBrowser(tunnel.TunnelUrl);
        }
    }

    private void RefreshButton_Click(object sender, RoutedEventArgs e)
    {
        _viewModel.RecheckInstallation();
    }

    protected override void OnClosed(EventArgs e)
    {
        // Clean up: stop all tunnels when window closes
        _ = _viewModel.StopAllTunnelsAsync();
        base.OnClosed(e);
    }

    // Public method to start a tunnel from external source (e.g., main window)
    public async Task StartTunnelForPort(int port)
    {
        await _viewModel.StartTunnelAsync(port);
    }
}
