using System;
using System.Drawing;

namespace LazyGPrototype;

internal sealed record RgbThresholdProbe(string PlayerHp, string TargetHp, string Resource)
{
    public override string ToString() => $"curve probes: HP {PlayerHp} · target HP {TargetHp} · resource {Resource}";
}

internal static class RgbV3ThresholdDetector
{
    private static bool Near(Color c, int r, int g, int b, int tolerance = 15) =>
        Math.Abs(c.R - r) <= tolerance &&
        Math.Abs(c.G - g) <= tolerance &&
        Math.Abs(c.B - b) <= tolerance;

    // First 4 pixels of curve probe act as a unique marker: cyan / dark-green.
    // Groups contain one availability cell and 9 threshold cells each.
    public static bool FindPanel(Bitmap image, out RgbThresholdProbe? result)
    {
        result = null;
        int width = Math.Min(image.Width, 22);
        int height = Math.Min(image.Height, 90);
        for (int y = 0; y < height; y++)
        for (int x = 0; x < width; x++)
        {
            // First status is green or red, followed by a black/white threshold cell.
            // Candidate validity requires an entire plausible 30-cell group sequence;
            // location is disambiguated by y-offset from the v3 marker.
            for (int pitch = 3; pitch <= 10; pitch++)
            {
                if (x + pitch * 29 >= image.Width)
                    break;
                // Decode supported test rows only if status colors are valid
                // for all three groups and thresholds are essentially binary.
                var status = new bool[3];
                bool good = true;
                var bands = new string[3];
                for (int g = 0; g < 3 && good; g++)
                {
                    Color marker = image.GetPixel(x + g * 10 * pitch, y);
                    if (Near(marker, 0, 255, 0)) status[g] = true;
                    else if (Near(marker, 255, 0, 0)) status[g] = false;
                    else { good = false; break; }
                    if (!status[g]) { bands[g] = "unavailable"; continue; }
                    int last = 0;
                    bool seenOffAfterOn = false;
                    for (int i = 1; i <= 9; i++)
                    {
                        var pixel = image.GetPixel(x + (g * 10 + i) * pitch, y);
                        bool on = Near(pixel, 255, 255, 255, 30);
                        bool off = Near(pixel, 0, 0, 0, 30);
                        if (!on && !off) { good = false; break; }
                        if (on)
                        {
                            if (seenOffAfterOn) { good = false; break; }
                            last = i;
                        }
                        else if (last > 0)
                            seenOffAfterOn = true;
                    }
                    bands[g] = last == 0 ? "0–9%" : last == 9 ? "90–100%" :
                        $"{last * 10}–{last * 10 + 9}%";
                }
                if (!good || !status[0]) continue;
                result = new RgbThresholdProbe(bands[0], bands[1], bands[2]);
                return true;
            }
        }
        return false;
    }
}
