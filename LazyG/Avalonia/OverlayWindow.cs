using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Linq;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Shapes;
using ArcPath = Avalonia.Controls.Shapes.Path;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Threading;
using LazyG.Desktop.Engine;
using Button = Avalonia.Controls.Button;
using HAlign = Avalonia.Layout.HorizontalAlignment;
using VAlign = Avalonia.Layout.VerticalAlignment;

namespace LazyG.Desktop;

// Forever display surface: actual Spell ID / icon/name lookup; the 1.5s GCD is DEMO ONLY.
// The rotation engine has not yet been implemented and this class sends no input.
internal sealed class OverlayWindow : Window
{
    private readonly TextBlock signalStatus;
    private readonly TextBlock combatStatus;
    private readonly TextBlock specStatus;
    private readonly TextBlock pauseReason;
    private readonly TextBlock spellTitle;
    private readonly TextBlock spellCaption;
    private readonly TextBlock spellContext;
    private readonly TextBlock gcdLabel;
    private readonly Border iconSurface;
    private readonly ArcPath gcdArc;
    private readonly Button aoeButton;
    private readonly Button cdButton;
    private readonly Button previewButton;
    private readonly TextBlock rotationLabel;
    private bool readonlySession;
    private readonly DispatcherTimer gcdTimer;
    private readonly Stopwatch demoClock = new();
    private readonly List<ForeverSpell> demoSpells;
    private readonly string recommendationClass;
    private int demoIndex=-1;
    private bool demoActive;
    private bool aoeEnabled;
    private bool cdEnabled;

