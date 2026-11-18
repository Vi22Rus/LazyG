using System;
using System.Drawing;

namespace LazyGPrototype;

/// <summary>Find the calibration pattern anywhere inside the user's screen selection.</summary>
internal static class RgbPanelDetector
{
    private static bool Near(Color p, int r, int g, int b, int tolerance = 30) =>
        Math.Abs(p.R-r)<=tolerance && Math.Abs(p.G-g)<=tolerance && Math.Abs(p.B-b)<=tolerance;

    private static bool Check(Bitmap bitmap, int x, int y, int step)
    {
        // sample centres of cells 1, 2, 3, 4 and 32, allowing UI/DPI scaling.
        int x2=x+step, x3=x+step*2, x4=x+step*3, xLast=x+step*31;
        if(xLast>=bitmap.Width || x4>=bitmap.Width) return false;
        return Near(bitmap.GetPixel(x,y),0,255,0)
            && Near(bitmap.GetPixel(x2,y),255,0,255)
            && Near(bitmap.GetPixel(x3,y),255,255,255)
            && Near(bitmap.GetPixel(x4,y),0,0,0)
            && Near(bitmap.GetPixel(xLast,y),255,0,255);
    }

    public static bool FindPanel(Bitmap image, out string detail)
    {
        // Logical stride 4px (3px cell + 1px gap), effective physical scale
        // may differ due to game UI scale, Windows scaling, and display size.
        // Sampling each candidate coordinate avoids assuming the selection
        // touches either exact edge of the panel.
        for(int y=0;y<image.Height;y++)
        for(int x=0;x<image.Width;x++)
        {
            var c=image.GetPixel(x,y);
            if(!Near(c,0,255,0)) continue;
            for(int stride=2;stride<=20;stride++)
                if(Check(image,x,y,stride))
                {
                    detail=$"Markers at ({x},{y}); stride={stride}px; complete width verified.";
                    return true;
                }
        }
        detail="Make sure the green/magenta/white/black prefix and the last magenta cell are visible; avoid UI scaling blur.";
        return false;
    }
}
