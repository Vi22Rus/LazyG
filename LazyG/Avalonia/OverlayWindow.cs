using System;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Shapes;
using Button = Avalonia.Controls.Button;
using HAlign = Avalonia.Layout.HorizontalAlignment;
using VAlign = Avalonia.Layout.VerticalAlignment;

namespace LazyG.Desktop;

// Independent original LazyG overlay, based on the requested information hierarchy.
// No XML rotation engine yet: deliberately no fabricated spell icon, cooldown, GCD or readiness.
internal sealed class OverlayWindow : Window
{
    private readonly TextBlock signalStatus;
    private readonly TextBlock combatStatus;
    private readonly TextBlock specStatus;
    private readonly TextBlock pauseReason;
    private readonly TextBlock spellTitle;
    private readonly TextBlock gcdLabel;
    private readonly Button aoeButton;
    private readonly Button cdButton;
    private bool aoeEnabled;
    private bool cdEnabled;
    public OverlayWindow(Action close)
    {
        Title="LazyG Overlay";
        Width=420; Height=260;
        MinWidth=400; MinHeight=246;
        CanResize=false; ShowInTaskbar=false; Topmost=true;
        SystemDecorations=SystemDecorations.None;
        Background=Palette.Brush("#041421");
        var surface=new Border
        {
            Background=Palette.Brush("#0A2033"),
            BorderBrush=Palette.Brush("#228BB6"),
            BorderThickness=new Thickness(1),
            CornerRadius=new CornerRadius(16),
            Padding=new Thickness(16,11,16,11)
        };
        var outer=new StackPanel { Spacing=9 };
        var header=new Grid { ColumnDefinitions=new ColumnDefinitions("*,Auto,Auto,Auto,Auto"),ColumnSpacing=8 };
        var brand=new TextBlock { Text="◆  LAZYG",FontSize=14,FontWeight=FontWeight.Bold,
            Foreground=Palette.Brush("#E9F8FF"),VerticalAlignment=VAlign.Center };
        header.Children.Add(brand);
        signalStatus=new TextBlock { Text="●  NO SIGNAL",FontSize=10,FontWeight=FontWeight.Bold,
            Foreground=Palette.Brush("#B3B8D0"),VerticalAlignment=VAlign.Center };
        Grid.SetColumn(signalStatus,1);header.Children.Add(signalStatus);
        aoeButton=ModeButton("AOE OFF",()=> {
            aoeEnabled=!aoeEnabled;UpdateMode(aoeButton,"AOE",aoeEnabled);
            RuntimeDiagnostics.Add("OVERLAY","AoE preference "+(aoeEnabled?"ON":"OFF")+" (no rotation engine)");
        });
        Grid.SetColumn(aoeButton,2);header.Children.Add(aoeButton);
        cdButton=ModeButton("CD OFF",()=> {
            cdEnabled=!cdEnabled;UpdateMode(cdButton,"CD",cdEnabled);
            RuntimeDiagnostics.Add("OVERLAY","Cooldown preference "+(cdEnabled?"ON":"OFF")+" (no rotation engine)");
        });
        Grid.SetColumn(cdButton,3);header.Children.Add(cdButton);
        var closeButton=ModeButton("×",close);
        closeButton.Width=26;
        Grid.SetColumn(closeButton,4);header.Children.Add(closeButton);
        header.PointerPressed+=(_,e)=>{
            if(e.GetCurrentPoint(header).Properties.IsLeftButtonPressed && e.Source is not Button)
                BeginMoveDrag(e);
        };
        outer.Children.Add(header);

        var next=new Grid { ColumnDefinitions=new ColumnDefinitions("103,*"), ColumnSpacing=14 };
        var iconFrame=new Grid { Width=98,Height=98 };
        iconFrame.Children.Add(new Ellipse {Width=96,Height=96,Stroke=Palette.Brush("#42E8FC"),
            StrokeThickness=3,Fill=Palette.Brush("#061D32")});
        iconFrame.Children.Add(new Ellipse {Width=82,Height=82,Stroke=Palette.Brush("#1E9EC7"),
            StrokeThickness=1,Fill=Palette.Brush("#041421")});
        iconFrame.Children.Add(new Border {
            Width=68,Height=68,CornerRadius=new CornerRadius(10),
            BorderBrush=Palette.Brush("#2B93C1"),BorderThickness=new Thickness(1),
            Background=Palette.Brush("#061827"),
            Child=new TextBlock {Text="?",FontSize=36,FontWeight=FontWeight.Bold,
                Foreground=Palette.Brush("#588CA4"),
                HorizontalAlignment=HAlign.Center,VerticalAlignment=VAlign.Center}
        });
        next.Children.Add(iconFrame);
        var text= new StackPanel {Spacing=5,VerticalAlignment=VAlign.Center};
        text.Children.Add(new TextBlock {Text="NEXT SPELL",FontSize=10,FontWeight=FontWeight.Bold,
            Foreground=Palette.Brush("#9BC1D2")});
        spellTitle=new TextBlock {Text="NOT AVAILABLE",FontSize=22,FontWeight=FontWeight.Bold,
            Foreground=Palette.White};
        text.Children.Add(spellTitle);
        text.Children.Add(new TextBlock {Text="XML rotation engine is not installed",FontSize=11,
            Foreground=Palette.Muted,TextWrapping=TextWrapping.Wrap});
        gcdLabel=new TextBlock {Text="GCD: unavailable",FontSize=11,Foreground=Palette.Brush("#62E4F4")};
        text.Children.Add(gcdLabel);
        Grid.SetColumn(text,1);next.Children.Add(text);
        outer.Children.Add(next);

        var statusLine=new Grid { ColumnDefinitions=new ColumnDefinitions("Auto,*,Auto"),ColumnSpacing=12 };
        combatStatus=new TextBlock {Text="OUT OF COMBAT",FontSize=11,
            Foreground=Palette.Muted,VerticalAlignment=VAlign.Center};
        statusLine.Children.Add(combatStatus);
        specStatus=new TextBlock {Text="FOREVER",FontSize=11,Foreground=Palette.Muted,
            VerticalAlignment=VAlign.Center};
        Grid.SetColumn(specStatus,1);statusLine.Children.Add(specStatus);
        var ready=new TextBlock {Text="ROTATION IDLE",FontSize=11,FontWeight=FontWeight.Bold,
            Foreground=Palette.Brush("#5FDCF0"),VerticalAlignment=VAlign.Center};
        Grid.SetColumn(ready,2);statusLine.Children.Add(ready);
        outer.Children.Add(statusLine);

        var pause=new Grid {ColumnDefinitions=new ColumnDefinitions("Auto,*"),ColumnSpacing=13};
        pause.Children.Add(new TextBlock {Text="PAUSE",FontSize=12,FontWeight=FontWeight.Bold,
            Foreground=Palette.Brush("#56E4F6"),VerticalAlignment=VAlign.Center});
        pauseReason=new TextBlock {Text="No XML rotation configured",FontSize=12,
            Foreground=Palette.Brush("#B1D5E1"),TextWrapping=TextWrapping.Wrap,VerticalAlignment=VAlign.Center};
        Grid.SetColumn(pauseReason,1);pause.Children.Add(pauseReason);
        outer.Children.Add(new Border {Child=pause,CornerRadius=new CornerRadius(8),
            BorderBrush=Palette.Brush("#1F6686"),BorderThickness=new Thickness(1),
            Background=Palette.Brush("#061E32"),Padding=new Thickness(13,9)});
        surface.Child=outer;Content=surface;
    }
    private static Button ModeButton(string label,Action action)
    {
        var b=new Button {Content=label,FontSize=10,FontWeight=FontWeight.SemiBold,
            Foreground=Palette.Brush("#BADBEA"),Background=Palette.Brush("#0B3048"),
            BorderBrush=Palette.Brush("#246182"),BorderThickness=new Thickness(1),
            CornerRadius=new CornerRadius(13),MinHeight=25,Padding=new Thickness(8,2)};
        b.Click+=(_,_)=>action();
        return b;
    }
    private static void UpdateMode(Button button,string label,bool enabled)
    {
        button.Content=label+(enabled?" ON":" OFF");
        button.Foreground=Palette.Brush(enabled?"#062333":"#BADBEA");
        button.Background=Palette.Brush(enabled?"#19DEF1":"#0B3048");
    }
    public void SetConnection(bool connected,bool crc,bool curve,bool inCombat,string? gameClass,string? specName)
    {
        bool signalReady=connected && crc;
        signalStatus.Text=signalReady?"● RGB READY":connected?"● RGB V2":"● NO SIGNAL";
        signalStatus.Foreground=Palette.Brush(signalReady?"#4BEAA5":connected?"#70E5F6":"#B3B8D0");
        combatStatus.Text=inCombat?"IN COMBAT":"OUT OF COMBAT";
        specStatus.Text=connected?(gameClass=="Hunter"&&specName is not null?
            gameClass+" · "+specName:gameClass??"FOREVER"):"FOREVER";
        // "Ready" is reserved for verified signal, not for rotation execution.
        pauseReason.Text=signalReady?"No XML rotation configured":
            connected?"RGB v3 CRC not confirmed · rotation unavailable":
            "Game data unavailable · rotation paused";
        gcdLabel.Text="GCD: unavailable";
        spellTitle.Text="NOT AVAILABLE";
    }
}
