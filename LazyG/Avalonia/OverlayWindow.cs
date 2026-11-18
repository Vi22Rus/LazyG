using System;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using HAlign = Avalonia.Layout.HorizontalAlignment;

namespace LazyG.Desktop;

// Compact topmost overlay. Displays status only; no key input and no rotations.
internal sealed class OverlayWindow : Window
{
    private readonly TextBlock mainStatus;
    private readonly TextBlock detailStatus;
    public OverlayWindow(Action close)
    {
        Title="LazyG Overlay";
        Width=240; Height=104; MinWidth=210; MinHeight=94;
        CanResize=false; ShowInTaskbar=false; Topmost=true; ShowActivated=false;
        SystemDecorations=SystemDecorations.None;
        Background=Palette.Brush("#19130F");

        var border=new Border {
            CornerRadius=new CornerRadius(11),
            Background=Palette.Brush("#DE211814"),
            BorderBrush=Palette.Brush("#986A33"),
            BorderThickness=new Thickness(1),
            Padding=new Thickness(12,8)
        };
        var panel=new StackPanel { Spacing=5 };
        var header=new Grid {ColumnDefinitions=new ColumnDefinitions("*,Auto")};
        var title=new TextBlock {Text="◆  LazyG   ·   FOREVER", FontWeight=FontWeight.Bold,
            FontSize=12, Foreground=Palette.Brush("#EFB05C"),
            VerticalAlignment=VerticalAlignment.Center};
        header.Children.Add(title);
        var closeButton=new Button {Content="×",Width=28,Height=23,Padding=new Thickness(0),
            Foreground=Palette.White, Background=Palette.Brush("#39251C"),BorderThickness=new Thickness(0),
            HorizontalContentAlignment=HAlign.Center};
        closeButton.Click+=(_,_)=>close();
        Grid.SetColumn(closeButton,1);header.Children.Add(closeButton);
        header.PointerPressed+=(_,e)=>{
            if (e.GetCurrentPoint(header).Properties.IsLeftButtonPressed && e.Source is not Button)
                BeginMoveDrag(e);
        };
        panel.Children.Add(header);
        mainStatus=new TextBlock { Text="WAITING FOR WOW",FontSize=12,Foreground=Palette.White };
        detailStatus=new TextBlock { Text="No rotation engine",FontSize=11,Foreground=Palette.Muted };
        panel.Children.Add(mainStatus);panel.Children.Add(detailStatus);
        border.Child=panel;
        Content=border;
    }
    public void SetConnection(bool connected, bool crc, bool curve)
    {
        mainStatus.Text=connected?(crc?"RGB CONNECTED · CRC PASS":"RGB CONNECTED"):"GAME NOT CONNECTED";
        mainStatus.Foreground=Palette.Brush(connected?"#92DEA8":"#E9A47B");
        detailStatus.Text=curve?"Curve thresholds detected · Rotation idle":"Rotation engine not configured";
    }
}