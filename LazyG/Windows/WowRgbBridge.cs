using System;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;

namespace LazyGPrototype;

/// <summary>Captures only a small area of the visible WoW client; no memory reading.</summary>
internal static class WowRgbBridge
{
    private static readonly string[] ProcessNames = { "Wow", "WowClassic", "WowB", "Wow-64", "WowClassicT" };

    [StructLayout(LayoutKind.Sequential)]
    private struct Point { public int X; public int Y; }
    [StructLayout(LayoutKind.Sequential)]
    private struct Rect { public int Left; public int Top; public int Right; public int Bottom; }

    [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr handle, out Rect rect);
    [DllImport("user32.dll")] private static extern bool ClientToScreen(IntPtr handle, ref Point point);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr handle);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr handle, int command);

    private static Process? FindGame()
    {
        foreach (string name in ProcessNames)
        {
            try
            {
                foreach (var process in Process.GetProcessesByName(name))
                {
                    try
                    {
                        if (!process.HasExited && process.MainWindowHandle != IntPtr.Zero)
                            return process;
                    }
                    catch (InvalidOperationException) { }
                    process.Dispose();
                }
            }
            catch (System.ComponentModel.Win32Exception) { }
            catch (InvalidOperationException) { }
        }
        return null;
    }

    public static bool GameRunning()
    {
        using var process = FindGame();
        return process != null;
    }

    public static void ActivateGame()
    {
        using var game = FindGame();
        if (game == null) return;
        ShowWindow(game.MainWindowHandle, 9); // SW_RESTORE
        SetForegroundWindow(game.MainWindowHandle);
    }

    public static bool TryRead(out RgbPlayerState? player, out string detail)
    {
        return TryReadCombined(out player, out _, out detail, out _);
    }

    // One physical capture for both independent RGB protocols.
    public static bool TryReadCombined(out RgbPlayerState? player,
        out RgbV3Packet? telemetry, out string detail, out string v3Detail)
    {
        player = null;
        telemetry = null;
        v3Detail = "RGB v3 not checked.";
        using var game = FindGame();
        if (game == null)
        {
            detail = "WoW window not found.";
            return false;
        }

        IntPtr handle = game.MainWindowHandle;
        if (GetForegroundWindow() != handle)
        {
            detail = "Switch to WoW to read RGB data (game must be visible).";
            return false;
        }

        if (!GetClientRect(handle, out var client))
        {
            detail = "Cannot read WoW client dimensions.";
            return false;
        }

        var topLeft = new Point();
        if (!ClientToScreen(handle, ref topLeft))
        {
            detail = "Cannot find WoW client screen coordinates.";
            return false;
        }

        int width = Math.Min(220, client.Right - client.Left);
        int height = Math.Min(120, client.Bottom - client.Top);
        if (width < 44 || height < 4)
        {
            detail = "WoW client window is too small.";
            return false;
        }

        try
        {
            using var bitmap = new Bitmap(width, height);
            using (var g = Graphics.FromImage(bitmap))
                g.CopyFromScreen(topLeft.X, topLeft.Y, 0, 0, new Size(width, height));
            bool v2 = RgbPanelDetector.FindPanel(bitmap, out player, out detail);
            RgbV3PanelDetector.FindPanel(bitmap, out telemetry, out v3Detail);
            return v2;
        }
        catch (Exception ex)
        {
            detail = "RGB screen capture failed: " + ex.Message;
            return false;
        }
    }
}
