using System.Windows;
using Microsoft.Extensions.DependencyInjection;
using PortKiller.Services;
using PortKiller.ViewModels;

namespace PortKiller;

public partial class App : Application
{
    public static IServiceProvider Services { get; private set; } = null!;

    public App()
    {
        // Add global exception handling
        this.DispatcherUnhandledException += (s, e) =>
        {
            System.Diagnostics.Debug.WriteLine($"Unhandled exception: {e.Exception.Message}");
            System.Diagnostics.Debug.WriteLine($"Stack trace: {e.Exception.StackTrace}");
            MessageBox.Show($"An error occurred: {e.Exception.Message}\n\nStack trace:\n{e.Exception.StackTrace}", 
                "Error", MessageBoxButton.OK, MessageBoxImage.Error);
            e.Handled = true;
        };

        // Setup dependency injection
        var services = new ServiceCollection();
        ConfigureServices(services);
        Services = services.BuildServiceProvider();
    }

    private void ConfigureServices(IServiceCollection services)
    {
        // Services
        services.AddSingleton<PortScannerService>();
        services.AddSingleton<ProcessKillerService>();
        services.AddSingleton<SettingsService>();
        services.AddSingleton<NotificationService>();
        services.AddSingleton<TunnelService>();

        // ViewModels
        services.AddSingleton<MainViewModel>(sp => new MainViewModel(
            sp.GetRequiredService<PortScannerService>(),
            sp.GetRequiredService<ProcessKillerService>(),
            sp.GetRequiredService<SettingsService>(),
            NotificationService.Instance,
            System.Windows.Threading.Dispatcher.CurrentDispatcher
        ));
        services.AddSingleton<TunnelViewModel>(sp => new TunnelViewModel(
            sp.GetRequiredService<TunnelService>(),
            NotificationService.Instance
        ));
    }
}
