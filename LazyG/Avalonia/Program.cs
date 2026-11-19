using System;
using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Themes.Fluent;
namespace LazyG.Desktop;
internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        Diagnostics.CrashReportService.Install();
        try { BuildAvaloniaApp().StartWithClassicDesktopLifetime(args); }
        catch(Exception ex)
        {
            Diagnostics.CrashReportService.Report(ex,true);
            throw;
        }
    }
    public static AppBuilder BuildAvaloniaApp() =>
        AppBuilder.Configure<LazyApp>().UsePlatformDetect().LogToTrace();
}
public sealed class LazyApp : Avalonia.Application
{
    public override void Initialize()
    {
        Styles.Add(new FluentTheme());
        RequestedThemeVariant = Avalonia.Styling.ThemeVariant.Dark;
    }
    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
            desktop.MainWindow = new MainWindow();
        base.OnFrameworkInitializationCompleted();
    }
}