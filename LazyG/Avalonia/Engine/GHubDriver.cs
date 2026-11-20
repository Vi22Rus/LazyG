using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using Microsoft.Win32;
using Microsoft.Win32.SafeHandles;

namespace LazyG.Desktop.Engine;

// Adapted from the user's DEV_LaZY_Forever/Core/GHubDriver.cs.
// Direct Logitech G HUB virtual bus only; no SendInput or alternative driver.
// Logitech's IOCTL is undocumented; the installed driver may be incompatible.
// The virtual-bus device can be present even when G HUB's desktop app
// has not been launched. Do not confuse an installed driver or background
// agent with a running G HUB application.
internal static class GHubRuntime
{
    internal const string NotRunningMessage =
        "Please launch Logitech G HUB before starting the rotation. " +
        "LazyG requires Logitech G HUB to be running to send key presses. " +
        "Start G HUB, then click Start again.";

    internal static bool IsDesktopProcess(string? processName) =>
        string.Equals(processName,"lghub",StringComparison.OrdinalIgnoreCase) ||
        string.Equals(processName,"lghub.exe",StringComparison.OrdinalIgnoreCase);

    public static bool IsRunning()
    {
        if(!OperatingSystem.IsWindows())return false;
        try
        {
            // Process.GetProcessesByName returns names without .exe on Windows.
            var processes=System.Diagnostics.Process.GetProcessesByName("lghub");
            bool found=processes.Length>0;
            foreach(var process in processes)process.Dispose();
            return found;
        }
        catch
        {
            // A failed process check must not be treated as a successful check.
            return false;
        }
    }
}

internal sealed class GHubDriver : IDisposable
{
    private const uint GenericRead=0x80000000;
    private const uint GenericWrite=0x40000000;
    private const uint OpenExisting=3;
    private const uint KeyboardIoctl=0x2A200C;
    private SafeFileHandle? device;
    private readonly object gate=new();
    public bool Connected { get {lock(gate)return device is {IsInvalid:false,IsClosed:false};} }

    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
    private static extern SafeFileHandle CreateFileW(string name,uint access,uint share,
        IntPtr security,uint disposition,uint flags,IntPtr template);
    [DllImport("kernel32.dll",SetLastError=true)]
    [return:MarshalAs(UnmanagedType.Bool)]
    private static extern bool DeviceIoControl(SafeFileHandle handle,uint code,
        byte[] input,int inputSize,IntPtr output,int outputSize,
        out int returned,IntPtr overlapped);
    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint processId);

    public static bool IsWowForeground()
    {
        if(!OperatingSystem.IsWindows())return false;
        var hwnd=GetForegroundWindow();
        if(hwnd==IntPtr.Zero)return false;
        GetWindowThreadProcessId(hwnd,out uint pid);
        if(pid==0)return false;
        try
        {
            using var process=System.Diagnostics.Process.GetProcessById((int)pid);
            string name=process.ProcessName;
            return name.Equals("Wow",StringComparison.OrdinalIgnoreCase) ||
                name.Equals("Wow-64",StringComparison.OrdinalIgnoreCase) ||
                name.Equals("WowClassic",StringComparison.OrdinalIgnoreCase) ||
                name.Equals("WowClassicT",StringComparison.OrdinalIgnoreCase);
        }
        catch{return false;}
    }

    private static IEnumerable<string> DiscoverPaths()
    {
        var instances=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        using(var root=Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Enum\ROOT\SYSTEM"))
        {
            if(root is not null)foreach(var instance in root.GetSubKeyNames())
            {
                using var item=root.OpenSubKey(instance);
                var ids=item?.GetValue("HardwareID") as string[] ?? Array.Empty<string>();
                if(ids.Any(id=>id.Contains("lghubvirtualbus",StringComparison.OrdinalIgnoreCase)))
                    instances.Add(instance);
            }
        }
        if(instances.Count==0)yield break;
        using var classes=Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Control\DeviceClasses");
        if(classes is null)yield break;
        foreach(var guid in classes.GetSubKeyNames())
        {
            using var cls=classes.OpenSubKey(guid);
            if(cls is null)continue;
            foreach(var name in cls.GetSubKeyNames())
            {
                if(name.StartsWith("##?#",StringComparison.Ordinal) &&
                   instances.Any(i=>name.Contains($"ROOT#SYSTEM#{i}#",StringComparison.OrdinalIgnoreCase)))
                    yield return @"\\?\" + name.Substring(4);
            }
        }
    }

    public void Connect()
    {
        lock(gate)
        {
            DisconnectCore();
            if(!OperatingSystem.IsWindows() || !Environment.Is64BitProcess)
                throw new PlatformNotSupportedException("Logitech G HUB requires Windows x64.");
            int lastError=0;
            bool discovered=false;
            foreach(var path in DiscoverPaths().Distinct(StringComparer.OrdinalIgnoreCase))
            {
                discovered=true;
                var handle=CreateFileW(path,GenericRead|GenericWrite,3,IntPtr.Zero,
                    OpenExisting,0,IntPtr.Zero);
                if(!handle.IsInvalid){device=handle;return;}
                lastError=Marshal.GetLastWin32Error();
                handle.Dispose();
            }
            if(!discovered)throw new InvalidOperationException(
                "Logitech lghubvirtualbus not found. Install/start G HUB.");
            throw new Win32Exception(lastError,"Unable to open Logitech virtual bus.");
        }
    }

    private void Report(byte modifier=0,byte usage=0)
    {
        if(device is not {IsInvalid:false,IsClosed:false})
            throw new InvalidOperationException("Logitech driver not connected");
        byte[] report=new byte[8];
        report[0]=modifier;report[2]=usage;
        if(!DeviceIoControl(device,KeyboardIoctl,report,report.Length,
            IntPtr.Zero,0,out _,IntPtr.Zero))
            throw new Win32Exception(Marshal.GetLastWin32Error(),"Logitech keyboard IOCTL failed");
    }

    public void TapKey(byte modifier,byte usage)
    {
        lock(gate)
        {
            if(!IsWowForeground())throw new InvalidOperationException("WoW is not foreground");
            try
            {
                Report(modifier,usage);
                Thread.Sleep(12);
            }
            finally
            {
                // Release all keys after a press (or a failed press).
                try{Report();}catch{DisconnectCore();throw;}
            }
        }
    }

    private void DisconnectCore(){device?.Dispose();device=null;}
    public void Disconnect(){lock(gate)DisconnectCore();}
    public void Dispose()=>Disconnect();
}

