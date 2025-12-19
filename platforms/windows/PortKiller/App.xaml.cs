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

        // ViewModels
        services.AddSingleton<MainViewModel>(sp => new MainViewModel(
            sp.GetRequiredService<PortScannerService>(),
            sp.GetRequiredService<ProcessKillerService>(),
            sp.GetRequiredService<SettingsService>(),
            NotificationService.Instance,
            System.Windows.Threading.Dispatcher.CurrentDispatcher
        ));
    }
}
