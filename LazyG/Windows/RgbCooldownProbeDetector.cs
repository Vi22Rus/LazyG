using System;
using System.Drawing;
using LazyG.Desktop.Diagnostics;

namespace LazyGPrototype;

// Optional LGC strip. Independent of every existing RGB decoder.
internal static class RgbCooldownProbeDetector
{
    private static bool Near(Color c,int r,int g,int b,int tolerance=3)=>
        Math.Abs(c.R-r)<=tolerance && Math.Abs(c.G-g)<=tolerance &&
        Math.Abs(c.B-b)<=tolerance;

    public static bool FindPanel(Bitmap image,out CooldownRgbPacket? packet)
    {
        packet=null;
        int maxY=Math.Min(image.Height,120);
        int maxX=Math.Min(image.Width,32);
        for(int y=0;y<maxY;y++)
        for(int x=0;x<maxX;x++)
        {
            if(!Near(image.GetPixel(x,y),0x4c,0x47,0x43))continue;
            for(int pitch=3;pitch<=12;pitch++)
            {
                if(x+pitch*5>=image.Width)break;
                var bytes=new byte[ForeverCooldownRgbCodec.ByteCount];
                for(int cell=0;cell<ForeverCooldownRgbCodec.Cells;cell++)
                {
                    var c=image.GetPixel(x+cell*pitch,y);
                    int n=cell*3;
                    bytes[n]=c.R;bytes[n+1]=c.G;bytes[n+2]=c.B;
                }
                if(ForeverCooldownRgbCodec.TryDecode(bytes,out packet))return true;
            }
        }
        packet=null;
        return false;
    }
}
