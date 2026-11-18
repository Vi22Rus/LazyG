using Avalonia.Media;
using Color = Avalonia.Media.Color;
namespace LazyG.Desktop;
internal static class Palette
{
    public static IBrush Brush(string html) => new SolidColorBrush(Color.Parse(html));
    public static readonly IBrush Background = Brush("#100D0C");
    public static readonly IBrush Surface = Brush("#241B16");
    public static readonly IBrush SurfaceAlt = Brush("#30231C");
    public static readonly IBrush Stroke = Brush("#60432B");
    public static readonly IBrush Gold = Brush("#EFB05C");
    public static readonly IBrush Muted = Brush("#B9A49A");
    public static readonly IBrush White = Brush("#F7EDE4");
}