    public OverlayWindow(Action close,string previewClass="Hunter")
    {
        recommendationClass=previewClass;
        demoSpells=ForeverSpellCatalog.ForClass(previewClass).ToList();
        if(demoSpells.Count==0) demoSpells=ForeverSpellCatalog.ForClass("Hunter").ToList();

        Title="LazyG Overlay";
        Width=450;Height=264;MinWidth=425;MinHeight=255;
        CanResize=false;ShowInTaskbar=false;Topmost=true;
        SystemDecorations=SystemDecorations.None;
        Background=Palette.Brush("#041421");

        var surface=new Border {Background=Palette.Brush("#0A2033"),
            BorderBrush=Palette.Brush("#228BB6"),BorderThickness=new Thickness(1),
            CornerRadius=new CornerRadius(16),Padding=new Thickness(13,10)};
        var outer=new StackPanel {Spacing=9};
        var header=new Grid {
            ColumnDefinitions=new ColumnDefinitions("*,Auto,Auto,Auto,Auto,Auto"),
            ColumnSpacing=5
        };
        header.Children.Add(new TextBlock {
            Text="◆  LAZYG",FontSize=13,FontWeight=FontWeight.Bold,
            Foreground=Palette.White,VerticalAlignment=VAlign.Center
        });
        signalStatus=new TextBlock {Text="●  NO SIGNAL",FontSize=10,FontWeight=FontWeight.Bold,
            Foreground=Palette.Muted,VerticalAlignment=VAlign.Center};
        Grid.SetColumn(signalStatus,1);header.Children.Add(signalStatus);

        aoeButton=ModeButton("AOE OFF",()=>{
            aoeEnabled=!aoeEnabled;UpdateMode(aoeButton,"AOE",aoeEnabled);
            RuntimeDiagnostics.Add("OVERLAY","AoE UI preference "+(aoeEnabled?"ON":"OFF")+" (rotation unavailable)");
        });
        Grid.SetColumn(aoeButton,2);header.Children.Add(aoeButton);
        cdButton=ModeButton("CD OFF",()=>{
            cdEnabled=!cdEnabled;UpdateMode(cdButton,"CD",cdEnabled);
            RuntimeDiagnostics.Add("OVERLAY","Cooldown UI preference "+(cdEnabled?"ON":"OFF")+" (rotation unavailable)");
        });
        Grid.SetColumn(cdButton,3);header.Children.Add(cdButton);
        previewButton=ModeButton("NEXT",NextPreview);
        var preview=previewButton;
        Avalonia.Controls.ToolTip.SetTip(preview,"Preview another archived spell and restart 1.5s demo GCD");
        Grid.SetColumn(preview,4);header.Children.Add(preview);
        var exit=ModeButton("×",close);exit.Width=25;
        Grid.SetColumn(exit,5);header.Children.Add(exit);
        header.PointerPressed+=(_,e)=>{
            if(e.GetCurrentPoint(header).Properties.IsLeftButtonPressed && e.Source is not Button)
                BeginMoveDrag(e);
        };
        outer.Children.Add(header);

        var next=new Grid {ColumnDefinitions=new ColumnDefinitions("103,*"),ColumnSpacing=13};
        var iconStack=new Grid {Width=98,Height=98};
        iconStack.Children.Add(new Ellipse {Width=96,Height=96,Stroke=Palette.Brush("#1D5771"),
            StrokeThickness=4,Fill=Palette.Brush("#061D32")});
        iconStack.Children.Add(new Ellipse {Width=82,Height=82,Stroke=Palette.Brush("#1E9EC7"),
            StrokeThickness=1,Fill=Palette.Brush("#041421")});
        iconSurface=new Border {Width=68,Height=68,ClipToBounds=true,CornerRadius=new CornerRadius(9),
            BorderBrush=Palette.Brush("#2B93C1"),BorderThickness=new Thickness(1),
            Background=Palette.Brush("#061827")};
        iconStack.Children.Add(iconSurface);
        gcdArc=new ArcPath {Stroke=Palette.Brush("#F5CF68"),StrokeThickness=4,
            StrokeLineCap=PenLineCap.Round,IsHitTestVisible=false};
        iconStack.Children.Add(gcdArc);
        next.Children.Add(iconStack);

        var right=new StackPanel {Spacing=4,VerticalAlignment=VAlign.Center};
        spellContext=new TextBlock {Text="SPELL DEMO · NO ROTATION EXECUTION",
            FontSize=10,FontWeight=FontWeight.Bold,Foreground=Palette.Brush("#85DDEE")};
        right.Children.Add(spellContext);
        spellTitle=new TextBlock {Text="NOT AVAILABLE",FontSize=19,
            FontWeight=FontWeight.Bold,Foreground=Palette.White,TextWrapping=TextWrapping.Wrap};
        right.Children.Add(spellTitle);
        spellCaption=new TextBlock {Text="Select NEXT to inspect a spell",FontSize=11,
            Foreground=Palette.Muted,TextWrapping=TextWrapping.Wrap};
        right.Children.Add(spellCaption);
        gcdLabel=new TextBlock {Text="GCD DEMO · 1.5s",FontSize=11,
            Foreground=Palette.Brush("#F5CF68")};
        right.Children.Add(gcdLabel);
        Grid.SetColumn(right,1);next.Children.Add(right);
        outer.Children.Add(next);

        var statusLine=new Grid {ColumnDefinitions=new ColumnDefinitions("Auto,*,Auto"),ColumnSpacing=10};
        combatStatus=new TextBlock {Text="OUT OF COMBAT",FontSize=11,
            Foreground=Palette.Muted,VerticalAlignment=VAlign.Center};
        statusLine.Children.Add(combatStatus);
        specStatus=new TextBlock {Text="FOREVER",FontSize=11,
            Foreground=Palette.Muted,VerticalAlignment=VAlign.Center};
        Grid.SetColumn(specStatus,1);statusLine.Children.Add(specStatus);
        rotationLabel=new TextBlock {Text="ROTATION IDLE",FontSize=11,FontWeight=FontWeight.Bold,
            Foreground=Palette.Brush("#5FDCF0"),VerticalAlignment=VAlign.Center};
        Grid.SetColumn(rotationLabel,2);statusLine.Children.Add(rotationLabel);
        outer.Children.Add(statusLine);

        var pause=new Grid {ColumnDefinitions=new ColumnDefinitions("Auto,*"),ColumnSpacing=12};
        pause.Children.Add(new TextBlock {Text="PAUSE",FontSize=12,FontWeight=FontWeight.Bold,
            Foreground=Palette.Brush("#56E4F6"),VerticalAlignment=VAlign.Center});
        pauseReason=new TextBlock {Text="XML rotation engine is not configured",FontSize=12,
            Foreground=Palette.Brush("#B1D5E1"),TextWrapping=TextWrapping.Wrap,
            VerticalAlignment=VAlign.Center};
        Grid.SetColumn(pauseReason,1);pause.Children.Add(pauseReason);
        outer.Children.Add(new Border {Child=pause,CornerRadius=new CornerRadius(8),
            BorderBrush=Palette.Brush("#1F6686"),BorderThickness=new Thickness(1),
            Background=Palette.Brush("#061E32"),Padding=new Thickness(12,8)});
        surface.Child=outer;Content=surface;

        gcdTimer=new DispatcherTimer {Interval=TimeSpan.FromMilliseconds(33)};
        gcdTimer.Tick+=(_,_)=>TickDemo();
        gcdTimer.Start();
        Closed+=(_,_)=>{gcdTimer.Stop();demoClock.Stop();};
        NextPreview();
    }

