using System;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;

namespace LazyGPrototype;

/// <summary>Only reads visible LazyGConnector LGC v3 RGB cells. No legacy RGB,
/// XML, GameState, aura, cooldown or GCD inputs.</summary>
internal static class WowRgbBridge
{
    private static readonly string[] ProcessNames =
        { "Wow", "WowClassic", "WowB", "Wow-64", "WowClassicT" };

    [StructLayout(LayoutKind.Sequential)]
    private struct Point { public int X; public int Y; }
    [StructLayout(LayoutKind.Sequential)]
    private struct Rect { public int Left; public int Top; public int Right; public int Bottom; }

    [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr handle,out Rect rect);
    [DllImport("user32.dll")] private static extern bool ClientToScreen(IntPtr handle,ref Point point);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr handle);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr handle,int command);

    private static Process? FindGame()
    {
        foreach(string name in ProcessNames)
        {
            try
            {
                foreach(var p in Process.GetProcessesByName(name))
                {
                    try
                    {
                        if(!p.HasExited && p.MainWindowHandle!=IntPtr.Zero)
                            return p;
                    }
                    catch(InvalidOperationException){}
                    p.Dispose();
                }
            }
            catch(System.ComponentModel.Win32Exception){}
            catch(InvalidOperationException){}
        }
        return null;
    }

    public static bool GameRunning()
    {
        using var game=FindGame();
        return game!=null;
    }

    public static void ActivateGame()
    {
        using var game=FindGame();
        if(game is null)return;
        ShowWindow(game.MainWindowHandle,9);
        SetForegroundWindow(game.MainWindowHandle);
    }

    public static bool TryReadLazyGConnector(out LazyGCoreRgbPacket? packet,
        out string detail)
    {
        packet=null;
        detail="CONNECTOR RGB UNKNOWN";
        using var game=FindGame();
        if(game is null){detail="WOW NOT FOUND";return false;}
        if(GetForegroundWindow()!=game.MainWindowHandle)
        {detail="WOW NOT FOREGROUND";return false;}
        if(!GetClientRect(game.MainWindowHandle,out var client) ||
            client.Right-client.Left<45 || client.Bottom-client.Top<85)
        {detail="INVALID WOW CLIENT RECT";return false;}
        var origin=new Point();
        if(!ClientToScreen(game.MainWindowHandle,ref origin))
        {detail="WOW SCREEN ORIGIN FAILED";return false;}
        try
        {
            int width=Math.Min(135,client.Right-client.Left);
            int height=Math.Min(120,client.Bottom-client.Top);
            using var bitmap=new Bitmap(width,height);
            using(var gr=Graphics.FromImage(bitmap))
                gr.CopyFromScreen(origin.X,origin.Y,0,0,new Size(width,height));
            int sync=0,shape=0,failed=0;
            for(int y=0;y<height;y++)
            for(int x=0;x<Math.Min(32,width);x++)
            {
                var first=bitmap.GetPixel(x,y);
                if(Math.Abs(first.R-76)>3 || Math.Abs(first.G-71)>3 ||
                   Math.Abs(first.B-67)>3)continue;
                sync++;
                for(int pitch=2;pitch<=14;pitch++)
                {
                    if(x+7*pitch>=width)break;
                    var version=bitmap.GetPixel(x+pitch,y);
                    if(version.R!=3 || version.B>3)continue;
                    shape++;
                    Span<byte> buffer=stackalloc byte[24];
                    for(int i=0;i<8;i++)
                    {
                        var rgb=bitmap.GetPixel(x+i*pitch,y);
                        buffer[3*i]=rgb.R;
                        buffer[3*i+1]=rgb.G;
                        buffer[3*i+2]=rgb.B;
                    }
                    if(LazyGCoreRgbCodec.TryDecode(buffer,out packet) &&
                       packet is { Version:3 })
                    {
                        detail="CONNECTOR CRC OK v3 x="+x+" y="+y+
                            " pitch="+pitch+" provider="+packet.ProviderId;
                        return true;
                    }
                    failed++;
                }
            }
            detail=sync==0?"LGC MARKER NOT FOUND":
                shape==0?"CONNECTOR VERSION 3 NOT FOUND":
                "CONNECTOR CRC/SHAPE REJECTED "+failed;
            return false;
        }
        catch(Exception e)
        {
            detail="CONNECTOR CAPTURE ERROR "+e.GetType().Name;
            return false;
        }
    }
}
