using System;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Threading;

namespace LazyGPrototype;

public partial class App : System.Windows.Application
{
    private static readonly string LogPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "LazyG", "startup-error.log");

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        DispatcherUnhandledException += OnDispatcherUnhandledException;
        AppDomain.CurrentDomain.UnhandledException += OnDomainUnhandledException;

        try
        {
            var mainWindow = new MainWindow();
            MainWindow = mainWindow;
            mainWindow.Show();
        }
        catch (Exception ex)
        {
            ReportCrash("Starting the main window", ex, true);
            Shutdown(1);
        }
    }

    private void OnDispatcherUnhandledException(object sender, DispatcherUnhandledExceptionEventArgs e)
    {
        ReportCrash("Unhandled UI exception", e.Exception, true);
        // Exit after showing the error instead of leaving a broken UI running.
        e.Handled = true;
        Shutdown(1);
    }

    private static void OnDomainUnhandledException(object? sender, UnhandledExceptionEventArgs e)
    {
        if (e.ExceptionObject is Exception ex)
            ReportCrash("Unhandled application exception", ex, false);
    }

    private static void ReportCrash(string stage, Exception exception, bool showDialog)
    {
        var message = $"LazyG {stage} failed.{Environment.NewLine}{exception}";
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(LogPath)!);
            File.AppendAllText(LogPath,
                $"[{DateTimeOffset.Now:O}] {message}{Environment.NewLine}{Environment.NewLine}",
                Encoding.UTF8);
        }
        catch { /* Logging must not cause a second startup exception. */ }

        if (showDialog)
        {
            try
            {
                System.Windows.MessageBox.Show(
                    $"LazyG failed to start.{Environment.NewLine}{Environment.NewLine}" +
                    $"{exception.Message}{Environment.NewLine}{Environment.NewLine}" +
                    $"Error details: {LogPath}",
                    "LazyG startup error", MessageBoxButton.OK, MessageBoxImage.Error);
            }
            catch { /* Even if the dialog fails, the original error is preserved if possible. */ }
        }
    }
}