    private static Button ModeButton(string label,Action action)
    {
        var b=new Button {Content=label,FontSize=10,FontWeight=FontWeight.SemiBold,
            Foreground=Palette.Brush("#BADBEA"),Background=Palette.Brush("#0B3048"),
            BorderBrush=Palette.Brush("#246182"),BorderThickness=new Thickness(1),
            CornerRadius=new CornerRadius(12),MinHeight=25,Padding=new Thickness(7,2)};
        b.Click+=(_,_)=>action();return b;
    }
    private static void UpdateMode(Button b,string label,bool on)
    {
        b.Content=label+(on?" ON":" OFF");
        b.Foreground=Palette.Brush(on?"#062333":"#BADBEA");
        b.Background=Palette.Brush(on?"#19DEF1":"#0B3048");
    }

    // Future rotation-engine entry point: class-specific SpellID lookup.
    // No magic ID guessing and no automatic key input.
    public bool SetSpell(string className,int spellId,string language="en")
    {
        var spell=ForeverSpellCatalog.Find(className,spellId);
        if(spell is null)return false;
        DisplaySpell(spell,language,false);
        return true;
    }
    // The live preview contains ONLY the current XML recommendation. No
    // recommendation means no icon: never substitute a demo or stale spell.
    // This function never sends any input, even after Start.
    public void SetReadOnlyRecommendation(bool running,int? spellId,string status)
    {
        readonlySession=running;
        previewButton.IsEnabled=!running;
        spellContext.Text=running?"XML RECOMMENDATION · "+recommendationClass:
            "XML IDLE · "+recommendationClass;
        rotationLabel.Text=running?"XML PREVIEW ON":"ROTATION IDLE";
        pauseReason.Text=running?status:"No active XML rotation";
        if(!running)
        {
            if(demoActive)demoClock.Stop();
            ClearSpell();
            spellCaption.Text="No active XML recommendation for "+recommendationClass;
            return;
        }
        if(spellId is not int id || id<=0)
        {
            ClearSpell();
            spellTitle.Text="NO RECOMMENDATION";
            spellCaption.Text="No verified XML recommendation for "+recommendationClass+" · no ability selected";
            return;
        }
        var spell=ForeverSpellCatalog.Find(recommendationClass,id);
        if(spell is null)
        {
            var family=recommendationClass.Equals("Hunter",StringComparison.OrdinalIgnoreCase)?
                HunterSpellFamilies.BaseId(id):null;
            if(family is int baseId)
                spell=ForeverSpellCatalog.Find(recommendationClass,baseId);
        }
        if(spell is null)
        {
            ClearSpell();
            spellTitle.Text="SPELL "+id;
            spellCaption.Text="XML recommendation · icon not in catalog";
            return;
        }
        DisplaySpell(spell,"en",false);
        spellCaption.Text="XML RECOMMENDATION · SpellID "+id+
            (spell.SpellId==id?"":" · family icon");
        gcdLabel.Text="GCD: remaining time unobservable";
    }

