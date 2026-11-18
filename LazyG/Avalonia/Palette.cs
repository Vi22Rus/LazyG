using Avalonia.Media;
using Color = Avalonia.Media.Color;

namespace LazyG.Desktop;

// Midnight Blue + Cyan: one semantic palette for all Avalonia windows.
internal static class Palette
{
    public static IBrush Brush(string html) => new SolidColorBrush(Color.Parse(html));
    public static readonly IBrush Background = Brush("#051320");
    public static readonly IBrush Surface = Brush("#0B2031");
    public static readonly IBrush SurfaceAlt = Brush("#102C3F");
    public static readonly IBrush Stroke = Brush("#216080");
    public static readonly IBrush Gold = Brush("#38DBF2");
    public static readonly IBrush Accent = Brush("#1DE5FC");
    public static readonly IBrush AccentSoft = Brush("#85F0FF");
    public static readonly IBrush Muted = Brush("#9DBCCB");
    public static readonly IBrush White = Brush("#F0F8FF");
    public static readonly IBrush Success = Brush("#41E9A5");
}
