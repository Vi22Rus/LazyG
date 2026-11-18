using System;
using System.Drawing;
using LazyG.Desktop.Diagnostics;

namespace LazyGPrototype;

// Optional six-cell LGD strip, independent of v2/v3/Curve decoding.
// Never infer missing/invalid pixels as False.
internal static class RgbSpellProbeDetector
{
    private static bool Near(Color c,int r,int g,int b,int tolerance=3) =>
        Math.Abs(c.R-r)<=tolerance && Math.Abs(c.G-g)<=tolerance &&
        Math.Abs(c.B-b)<=tolerance;

    public static bool FindPanel(Bitmap image,out SpellProbe? probe)
    {
        probe=null;
        int maxY=Math.Min(image.Height,120);
        int maxX=Math.Min(image.Width,32);
        for(int y=0;y<maxY;y++)
        for(int x=0;x<maxX;x++)
        {
            if(!Near(image.GetPixel(x,y),0x4c,0x47,0x44))continue;
            for(int pitch=3;pitch<=12;pitch++)
            {
                if(x+pitch*5>=image.Width)break;
                var data=new byte[ForeverSpellProbeCodec.ByteCount];
                bool valid=true;
                for(int cell=0;cell<ForeverSpellProbeCodec.Cells;cell++)
                {
                    var c=image.GetPixel(x+cell*pitch,y);
                    int offset=cell*3;
                    data[offset]=c.R;
                    data[offset+1]=c.G;
                    data[offset+2]=c.B;
                }
                if(ForeverSpellProbeCodec.TryDecode(data,out probe))
                    return true;
                if(!valid)continue;
            }
        }
        probe=null;
        return false;
    }
}
