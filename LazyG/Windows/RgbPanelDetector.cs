using System;
using System.Drawing;

namespace LazyGPrototype;

/// <summary>Find the three-row RGB calibration pattern inside the selected screen region.</summary>
internal static class RgbPanelDetector
{
    private static bool Near(Color p, int r, int g, int b, int tolerance = 30) =>
        Math.Abs(p.R-r)<=tolerance && Math.Abs(p.G-g)<=tolerance && Math.Abs(p.B-b)<=tolerance;

    private static bool Check(Bitmap bitmap, int x, int y, int step)
    {
        // The panel has 11 columns and 3 rows. Horizontal pitch is 4 UI units,
        // vertical pitch is 8 UI units; both scale together on screen.
        int x2=x+step, x3=x+step*2, x4=x+step*3;
        int xLast=x+step*10, yLast=y+step*4;
        if(xLast>=bitmap.Width || yLast>=bitmap.Height) return false;
        return Near(bitmap.GetPixel(x,y),0,255,0)
            && Near(bitmap.GetPixel(x2,y),255,0,255)
            && Near(bitmap.GetPixel(x3,y),255,255,255)
            && Near(bitmap.GetPixel(x4,y),0,0,0)
            && Near(bitmap.GetPixel(xLast,yLast),255,0,255);
    }

    public static bool FindPanel(Bitmap image, out string detail)
    {
        // Scan for the marker prefix anywhere in the selection, then verify the
        // final marker on the third row; tolerate UI/DPI scaling and margins.
        for(int y=0;y<image.Height;y++)
        for(int x=0;x<image.Width;x++)
        {
            if(!Near(image.GetPixel(x,y),0,255,0)) continue;
            for(int stride=2;stride<=20;stride++)
                if(Check(image,x,y,stride))
                {
                    detail=$"Markers at ({x},{y}); column stride={stride}px; three rows verified.";
                    return true;
                }
        }
        detail="Select the whole three-row RGB panel, including the green/magenta/white/black markers at the top and the final magenta marker at the bottom right.";
        return false;
    }
}
