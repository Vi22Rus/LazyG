using System;
using System.Drawing;

namespace LazyGPrototype;

internal sealed record RgbPlayerState(byte ClassId, byte RaceId, byte Level, byte SpecIndex, byte TalentPoints, byte CombatFlags)
{
    public bool TargetExists => (CombatFlags & 1) != 0;
    public bool TargetHostile => (CombatFlags & 2) != 0;
    public bool TargetAlive => (CombatFlags & 4) != 0;
    public bool InCombat => (CombatFlags & 8) != 0;

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

/// <summary>Decodes protocol v2: 9 horizontal cells, each 4 UI units plus 1 UI gap.</summary>
internal static class RgbPanelDetector
{
    private static bool Near(Color color, int r, int g, int b, int tolerance = 18) =>
        Math.Abs(color.R - r) <= tolerance &&
        Math.Abs(color.G - g) <= tolerance &&
        Math.Abs(color.B - b) <= tolerance;

    private static bool Decode(Bitmap image, int x, int y, int pitch, out RgbPlayerState? state)
    {
        state = null;
        if (x + pitch * 8 >= image.Width) return false;
        if (!Near(image.GetPixel(x + pitch, y), 255, 0, 255) ||
            !Near(image.GetPixel(x + pitch * 2, y), 255, 255, 255) ||
            !Near(image.GetPixel(x + pitch * 3, y), 0, 0, 0) ||
            !Near(image.GetPixel(x + pitch * 8, y), 255, 0, 255))
            return false;

        var data = image.GetPixel(x + pitch * 4, y);
        var spec = image.GetPixel(x + pitch * 5, y);
        var flags = image.GetPixel(x + pitch * 6, y);
        var check = image.GetPixel(x + pitch * 7, y);
        if (data.R is < 1 or > 13 || data.G > 32 ||
            data.B is < 1 or > 100 || spec.R > 3 ||
            spec.B != 2 || flags.R > 15 || flags.G != 0 || flags.B != 0)
            return false;

        int signature = (data.R * 17 + data.G * 11 + data.B * 7 +
                         spec.R * 19 + spec.G * 3 + spec.B * 13 + flags.R * 23) % 256;
        if (!Near(check, signature, 255 - signature, 77, 3))
            return false;
        state = new RgbPlayerState(data.R, data.G, data.B, spec.R, spec.G, flags.R);
        return true;
    }

    public static bool FindPanel(Bitmap image, out RgbPlayerState? state, out string detail)
    {
        // The first cell is anchored at the client origin. Search a small
        // region only; sampling one pixel per cell avoids full-frame analysis.
        for (int y = 0; y < image.Height; y++)
        for (int x = 0; x < image.Width; x++)
        {
            if (!Near(image.GetPixel(x, y), 0, 255, 0)) continue;
            for (int pitch = 3; pitch <= 20; pitch++)
            {
                if (Decode(image, x, y, pitch, out state))
                {
                    detail = $"RGB protocol v2; position=({x},{y}); pitch={pitch}px";
                    return true;
                }
            }
        }
        state = null;
        detail = "RGB v2 packet not found near WoW client top-left. Check addon version, UI scale, visible window and other overlays.";
        return false;
    }
}
