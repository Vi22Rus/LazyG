using System;
using System.IO;
using System.Threading;

namespace LazyG.Desktop.Diagnostics;

// Best-effort early process-level handling. This cannot recover a fatal exception.
// Future input/automation must register a synchronous stop callback before being enabled.
internal static class CrashReportService
{
    private static int reporting;
    private static Action? emergencyStop;
    public static void RegisterEmergencyStop(Action action) =>
        Interlocked.Exchange(ref emergencyStop,action);
    public static void Install()
    {
        AppDomain.CurrentDomain.UnhandledException+=(_,eventArgs)=>
        {
            Report(eventArgs.ExceptionObject as Exception,true);
        };
        System.Threading.Tasks.TaskScheduler.UnobservedTaskException+=(_,eventArgs)=>
        {
            // Observability only; no guaranteed recovery or async-void coverage.
            Report(eventArgs.Exception,false);
        };
    }
    public static void Report(Exception? exception,bool fatal)
    {
        if(Interlocked.Exchange(ref reporting,1)!=0)return;
        try
        {
            // Always disarm first, even if the ZIP writer subsequently fails.
            try {emergencyStop?.Invoke();}catch { /* never block fatal path */ }
            var directory=Path.Combine(Environment.GetFolderPath(
                Environment.SpecialFolder.LocalApplicationData),"LazyG","reports");
            RotationSupportArchive.Create(directory,
                new RotationSupportArchive.SafeState("0.4.0-dev",null,
                    "AwaitingTransport","UnhandledException","forever",null,0,0,0,0),
                "UnhandledException",fatal,DateTimeOffset.UtcNow,exception?.GetType().Name);
        }
        catch { /* out-of-space, ACL, shutdown: best-effort only */ }
        finally { Interlocked.Exchange(ref reporting,0); }
    }
}