internal static class GHubKeys
{
    // Decoded RGB reports carry USB HID usage, not a Windows VK code.
    // Restrict to known keyboard usages; mouse events are a separate device.
    public static bool IsSupportedUsage(byte usage) =>
        usage is >=4 and <=99 or >=104 and <=115;
    // Original DEV_LaZY_Forever USB HID keyboard mapping.
    public static bool TryParse(string value,out byte modifier,out byte usage)
    {
        modifier=0;usage=0;
        if(string.IsNullOrWhiteSpace(value))return false;
        if(value.StartsWith("HID:",StringComparison.Ordinal))
        {
            var parts=value.Split(':');
            if(parts.Length!=3 || !byte.TryParse(parts[1],out modifier) ||
               !byte.TryParse(parts[2],out usage) ||
               modifier>15 || !IsSupportedUsage(usage))
            {modifier=0;usage=0;return false;}
            return true;
        }
        foreach(var part in value.Trim().ToUpperInvariant().Split('+',
            StringSplitOptions.TrimEntries|StringSplitOptions.RemoveEmptyEntries))
        {
            if(part is "CTRL" or "CONTROL"){modifier|=0x01;continue;}
            if(part=="SHIFT"){modifier|=0x02;continue;}
            if(part=="ALT"){modifier|=0x04;continue;}
            if(part=="WIN"){modifier|=0x08;continue;}
            if(usage!=0)return false;
            if(part.Length==1 && part[0] is >= 'A' and <= 'Z')
            {usage=(byte)(4+part[0]-'A');continue;}
            if(part.Length==1 && part[0] is >= '1' and <= '9')
            {usage=(byte)(30+part[0]-'1');continue;}
            if(part=="0"){usage=39;continue;}
            if(part=="SPACE"){usage=44;continue;}
            if(part=="TAB"){usage=43;continue;}
            if(part=="ENTER"){usage=40;continue;}
            if(part.StartsWith('F') && int.TryParse(part[1..],out int f) && f is >=1 and <=12)
            {usage=(byte)(57+f);continue;}
            return false;
        }
        return usage!=0;
    }
}
