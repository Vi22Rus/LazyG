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

    // Native LazyGCore recommendation row is at WoW CLIENT x=0..38,y=54..57.
    // Independently captured: a missing old v2 addon cannot be mistaken for a
    // valid game state, and the read-only frame cannot authorize input by itself.
    public static bool TryReadLazyGCore(out LazyGCoreRgbPacket? packet) =>
        TryReadLazyGCore(out packet,out _);

    public static bool TryReadLazyGCore(out LazyGCoreRgbPacket? packet,
        out string detail)
    {
        packet=null;
        detail="NATIVE RGB UNKNOWN";
        using var game=FindGame();
        if(game is null){detail="WOW WINDOW NOT FOUND";return false;}
        if(GetForegroundWindow()!=game.MainWindowHandle)
        {detail="WOW NOT FOREGROUND";return false;}
        if(!GetClientRect(game.MainWindowHandle,out var client) ||
           client.Right-client.Left<45 || client.Bottom-client.Top<65)
        {detail="INVALID WOW CLIENT RECT";return false;}
        var topLeft=new Point();
        if(!ClientToScreen(game.MainWindowHandle,ref topLeft))
        {detail="WOW CLIENT SCREEN ORIGIN FAILED";return false;}
        try
        {
            // UI scale changes physical y position and pixel pitch. Search
            // only the small upper-left client rectangle for the exact
            // L,G,C sync cells; accept only CRC-valid 8-cell frames.
            int width=Math.Min(135,client.Right-client.Left);
            int height=Math.Min(120,client.Bottom-client.Top);
            using var bitmap=new Bitmap(width,height);
            using(var graphics=Graphics.FromImage(bitmap))
                graphics.CopyFromScreen(topLeft.X,topLeft.Y,0,0,new Size(width,height));
            int syncCount=0,versionCount=0,failedCrc=0;
            for(int y=0;y<height;y++)
            for(int x=0;x<Math.Min(32,width);x++)
            {
                var sync=bitmap.GetPixel(x,y);
                if(Math.Abs(sync.R-76)>3 || Math.Abs(sync.G-71)>3 ||
                   Math.Abs(sync.B-67)>3)continue;
                syncCount++;
                for(int pitch=2;pitch<=14;pitch++)
                {
                    if(x+pitch*7>=width)break;
                    var second=bitmap.GetPixel(x+pitch,y);
                    // Pixel 1=magic LGC, pixel 2=(version,sequence,status).
                    // Native v2 adds trusted HID/gate information while keeping
                    // the same eight cells. Do not reject v2 before CRC validation.
                    if(!LazyGCoreRgbCodec.IsCandidateVersionCell(
                        second.R,second.B))continue;
                    versionCount++;
                    Span<byte> frame=stackalloc byte[24];
                    for(int i=0;i<8;i++)
                    {
                        var color=bitmap.GetPixel(x+pitch*i,y);
                        frame[i*3]=color.R;
                        frame[i*3+1]=color.G;
                        frame[i*3+2]=color.B;
                    }
                    if(LazyGCoreRgbCodec.TryDecode(frame,out packet))
                    {
                        detail="NATIVE CRC OK v"+packet!.Version+
                            " pitch="+pitch+" x="+x+" y="+y;
                        return true;
                    }
                    failedCrc++;
                }
            }
            detail=syncCount==0?"NATIVE SYNC LGC NOT FOUND":
                versionCount==0?"NATIVE MARKER FOUND / VERSION OR STATUS NOT FOUND":
                "NATIVE CANDIDATE CRC/SHAPE REJECTED "+failedCrc;
            return false;
        }
        catch(Exception ex) {detail="NATIVE CAPTURE ERROR "+ex.GetType().Name;return false;}
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
        return TryReadCombined(out player, out _, out detail, out _, out _);
    }

    // Legacy RGB callers preserve the old signature.
    public static bool TryReadCombined(out RgbPlayerState? player,
        out RgbV3Packet? telemetry, out string detail, out string v3Detail,
        out RgbThresholdProbe? thresholds)
        => TryReadCombined(out player,out telemetry,out detail,out v3Detail,
            out thresholds,false,out _);

    // Optional LGD is read from the same bitmap, never changing v2/v3 return.

    public static bool TryReadCombined(out RgbPlayerState? player,
        out RgbV3Packet? telemetry, out string detail, out string v3Detail,
        out RgbThresholdProbe? thresholds, bool readSpellProbe,
        out LazyG.Desktop.Diagnostics.SpellProbe? spellProbe)
    {
        return TryReadCombined(out player,out telemetry,out detail,out v3Detail,
            out thresholds,readSpellProbe,out spellProbe,false,out _);
    }

    // Independent LGC capture is opt-in; same bitmap, same verified RGB v2 anchor.
    public static bool TryReadCombined(out RgbPlayerState? player,
        out RgbV3Packet? telemetry,out string detail,out string v3Detail,
        out RgbThresholdProbe? thresholds,bool readSpellProbe,
        out LazyG.Desktop.Diagnostics.SpellProbe? spellProbe,
        bool readCooldownProbe,out LazyG.Desktop.Diagnostics.CooldownRgbPacket? cooldownProbe)
    {
        return TryReadCombined(out player,out telemetry,out detail,out v3Detail,
            out thresholds,readSpellProbe,out spellProbe,readCooldownProbe,
            out cooldownProbe,false,out _);
    }

    // Optional LGE event strip shares the same captured bitmap and never alters
    // existing return contracts. Callers must opt in explicitly.
    public static bool TryReadCombined(out RgbPlayerState? player,
        out RgbV3Packet? telemetry,out string detail,out string v3Detail,
        out RgbThresholdProbe? thresholds,bool readSpellProbe,
        out LazyG.Desktop.Diagnostics.SpellProbe? spellProbe,
        bool readCooldownProbe,out LazyG.Desktop.Diagnostics.CooldownRgbPacket? cooldownProbe,
        bool readCastEvent,out LazyG.Desktop.Diagnostics.ForeverCastEventPacket? castEvent)
        => TryReadCombined(out player,out telemetry,out detail,out v3Detail,
            out thresholds,readSpellProbe,out spellProbe,readCooldownProbe,
            out cooldownProbe,readCastEvent,out castEvent,0);

    // Optional manifest-indexed extension lives in the original v3 row.
    // Zero preserves the byte-identical legacy RGB capture behavior.
    public static bool TryReadCombined(out RgbPlayerState? player,
        out RgbV3Packet? telemetry,out string detail,out string v3Detail,
        out RgbThresholdProbe? thresholds,bool readSpellProbe,
        out LazyG.Desktop.Diagnostics.SpellProbe? spellProbe,
        bool readCooldownProbe,out LazyG.Desktop.Diagnostics.CooldownRgbPacket? cooldownProbe,
        bool readCastEvent,out LazyG.Desktop.Diagnostics.ForeverCastEventPacket? castEvent,
        int compactExtensionCells)
    {
        castEvent=null;
        cooldownProbe=null;
        spellProbe=null;
        player = null;
        telemetry = null;
        thresholds = null;
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

        int width = Math.Min(800, client.Right - client.Left);
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
            if(!RgbV3PanelDetector.FindPanel(bitmap,out telemetry,out v3Detail))
            {
                // New 4-cell auto-binding tail on the same v3 row.
                // Legacy layouts remain accepted for old addon installs.
                if(!RgbV3PanelDetector.FindProfilePanel(bitmap,
                    compactExtensionCells+4,out telemetry,out v3Detail))
                {
                    if(!RgbV3PanelDetector.FindProfilePanel(bitmap,4,
                        out telemetry,out v3Detail) && compactExtensionCells>0)
                        RgbV3PanelDetector.FindProfilePanel(bitmap,
                            compactExtensionCells,out telemetry,out v3Detail);
                }
            }
            if (telemetry != null)
                RgbV3ThresholdDetector.FindPanel(bitmap, out thresholds);
            if (readSpellProbe)
                RgbSpellProbeDetector.FindPanel(bitmap,out spellProbe);
            if (readCooldownProbe)
                RgbCooldownProbeDetector.FindPanel(bitmap,out cooldownProbe);
            if (v2 && readCastEvent)
                RgbCastEventDetector.FindPanel(bitmap,out castEvent);
            return v2;
        }
        catch (Exception ex)
        {
            detail = "RGB screen capture failed: " + ex.Message;
            return false;
        }
    }
}
