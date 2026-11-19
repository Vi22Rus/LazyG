using System;
using System.Drawing;

namespace LazyGPrototype;

/// <summary>Reads the separate Forever v3 diagnostic strip without changing the v2 detector.</summary>
internal static class RgbV3PanelDetector
{
    private static bool Near(Color c, int r, int g, int b, int tolerance = 4) =>
        Math.Abs(c.R - r) <= tolerance &&
        Math.Abs(c.G - g) <= tolerance &&
        Math.Abs(c.B - b) <= tolerance;

    public static bool FindPanel(Bitmap bitmap, out RgbV3Packet? packet, out string detail)
    => Scan(bitmap,0,out packet,out detail);

    // Same physical v3 row, profile-indexed extension. No extra RGB strip.
    // A layout mismatch/CRC failure cannot be accepted as old 24-cell v3.
    public static bool FindProfilePanel(Bitmap bitmap,int extensionCells,
        out RgbV3Packet? packet,out string detail)
        => extensionCells>0 && extensionCells<=96
            ? Scan(bitmap,extensionCells,out packet,out detail)
            : Reject(out packet,out detail);

    private static bool Reject(out RgbV3Packet? packet,out string detail)
    { packet=null;detail="Invalid profile extension count";return false; }

    private static bool Scan(Bitmap bitmap,int extensionCells,
        out RgbV3Packet? packet,out string detail)
    {
        packet = null;
        detail = "RGB v3 diagnostic strip not found (old v2 addon or hidden strip).";
        // The new v3 panel is anchored at UI top-left (0,-12).
        // Keep sampling in a small bounded region; old v2 stays untouched.
        int maxY = Math.Min(bitmap.Height, 80);
        int maxX = Math.Min(bitmap.Width, 32);
        for (int y = 0; y < maxY; ++y)
        for (int x = 0; x < maxX; ++x)
        {
            if (!Near(bitmap.GetPixel(x, y), 255, 0, 255))
                continue;
            for (int pitch = 3; pitch <= 12; ++pitch)
            {
                if (x + pitch * 23 >= bitmap.Width)
                    break;
                if (!Near(bitmap.GetPixel(x + pitch, y), 0, 255, 0) ||
                    !Near(bitmap.GetPixel(x + 2 * pitch, y), 255, 255, 255) ||
                    !Near(bitmap.GetPixel(x + 3 * pitch, y), 0, 0, 0))
                    continue;

                // The first five cells are always plain in both modes.
                // direct8: 24 physical cells. stepped4: 5 + (24-5)*2 = 43.
                var versionCell=bitmap.GetPixel(x + 4 * pitch,y);
                int encoding=versionCell.B & 3;
                if(encoding!=0 && encoding!=1)continue;
                int logicalCells=24+extensionCells;
                int cellCount=encoding==1?5+(logicalCells-5)*2:logicalCells;
                if(x + pitch*(cellCount-1)>=bitmap.Width)continue;
                var rgb=new byte[cellCount*3];
                for(int cell=0;cell<cellCount;cell++)
                {
                    Color color=bitmap.GetPixel(x+cell*pitch,y);
                    int offset=cell*3;
                    rgb[offset]=color.R;
                    rgb[offset+1]=color.G;
                    rgb[offset+2]=color.B;
                }
                if (RgbV3Codec.TryDecode(rgb, extensionCells, 0x4C47, out packet, out var error))
                {
                    detail = $"RGB v3 CRC PASS; frame={packet!.FrameCounter}; encoding={packet.Encoding}; position=({x},{y}); pitch={pitch}px";
                    return true;
                }
                detail = "RGB v3 detected but invalid: " + error;
            }
        }
        return false;
    }
}
