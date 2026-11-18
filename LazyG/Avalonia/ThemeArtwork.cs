using System;
using System.IO;
using Avalonia.Media.Imaging;

namespace LazyG.Desktop;

// Decorative illustration loaded entirely from the EXE; no remote images.
internal static class ThemeArtwork
{
    private static Bitmap? _background;
    private static bool _attempted;
    public static Bitmap? Background()
    {
        if (_attempted) return _background;
        _attempted = true;
        try
        {
            using var stream=typeof(ThemeArtwork).Assembly.GetManifestResourceStream("LazyG.MidnightBackdrop");
            if(stream is null)return null;
            using var reader=new StreamReader(stream);
            using var data=new MemoryStream(Convert.FromBase64String(reader.ReadToEnd().Trim()));
            _background=new Bitmap(data);
        }
        catch(Exception){ _background=null; }
        return _background;
    }
}