    private void NextPreview()
    {
        if(readonlySession)return;
        if(demoSpells.Count==0) {ClearSpell();return;}
        demoIndex=(demoIndex+1)%demoSpells.Count;
        DisplaySpell(demoSpells[demoIndex],"en",true);
    }
    private void ClearSpell()
    {
        demoActive=false;demoClock.Reset();gcdArc.Data=null;
        spellTitle.Text="NOT AVAILABLE";
        spellCaption.Text="No spells in local catalog";
        gcdLabel.Text="GCD unavailable";
        iconSurface.Child=null;
    }
    private void DisplaySpell(ForeverSpell spell,string language,bool demo)
    {
        demoActive=demo;
        spellTitle.Text=spell.DisplayName(language);
        spellCaption.Text=(demo?"DEMO ONLY · ":"")+spell.ClassName+" · SpellID "+spell.SpellId+
            (spell.GenericAttackFallback?" · Generic attack icon":"");
        var icon=ForeverSpellCatalog.Icon(spell);
        iconSurface.Child=icon is null
            ? new TextBlock {Text="?",FontSize=28,Foreground=Palette.Muted,
                HorizontalAlignment=HAlign.Center,VerticalAlignment=VAlign.Center}
            : new Avalonia.Controls.Image {Source=icon,Width=68,Height=68,
                Stretch=Stretch.Fill,IsHitTestVisible=false};
        if(demo){demoClock.Restart();RuntimeDiagnostics.Add("SPELL","Preview "+spell.ClassName+"/"+spell.SpellId);}
        else {demoClock.Reset();gcdArc.Data=null;gcdLabel.Text="GCD: no live telemetry";}
    }
    private void TickDemo()
    {
        if(!demoActive)return;
        const double ms=1500;
        double elapsed=demoClock.Elapsed.TotalMilliseconds%ms;
        double progress=Math.Clamp(elapsed/ms,0.001,0.999);
        double angle=2*Math.PI*progress;
        double x=49+46*Math.Sin(angle),y=49-46*Math.Cos(angle);
        string N(double d)=>d.ToString("0.###",CultureInfo.InvariantCulture);
        gcdArc.Data=Geometry.Parse($"M 49,3 A 46,46 0 {(progress>0.5?1:0)} 1 {N(x)},{N(y)}");
        gcdLabel.Text="GCD DEMO · "+((ms-elapsed)/1000).ToString("0.0",CultureInfo.InvariantCulture)+"s / 1.5s";
    }
    public void SetConnection(bool connected,bool crc,bool curve,bool inCombat,string? gameClass,string? specName)
    {
        bool ready=connected&&crc;
        signalStatus.Text=ready?"● RGB READY":connected?"● RGB V2":"● NO SIGNAL";
        signalStatus.Foreground=Palette.Brush(ready?"#4BEAA5":connected?"#70E5F6":"#B3B8D0");
        combatStatus.Text=inCombat?"IN COMBAT":"OUT OF COMBAT";
        specStatus.Text=connected?((gameClass??"FOREVER")+
            (string.IsNullOrEmpty(specName)?"":" · "+specName)):"FOREVER";
        if(!readonlySession)
            pauseReason.Text=ready?"Read-only XML preview not started":
                connected?"RGB v3 CRC not confirmed · preview unavailable":
                "Game data unavailable · preview paused";
        // Do NOT overwrite spell preview: it is expressly not a live recommendation.
    }
}
