using System;
using System.Drawing;

namespace LazyGPrototype;

internal sealed record RgbPlayerState(byte ClassId, byte RaceId, byte Level, byte SpecIndex, byte TalentPoints)
{
    public string ClassName => ClassId switch
    {
        1 => "Warrior", 2 => "Paladin", 3 => "Hunter", 4 => "Rogue",
        5 => "Priest", 6 => "Death Knight", 7 => "Shaman", 8 => "Mage",
        9 => "Warlock", 10 => "Monk", 11 => "Druid", 12 => "Demon Hunter",
        13 => "Evoker", _ => "Unknown"
    };

    public string RaceName => RaceId switch
    {
        1 => "Human", 2 => "Orc", 3 => "Dwarf", 4 => "Night Elf",
        5 => "Undead", 6 => "Tauren", 7 => "Gnome", 8 => "Troll",
        9 => "Goblin", 10 => "Blood Elf", 11 => "Draenei",
        12 => "Worgen", 13 => "Pandaren", _ => "Unknown"
    };

    public string SpecName => ClassId == 3 ? SpecIndex switch
    {
        1 => "Beast Mastery", 2 => "Marksmanship", 3 => "Survival",
        _ => "Undetermined"
    } : SpecIndex == 0 ? "Undetermined" : $"Talent tree {SpecIndex}";
}

/// <summary>Decodes the tiny four-column/two-row static protocol at the WoW client top-left.</summary>
internal static class RgbPanelDetector
{
    private static bool Near(Color p, int r, int g, int b, int tolerance = 20) =>
        Math.Abs(p.R - r) <= tolerance &&
        Math.Abs(p.G - g) <= tolerance &&
        Math.Abs(p.B - b) <= tolerance;

    private static bool Decode(Bitmap image, int x, int y, int stride, out RgbPlayerState? state)
    {
        state = null;
        int x1 = x + stride, x2 = x + 2 * stride, x3 = x + 3 * stride, y1 = y + stride;
        if (x3 >= image.Width || y1 >= image.Height) return false;

        if (!Near(image.GetPixel(x1, y), 255, 0, 255, 18) ||
            !Near(image.GetPixel(x2, y), 255, 255, 255, 18) ||
            !Near(image.GetPixel(x3, y), 0, 0, 0, 18) ||
            !Near(image.GetPixel(x3, y1), 255, 0, 255, 18))
            return false;

        Color data1 = image.GetPixel(x, y1);
        Color data2 = image.GetPixel(x1, y1);
        Color check = image.GetPixel(x2, y1);
        if (data1.R is < 1 or > 13 || data1.G > 32 ||
            data1.B is < 1 or > 100 || data2.R > 3 || data2.B != 1)
            return false;

        int signature = (data1.R * 17 + data1.G * 11 + data1.B * 7 +
                         data2.R * 19 + data2.G * 3 + data2.B * 13) % 256;
        if (!Near(check, signature, 255 - signature, 77, 3))
            return false;

        state = new RgbPlayerState(data1.R, data1.G, data1.B, data2.R, data2.G);
        return true;
    }

    public static bool FindPanel(Bitmap image, out RgbPlayerState? state, out string detail)
    {
        // The WoW scale can vary. The small search window is relative to
        // the client top-left, never the desktop or an arbitrary saved rectangle.
        for (int y = 0; y < image.Height; y++)
        for (int x = 0; x < image.Width; x++)
        {
            if (!Near(image.GetPixel(x, y), 0, 255, 0, 18)) continue;
            for (int stride = 4; stride <= 36; stride++)
            {
                if (Decode(image, x, y, stride, out state))
                {
                    detail = $"RGB protocol v1; position=({x},{y}); pitch={stride}px";
                    return true;
                }
            }
        }

        state = null;
        detail = "RGB packet not found near WoW client top-left. Check the installed addon, UI scale and visible game window.";
        return false;
    }
}
