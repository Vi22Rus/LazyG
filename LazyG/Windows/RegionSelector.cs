using System;
using System.Drawing;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using Forms=System.Windows.Forms;
namespace LazyGPrototype;
public sealed class RegionSelector : Window
{
    private readonly Canvas canvas=new();
    private readonly System.Windows.Shapes.Rectangle rect=new(){Stroke=System.Windows.Media.Brushes.LimeGreen,StrokeThickness=2,Fill=new SolidColorBrush(System.Windows.Media.Color.FromArgb(35,30,230,100))};
    private System.Windows.Point start;
    private bool selecting;
    public System.Drawing.Rectangle SelectedRegion {get;private set;}
    public RegionSelector()
    {
        Title="Select RGB panel (Esc to cancel)";WindowStyle=WindowStyle.None;ResizeMode=ResizeMode.NoResize;
        Topmost=true;ShowInTaskbar=false;AllowsTransparency=true;Background=new SolidColorBrush(System.Windows.Media.Color.FromArgb(50,0,0,0));
        // MVP limitation: capture area on the primary display.
        WindowStartupLocation=WindowStartupLocation.Manual;
        Left=0;Top=0;Width=SystemParameters.PrimaryScreenWidth;Height=SystemParameters.PrimaryScreenHeight;
        Content=canvas;canvas.Children.Add(rect);rect.Visibility=Visibility.Collapsed;
        var label=new TextBlock{Text="Drag to select full RGB panel  ·  Esc cancels",Foreground=System.Windows.Media.Brushes.White,Background=System.Windows.Media.Brushes.Black,FontSize=17};
        Canvas.SetLeft(label,25);Canvas.SetTop(label,25);canvas.Children.Add(label);
        MouseLeftButtonDown+=Down;MouseMove+=Move;MouseLeftButtonUp+=Up;
        KeyDown+=(_,e)=>{if(e.Key==Key.Escape){DialogResult=false;Close();}};
    }
    private void Down(object sender,MouseButtonEventArgs e)
    {start=e.GetPosition(canvas);selecting=true;CaptureMouse();rect.Visibility=Visibility.Visible;Canvas.SetLeft(rect,start.X);Canvas.SetTop(rect,start.Y);rect.Width=0;rect.Height=0;}
    private void Move(object sender,System.Windows.Input.MouseEventArgs e)
    {if(!selecting)return;var p=e.GetPosition(canvas);Canvas.SetLeft(rect,Math.Min(start.X,p.X));Canvas.SetTop(rect,Math.Min(start.Y,p.Y));rect.Width=Math.Abs(start.X-p.X);rect.Height=Math.Abs(start.Y-p.Y);}
    private void Up(object sender,MouseButtonEventArgs e)
    {
        if(!selecting)return;selecting=false;ReleaseMouseCapture();var p=e.GetPosition(canvas);
        var source=PresentationSource.FromVisual(this);if(source?.CompositionTarget==null)return;
        var transform=source.CompositionTarget.TransformToDevice;
        var a=transform.Transform(start);var b=transform.Transform(p);
        int x=(int)Math.Round(Math.Min(a.X,b.X));int y=(int)Math.Round(Math.Min(a.Y,b.Y));
        int w=(int)Math.Round(Math.Abs(b.X-a.X));int h=(int)Math.Round(Math.Abs(b.Y-a.Y));
        if(w<20 || h<4)return;
        SelectedRegion=new System.Drawing.Rectangle(x,y,w,h);DialogResult=true;Close();
    }
}
