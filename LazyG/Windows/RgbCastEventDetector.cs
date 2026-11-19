using System;
using System.Drawing;
using LazyG.Desktop.Diagnostics;

namespace LazyGPrototype;

// Read-only optional LGE strip. Never changes existing v2/v3/Curve/LGD/LGC.
internal static class RgbCastEventDetector
{
    private static bool Near(Color c,int r,int g,int b) =>
        Math.Abs(c.R-r)<=3 && Math.Abs(c.G-g)<=3 && Math.Abs(c.B-b)<=3;

    public static bool FindPanel(Bitmap image,out ForeverCastEventPacket? packet)
    {
        packet=null;
        int maxY=Math.Min(120,image.Height),maxX=Math.Min(32,image.Width);
        for(int y=0;y<maxY;y++)
        for(int x=0;x<maxX;x++)
        {
            if(!Near(image.GetPixel(x,y),0x4C,0x47,0x45))continue;
            for(int pitch=3;pitch<=12;pitch++)
            {
                if(x+pitch*5>=image.Width)break;
                var data=new byte[ForeverCastEventCodec.ByteCount];
                for(int c=0;c<ForeverCastEventCodec.Cells;c++)
                {
                    var pixel=image.GetPixel(x+c*pitch,y);
                    data[3*c]=pixel.R;data[3*c+1]=pixel.G;data[3*c+2]=pixel.B;
                }
                if(ForeverCastEventCodec.TryDecode(data,out packet))return true;
            }
        }
        packet=null;
        return false;
    }
}
