using System;
using System.IO;
using System.Linq;
using LazyG.Desktop.Engine;
using System.Threading.Tasks;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Threading;
using LazyGPrototype;
using LazyG.Desktop.Diagnostics;
using Control = Avalonia.Controls.Control;
using Button = Avalonia.Controls.Button;
using CheckBox = Avalonia.Controls.CheckBox;
using TextBox = Avalonia.Controls.TextBox;
using Orientation = Avalonia.Layout.Orientation;
using HAlign = Avalonia.Layout.HorizontalAlignment;

namespace LazyG.Desktop;

public sealed class MainWindow : Window
{
    private readonly UserSession session = UserSession.Load();
    private readonly Border rootBody = new();
    private readonly TextBlock statusText = Text("GAME NOT CONNECTED",12,"#93CBE5");
    private readonly TextBlock clientText = Text("WOW FOREVER",12,"#6CE7FA");
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromMilliseconds(400) };
    private readonly GameClient client = ClientCatalog.Forever;
    private GameClass? selectedClass;
    private Specialization? selectedSpec;
    private string view = "classes";
    private bool scanning;
    private bool setupOpen;
    private OverlayWindow? overlay;
    private Button? overlayButton;
    private Button? classesTab;
    private Button? commonTab;
    private Button? supportTab;
    private TextBox? diagnosticsOutput;
    private string lastBridgeState = "";
    private string lastProbeState = "";
    private string lastGameStateDiagnostic = "";
    private bool spellDiagnosticEnabled;
    private bool cooldownDiagnosticEnabled;
    private string lastCooldownDiagnostic="";
    private readonly ForeverCooldownObserver cooldownObserver=new();
    private readonly RgbTransportMonitor rgbMonitor=new();
    private readonly RotationSourceManager sourceManager=new();
    private readonly HunterRotationAudit hunterAudit=new();
    private TextBlock? hunterAuditSummaryText;
    private bool hunterAuditRecording;
    private bool hunterExecutionArmed;
    private readonly System.Collections.Generic.Dictionary<int,int> hunterExecutionKeys=new();
    private DateTimeOffset hunterLastKeyAt;
    private int? hunterLastAutoShotEpoch;
    private int hunterKeyAttempts;
    private int hunterKeySubmitted;

    private DateTimeOffset lastHunterAuditSample;
    private byte? lastCastEventSequence;
    private int lastCastEventSpellId;
    private RotationProfileV2? hunterAuditProfile;
    private System.Collections.Generic.IReadOnlyDictionary<string,int>? hunterAuditSettings;
    private TextBlock? rgbHealthText;
    private string lastRgbHealthSignature="";
    private bool fullRgbDiagnosticMode;
    private bool xmlPreviewEnabled;
    private XmlRotationProfile? xmlPreviewProfile;
    private string lastXmlPreview = "";
    private string lastSpellDiagnostic = "";
    private byte? lastSpellSequence;
    private DateTimeOffset lastSpellPacketAt;
    private SpellProbe? lastSpellPacket;
    private LazyG.Desktop.Engine.GameState latestGameState = LazyG.Desktop.Engine.GameState.Empty(DateTimeOffset.UtcNow);
    private bool finished;
    public MainWindow()
    {
        Title = "LazyG · 0.4.0-dev · foundation";
        RuntimeDiagnostics.Add("APP", "LazyG 0.4.0-dev foundation started · Forever UI");
        Width = 1280; Height = 820; MinWidth = 850; MinHeight = 560;
        Background = Palette.Background; Foreground = Palette.White;
        SystemDecorations = SystemDecorations.None;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Content = CreateShell();
        ShowClasses();
        timer.Tick += async (_, _) => await PollBridgeAsync();
        timer.Start();
        Closed += (_, _) => { finished = true; timer.Stop(); overlay?.Close(); };
        Opened += (_, _) =>
        {
            if (!session.ForeverConfigured)
                Dispatcher.UIThread.Post(ShowSetup);
        };
    }
    private static TextBlock Text(string text, double size = 14, string foreground = "#F1FAFF", FontWeight? weight = null) =>
        new() { Text = text, FontSize = size, Foreground = Palette.Brush(foreground),
            FontWeight = weight ?? FontWeight.Normal, TextWrapping = TextWrapping.Wrap,
            VerticalAlignment = VerticalAlignment.Center };
    private static Border Pane(Control child, string bg="#0D2436", double radius=12, string stroke="#1B5676", Thickness? padding=null) =>
        new() { Child = child, Background = Palette.Brush(bg), CornerRadius = new CornerRadius(radius),
            BorderBrush = Palette.Brush(stroke), BorderThickness = new Thickness(1), Padding = padding ?? new Thickness(16) };
    private static StackPanel Stack(Orientation orientation = Orientation.Vertical, double spacing=0) =>
        new() { Orientation=orientation, Spacing=spacing };
    private static Button Action(string label, Action click, bool primary=false, double minWidth=0)
    {
        var b = new Button { Content=label, Padding=new Thickness(19,9), MinWidth=minWidth,
            HorizontalContentAlignment=HAlign.Center, VerticalContentAlignment=VerticalAlignment.Center,
            Background=Palette.Brush(primary?"#19D9F4":"#0D283D"), Foreground=Palette.Brush(primary?"#052030":"#EDF8FF"),
            BorderBrush=Palette.Brush(primary?"#7CEFFD":"#275B75"), BorderThickness=new Thickness(1),
            CornerRadius=new CornerRadius(9), FontWeight=FontWeight.SemiBold };
        b.Click += (_,_)=>click();
        return b;
    }
    private Control CreateShell()
    {
        var shell = new Grid { RowDefinitions=new RowDefinitions("58,*,34") };
        var header = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,Auto,*,Auto,Auto,Auto,Auto"),
            Background=new LinearGradientBrush {
                StartPoint=new RelativePoint(0,0,RelativeUnit.Relative),
                EndPoint=new RelativePoint(1,0,RelativeUnit.Relative),
                GradientStops=new GradientStops {
                    new GradientStop(Avalonia.Media.Color.Parse("#082A43"),0),
                    new GradientStop(Avalonia.Media.Color.Parse("#082337"),0.54),
                    new GradientStop(Avalonia.Media.Color.Parse("#061B2D"),1)
                }
            } };
        header.PointerPressed += (_,e) => { if (e.GetCurrentPoint(header).Properties.IsLeftButtonPressed && e.Source is not Button) BeginMoveDrag(e); };
        var brand = Stack(Orientation.Horizontal,11);
        brand.VerticalAlignment=VerticalAlignment.Center;
        brand.Children.Add(Text("◆",22,"#38DEEF",FontWeight.Bold));
        brand.Children.Add(Text("LazyG",24,"#F3F9FF",FontWeight.Bold));
        brand.Margin=new Thickness(20,0,28,0);
        header.Children.Add(brand);

        var tabs = Stack(Orientation.Horizontal,8);
        tabs.VerticalAlignment=VerticalAlignment.Center;
        classesTab=Action("⚔  Classes & Specs",ShowClasses);
        commonTab=Action("⚗  Racials & Consumables",ShowCommon);
        supportTab=Action("◉  Support",ShowSupport);
        tabs.Children.Add(classesTab);
        tabs.Children.Add(commonTab);
        tabs.Children.Add(supportTab);
        Grid.SetColumn(tabs,1);header.Children.Add(tabs);
        var game = Stack(Orientation.Horizontal,9);
        game.VerticalAlignment=VerticalAlignment.Center;
        game.HorizontalAlignment=HAlign.Right;
        game.Margin=new Thickness(8);
        game.Children.Add(clientText);game.Children.Add(Text("●",12,"#40E8A2"));game.Children.Add(statusText);
        Grid.SetColumn(game,3);header.Children.Add(game);
        overlayButton=Action("Overlay OFF",ToggleOverlay);
        overlayButton.Margin=new Thickness(5,0,5,0);
        Grid.SetColumn(overlayButton,4);header.Children.Add(overlayButton);
        var setup=Action("Setup",ShowSetup);
        setup.Margin=new Thickness(8,0,12,0);Grid.SetColumn(setup,5);header.Children.Add(setup);
        var wins=Stack(Orientation.Horizontal,0); wins.VerticalAlignment=VerticalAlignment.Stretch;
        wins.Children.Add(WindowAction("—",()=>WindowState=WindowState.Minimized));
        wins.Children.Add(WindowAction("□",()=>WindowState=WindowState==WindowState.Maximized?WindowState.Normal:WindowState.Maximized));
        wins.Children.Add(WindowAction("×",Close,true));
        Grid.SetColumn(wins,6);header.Children.Add(wins);
        var headerBorder=new Border { Child=header,BorderBrush=Palette.Brush("#28718D"),
            BorderThickness=new Thickness(0,0,0,1) };
        Grid.SetRow(headerBorder,0);shell.Children.Add(headerBorder);
        // The landscape is precomposed at a consistent 1440:800 aspect ratio,
        // with feathered transitions into the same base gradient at EVERY edge.
        // Render it as a single full-viewport decorative layer, not a fixed
        // 780x445 image attached to the bottom-right corner.
        var backdropLayer=new Grid { ClipToBounds=true };
        var backdropImage=ThemeArtwork.Background();
        if (backdropImage is not null)
        {
            backdropLayer.Children.Add(new Avalonia.Controls.Image {
                Source=backdropImage,
                Stretch=Stretch.UniformToFill,
                IsHitTestVisible=false,
                HorizontalAlignment=HAlign.Stretch,
                VerticalAlignment=Avalonia.Layout.VerticalAlignment.Stretch
            });
        }
        backdropLayer.Children.Add(new ScrollViewer { Content=rootBody,
            HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled,
            VerticalScrollBarVisibility=ScrollBarVisibility.Auto });
        var bodyWrap = new Border {
            ClipToBounds=true,
            Background=new LinearGradientBrush {
                StartPoint=new RelativePoint(0,0,RelativeUnit.Relative),
                EndPoint=new RelativePoint(1,1,RelativeUnit.Relative),
                GradientStops=new GradientStops {
                    new GradientStop(Avalonia.Media.Color.Parse("#092A43"),0),
                    new GradientStop(Avalonia.Media.Color.Parse("#061B2F"),0.57),
                    new GradientStop(Avalonia.Media.Color.Parse("#020D1A"),1)
                }
            },Child=backdropLayer
        };
        Grid.SetRow(bodyWrap,1);shell.Children.Add(bodyWrap);
        var footer = new Grid { ColumnDefinitions=new ColumnDefinitions("*,Auto"), Background=Palette.Brush("#031524"),
            Margin=new Thickness(0) };
        footer.Children.Add(Text("  LazyG 0.4.0-dev foundation  ·  Forever profile  ·  Local desktop application",11,"#719BB2"));
        var fw=Text("Rotation engine: not configured   ·   No automatic input",11,"#719BB2");
        fw.Margin=new Thickness(10,0,18,0);Grid.SetColumn(fw,1);footer.Children.Add(fw);
        Grid.SetRow(footer,2);shell.Children.Add(footer);
        return shell;
    }
    private Button WindowAction(string label,Action action,bool close=false)
    {
        var b=new Button { Content=label,Width=45,Padding=new Thickness(0),
            Background=Palette.Brush("#061B2D"), Foreground=Palette.White, BorderThickness=new Thickness(0),
            FontSize=17,VerticalContentAlignment=VerticalAlignment.Center,HorizontalContentAlignment=HAlign.Center };
        b.Click+=(_,_)=>action();
        if (close) b.PointerEntered+=(_,_)=>b.Background=Palette.Brush("#B3344E");
        if (close) b.PointerExited+=(_,_)=>b.Background=Palette.Brush("#061B2D");
        return b;
    }
    private static Border SpellIcon(string key,int size=56)
    {
        var image=IconPack.Create(key,size);
        return new Border { Width=size,Height=size,CornerRadius=new CornerRadius(9),
            Background=Palette.Brush("#061D2B"), ClipToBounds=true,
            BorderBrush=Palette.Brush("#408DB3"), BorderThickness=new Thickness(1),
            Child=image };
    }
    private Border Page(string title,string subtitle,Control content,string? back=null,Action? backAction=null)
    {
        var contentStack=Stack(spacing:20);
        contentStack.Margin = new Thickness(28,24,28,35);
        if(back is not null && backAction is not null)
            contentStack.Children.Add(Action("← "+back,backAction));
        contentStack.Children.Add(Text(title,30,"#F1FAFF",FontWeight.Bold));
        contentStack.Children.Add(Text(subtitle,13,"#9EB9C9"));
        contentStack.Children.Add(content);
        return new Border { MaxWidth=1600,HorizontalAlignment=HAlign.Center,
            Child=contentStack,Width=double.NaN };
    }
    private void Go(Control page)
    {
        rootBody.Child=page;
        var tabs=new[] { (button:classesTab,selected:view=="classes"||view=="specs"||view=="rotation"),
                         (button:commonTab,selected:view=="common"),
                         (button:supportTab,selected:view=="support") };
        foreach(var tab in tabs)
        {
            if(tab.button is null)continue;
            tab.button.BorderBrush=Palette.Brush(tab.selected?"#26E8FC":"#26546C");
            tab.button.Background=Palette.Brush(tab.selected?"#0A4563":"#0A2437");
            tab.button.Foreground=Palette.Brush(tab.selected?"#F6FDFF":"#C8E1F0");
            tab.button.BorderThickness=new Thickness(tab.selected?2:1);
        }
    }
    private void ShowClasses()
    {
        view="classes"; selectedClass=null; selectedSpec=null;
        var wrap=Stack(spacing:19);
        var selection = client.Classes.FirstOrDefault(c=>c.Id==session.LastClass);
        var lastSpec = selection?.Specs.FirstOrDefault(s=>s.Id==session.LastSpec);
        if(selection is not null && lastSpec is not null)
        {
            var last = new Grid { ColumnDefinitions=new ColumnDefinitions("Auto,*,Auto"), ColumnSpacing=17 };
            last.Children.Add(SpellIcon(lastSpec.Icon,59));
            var labels=Stack(spacing:3);labels.Children.Add(Text("LAST USED",11,"#52E3F4",FontWeight.Bold));
            labels.Children.Add(Text(lastSpec.Name+"  ·  "+selection.Name,20,"#FFFFFF",FontWeight.SemiBold));
            labels.Children.Add(Text("Your previous specialization · Start requires an installed XML rotation",12,"#A3BCCC"));
            Grid.SetColumn(labels,1);last.Children.Add(labels);
            var b=Action("Start",()=>RequestStart(selection,lastSpec),true);b.VerticalAlignment=VerticalAlignment.Center;

            Grid.SetColumn(b,2);last.Children.Add(b);
            wrap.Children.Add(Pane(last,"#102B41"));
        }
        else
        {
            var top=Stack(Orientation.Horizontal,10);top.Children.Add(Text("●",12,"#29CFEA"));
            top.Children.Add(Text("Choose a class to browse its specializations",14,"#ACD1DF"));
            wrap.Children.Add(Pane(top,"#0B2840"));
        }
        wrap.Children.Add(Text("CLASSES",15,"#58E8FB",FontWeight.Bold));
        // The reference deliberately uses 5 narrow tiles above 4 slightly wider tiles.
        // Neither row upscales when the window becomes maximized.
        var rows=Stack(spacing:14);
        var five=new StackPanel {Orientation=Orientation.Horizontal,Spacing=12,HorizontalAlignment=HAlign.Center};
        var four=new StackPanel {Orientation=Orientation.Horizontal,Spacing=12,HorizontalAlignment=HAlign.Center};
        for(int i=0;i<client.Classes.Length;i++)
        {
            var cls=client.Classes[i];
            if(i<5) five.Children.Add(ClassTile(cls,166));
            else four.Children.Add(ClassTile(cls,211));
        }
        var classesGrid=Stack(spacing:12);
        classesGrid.Children.Add(five);classesGrid.Children.Add(four);
        rows.Children.Add(new Viewbox { Child=classesGrid,Stretch=Stretch.Uniform,
            StretchDirection=StretchDirection.DownOnly,HorizontalAlignment=HAlign.Center });
        wrap.Children.Add(rows);
        Go(Page("CLASSES & SPECS","WoW Forever · 9 classes · Select a class to explore its specializations",wrap));
    }
    private Control ClassTile(GameClass cls,double tileWidth)
    {
        var body=Stack(spacing:10);
        body.HorizontalAlignment=HAlign.Center;
        body.Children.Add(SpellIcon(cls.Icon,73));
        body.Children.Add(Text(cls.Name,17,cls.Accent,FontWeight.Bold));
        body.Children.Add(Text("3 specializations",11,"#9CB8CA"));
        var open=Action("View specs",()=>ShowClass(cls),true);
        open.HorizontalAlignment=HAlign.Stretch;
        body.Children.Add(open);
        var pane=Pane(body,"#11283B",12,"#2B6686",new Thickness(18,19));
        pane.Width=tileWidth;pane.MinHeight=187;
        pane.PointerPressed+=(_,e)=> { if(e.Source is not Button) ShowClass(cls); };
        pane.PointerEntered+=(_,_)=>pane.BorderBrush=Palette.Brush("#2BECFF");
        pane.PointerExited+=(_,_)=>pane.BorderBrush=Palette.Brush("#2B6686");
        return pane;
    }
    private void ShowClass(GameClass cls)
    {
        selectedClass=cls;selectedSpec=null;view="specs";
        var body=Stack(spacing:21);
        var intro=Stack(Orientation.Horizontal,14);
        intro.Children.Add(SpellIcon(cls.Icon,63));
        var txt=Stack(spacing:4);txt.Children.Add(Text(cls.Name,23,cls.Accent,FontWeight.Bold));
        txt.Children.Add(Text("Choose a specialization · PvE / PvP settings will follow the rotation XML",12,"#B2CCD9"));
        intro.Children.Add(txt);
        body.Children.Add(Pane(intro,"#332219"));
        var grid=new Grid { ColumnDefinitions=new ColumnDefinitions("Auto,Auto,Auto"),ColumnSpacing=13 };
        for(int i=0;i<cls.Specs.Length;i++)
        {
            var spec=cls.Specs[i];
            var p=Stack(spacing:16);p.HorizontalAlignment=HAlign.Center;
            p.Children.Add(SpellIcon(spec.Icon,73));
            p.Children.Add(Text(spec.Name,15,"#FFFFFF",FontWeight.Bold));
            p.Children.Add(Text("Rotation not installed",12,"#90B7C9"));
            p.Children.Add(Action("Open",()=>ShowSpec(cls,spec),true,120));
            var box=Pane(p,"#0C2336",12,"#2A6784",new Thickness(14,17));
            box.Width=176;box.MinHeight=187;
            box.PointerEntered+=(_,_)=>box.BorderBrush=Palette.Brush("#2BECFF");
            box.PointerExited+=(_,_)=>box.BorderBrush=Palette.Brush("#2A6784");
            Grid.SetColumn(box,i);grid.Children.Add(box);
        }
        body.Children.Add(new Viewbox { Child=grid, Stretch=Stretch.Uniform, StretchDirection=StretchDirection.DownOnly, HorizontalAlignment=HAlign.Center });
        Go(Page(cls.Name.ToUpperInvariant()+" SPECIALIZATIONS","Forever · Class library",body,"Classes",ShowClasses));
    }
    // Generated directly from the XML v2 rule parameter schema: no separate UI setting list.
    // Editing an experimental profile is offline configuration, NOT live cast authorization.
    private void ShowSpec(GameClass cls,Specialization spec,string mode="PvE",
        string tier="Essentials",bool changedOnly=false)
    {
        selectedClass=cls;selectedSpec=spec;view="rotation";
        session.LastClient="forever";session.LastClass=cls.Id;session.LastSpec=spec.Id;session.Save();
        var body=Stack(spacing:17);
        var top=Stack(Orientation.Horizontal,16);top.Children.Add(SpellIcon(spec.Icon,76));
        var identity=Stack(spacing:5);
        identity.Children.Add(Text(spec.Name,25,"#FFFFFF",FontWeight.Bold));
        identity.Children.Add(Text(cls.Name+" · Forever · Internal XML (not executing)",12,cls.Accent));
        top.Children.Add(identity);body.Children.Add(Pane(top));
        var modeTabs=Stack(Orientation.Horizontal,8);
        modeTabs.Children.Add(Action(mode=="PvE"?"PvE ✓":"PvE",
            ()=>ShowSpec(cls,spec,"PvE","Essentials"),mode=="PvE"));
        modeTabs.Children.Add(Action(mode=="PvP"?"PvP ✓":"PvP",
            ()=>ShowSpec(cls,spec,"PvP","Essentials"),mode=="PvP"));
        body.Children.Add(modeTabs);
        var source=sourceManager.Snapshot(DateTimeOffset.UtcNow);
        bool externalActive=source.Confirmed is RotationSourceId.Hekili or RotationSourceId.JustAC;
        body.Children.Add(Text(externalActive
            ?"External source confirmed: built-in settings locked; values preserved."
            :"Source RGB not installed. Settings may be edited offline; no automatic input is enabled.",
            12,externalActive?"#E9B26D":"#94CDE4"));
        RotationProfileV2? profile;
        try { profile=RotationProfileCatalog.Load(cls.Id,spec.Id,mode); }
        catch(Exception ex)
        {
            RuntimeDiagnostics.Add("XML2","Profile load rejected: "+ex.GetType().Name);
            body.Children.Add(Text("Invalid embedded XML; rotation blocked.",14,"#EAA3A3"));
            Go(Page(spec.Name.ToUpperInvariant(),"Rotation settings",body,cls.Name,()=>ShowClass(cls)));
            return;
        }
        if(profile is null)
        {
            body.Children.Add(Pane(Text("No validated XML profile for this specialization and mode. Settings are unavailable; no placeholder controls are shown.",14,"#E8C4A6")));
            Go(Page(spec.Name.ToUpperInvariant(),"Rotation settings",body,cls.Name,()=>ShowClass(cls)));
            return;
        }
        body.Children.Add(Text("EXPERIMENTAL · Offline-only profile. Spell ranks, signals and priorities require Forever gameplay verification.",12,"#F3C48C"));
        if(cls.Id=="hunter" && spec.Id=="beast-mastery" && mode=="PvE")
        {
            body.Children.Add(Action("Hunter BM — открыть диагностику XML",ShowSupport));
            body.Children.Add(Text("Для теста: Support → Start Hunter BM audit; Save Hunter audit JSON. Факт успешного применения заклинания текущим RGB не подтверждается.",11,"#B7A88E"));
        }
        string settingsFile=Path.Combine(Environment.GetFolderPath(
            Environment.SpecialFolder.LocalApplicationData),"LazyG","rotations",
            "forever-"+cls.Id+"-"+spec.Id+"-"+mode.ToLowerInvariant()+".json");
        System.Collections.Generic.Dictionary<string,int> overrides;
        try {overrides=new System.Collections.Generic.Dictionary<string,int>(
            RotationSettingsStore.Load(settingsFile,profile));}
        catch(Exception ex)
        {
            RuntimeDiagnostics.Add("XML2","Override load rejected: "+ex.GetType().Name);
            body.Children.Add(Text("Saved settings invalid. Defaults are displayed; saving is disabled until the file is repaired.",12,"#EAA3A3"));
            Go(Page(spec.Name.ToUpperInvariant(),"Rotation settings",body,cls.Name,()=>ShowClass(cls)));
            return;
        }
        int changes=overrides.Count(kv=>profile.Settings.TryGetValue(kv.Key,out var d) && d.Default!=kv.Value);
        var toolbar=Stack(Orientation.Horizontal,8);
        toolbar.Children.Add(Action(tier=="Essentials"?"Essentials ✓":"Essentials",
            ()=>ShowSpec(cls,spec,mode,"Essentials",changedOnly),tier=="Essentials"));
        toolbar.Children.Add(Action(tier=="Advanced"?"Advanced ✓":"Advanced",
            ()=>ShowSpec(cls,spec,mode,"Advanced",changedOnly),tier=="Advanced"));
        toolbar.Children.Add(Action(changedOnly?"Changed only ✓ ("+changes+")":"Changed only ("+changes+")",
            ()=>ShowSpec(cls,spec,mode,tier,!changedOnly)));
        var reset=Action("Reset defaults",()=>{
            if(externalActive)return;
            // Reset is explicit: retained backup via settings store and confirmed in a second click.
            ShowRotationResetConfirmation(cls,spec,profile,settingsFile,mode,tier);
        });
        reset.IsEnabled=!externalActive;toolbar.Children.Add(reset);
        body.Children.Add(toolbar);
        int shown=0;
        foreach(var setting in profile.Settings.Values.OrderBy(s=>s.Group).ThenBy(s=>s.Id))
        {
            if(setting.Tier!=tier || (changedOnly &&
                (!overrides.TryGetValue(setting.Id,out var v) || v==setting.Default)))continue;
            shown++;
            var settingLocal=setting;
            var pane=Stack(spacing:7);
            pane.Children.Add(Text(setting.LabelRu+" / "+setting.LabelEn,14,"#E9F9FF",FontWeight.SemiBold));
            var referencedRules=profile.Rules.Where(rule=>rule.EnabledBy==setting.Id ||
                rule.Conditions.Any(cond=>cond.SettingRef==setting.Id ||
                    cond.WhenEnabled==setting.Id)).ToArray();
            var referencedSignals=referencedRules.SelectMany(rule=>rule.Conditions)
                .Select(cond=>cond.Signal).Distinct().ToArray();
            pane.Children.Add(Text(setting.Group+" · "+setting.Unit+" · default "+setting.Default+
                " · rules: "+string.Join(", ",referencedRules.Select(rule=>
                    rule.Id+" (SpellID "+rule.SpellId+")")),11,"#8CAEC1"));
            pane.Children.Add(Text("Signals: "+
                (referencedSignals.Length==0?"spell/GCD/target proof":string.Join(", ",referencedSignals))+
                " · Live readiness unverified (Unknown blocks).",11,"#B7A88E"));
            if(referencedSignals.Contains("PowerPercent"))
                pane.Children.Add(Text("Forever Curve: только интервалы 0–4%, 5–9%, 10–14%…95–100%; порог с шагом 5%. Не точная мана или ярость.",11,"#B7A88E"));
            int current=overrides.TryGetValue(setting.Id,out var saved)?saved:setting.Default;
            void SaveSetting(int newValue)
            {
                if(externalActive)return;
                var updated=new System.Collections.Generic.Dictionary<string,int>(overrides);
                if(newValue==settingLocal.Default)updated.Remove(settingLocal.Id);
                else updated[settingLocal.Id]=newValue;
                try
                {
                    RotationSettingsStore.Save(settingsFile,profile,updated);
                    overrides=updated;
                    RuntimeDiagnostics.Add("XML2","Setting saved: "+settingLocal.Id+" (local override)");
                }
                catch(Exception ex)
                {
                    RuntimeDiagnostics.Add("XML2","Setting save failed: "+ex.GetType().Name);
                    ShowSpec(cls,spec,mode,tier,changedOnly);
                }
            }
            if(setting.Type==RotationSettingType.Boolean)
            {
                var toggle=new CheckBox {Content="Enabled",IsChecked=current==1,
                    IsEnabled=!externalActive,Foreground=Palette.Brush("#EAF8FF")};
                toggle.IsCheckedChanged+=(_,_)=>SaveSetting(toggle.IsChecked==true?1:0);
                pane.Children.Add(toggle);
            }
            else
            {
                var slider=new Slider {Minimum=setting.Min,Maximum=setting.Max,
                    TickFrequency=setting.Step,IsSnapToTickEnabled=true,
                    Value=current,IsEnabled=!externalActive,Width=300,
                    HorizontalAlignment=HAlign.Left};
                var valueText=Text(current.ToString()+" "+setting.Unit,13,"#42E4F3");
                slider.ValueChanged+=(_,_)=>{
                    int proposed=(int)Math.Round(slider.Value);
                    valueText.Text=proposed+" "+setting.Unit;
                    SaveSetting(proposed);
                };
                pane.Children.Add(slider);pane.Children.Add(valueText);
            }
            body.Children.Add(Pane(pane));
        }
        if(shown==0)
            body.Children.Add(Text(changedOnly?"No modified settings in this category.":"No parameters in this category.",13,"#9EC3D9"));
        Go(Page(spec.Name.ToUpperInvariant(),mode+" · XML-driven settings · experimental",body,
            cls.Name,()=>ShowClass(cls)));
    }
    private void ShowRotationResetConfirmation(GameClass cls,Specialization spec,
        RotationProfileV2 profile,string settingsFile,string mode,string tier)
    {
        var dialog=new Window {Title="Reset XML settings?",Width=420,Height=190,
            WindowStartupLocation=WindowStartupLocation.CenterOwner,CanResize=false,
            Background=Palette.Surface,Foreground=Palette.White};
        var contents=Stack(spacing:15);contents.Margin=new Thickness(22);
        contents.Children.Add(Text("Reset all "+mode+" overrides for "+spec.Name+"?",15,"#FFFFFF"));
        contents.Children.Add(Text("A backup of the previous values is retained.",12,"#98BED1"));
        var controls=Stack(Orientation.Horizontal,12);
        controls.Children.Add(Action("Cancel",dialog.Close));
        controls.Children.Add(Action("Reset defaults",()=>{
            try { RotationSettingsStore.Reset(settingsFile,profile); }
            catch(Exception ex) {RuntimeDiagnostics.Add("XML2","Reset failed: "+ex.GetType().Name);}
            dialog.Close();ShowSpec(cls,spec,mode,tier);
        },true));
        contents.Children.Add(controls);
        dialog.Content=contents;dialog.ShowDialog(this);
    }
    private void ShowCommon()
    {
        view="common";
        var all=Stack(spacing:16);
        all.Children.Add(Text("Shared settings are planned per client, with independent PvE and PvP preferences.",13,"#CDB29C"));
        foreach(var group in new [] { ("RACIAL ABILITIES",new[]{"Offensive racials","Defensive racials","Racial interrupts","Racial utility"}),
                          ("CONSUMABLES",new[]{"Healing potions","Mana potions","Battle potions","Healthstone"}),
                          ("TRINKETS & ENGINEERING",new[]{"On-use trinkets","Engineering abilities"}) })
        {
            var entries=Stack(spacing:12);
            entries.Children.Add(Text(group.Item1,15,"#45E5F7",FontWeight.Bold));
            foreach(var label in group.Item2)
            {
                var row=new Grid { ColumnDefinitions=new ColumnDefinitions("*,Auto,Auto"),ColumnSpacing=20 };
                row.Children.Add(Text(label,14,"#EAF9FF"));
                var pve=Text("PvE · not configured",12,"#87A7BA");Grid.SetColumn(pve,1);row.Children.Add(pve);
                var pvp=Text("PvP · not configured",12,"#87A7BA");Grid.SetColumn(pvp,2);row.Children.Add(pvp);
                entries.Children.Add(row);
            }
            all.Children.Add(Pane(entries));
        }
        Go(Page("RACIALS & CONSUMABLES","Global Forever settings · UI prepared, no automation is active",all));
    }
    private void ShowSupport()
    {
        view="support";
        var b=Stack(spacing:12);
        b.Children.Add(Text("SUPPORT",15,"#45E5F7",FontWeight.Bold));
        b.Children.Add(Text("LIVE RGB & APPLICATION DIAGNOSTICS",18,"#F1FAFF",FontWeight.Bold));
        b.Children.Add(Text("GAMESTATE v1 · verified RGB fields only · UNKNOWN does not authorize casts",12,"#85DDEE"));
        rgbHealthText=Text(rgbMonitor.Summary(),12,"#72D9F3");
        b.Children.Add(rgbHealthText);
        b.Children.Add(Text("Rotation source: AwaitingTransport — source RGB/SRC not installed; no external provider confirmed.",12,"#E5B778"));
        b.Children.Add(Text("RGB transport: v2 identity, v3 CRC, Curve, LGD, LGC; sequence/age, recovery, capture performance. Read-only.",11,"#99BCCC"));
        b.Children.Add(Text(ForeverGameStateBridge.Diagnostic(latestGameState),12,"#C5E1EF"));
        b.Children.Add(Text("In-memory only · No screenshots, character names, keys or credentials are logged.",12,"#99BCCC"));
        var actions=Stack(Orientation.Horizontal,9);
        actions.Children.Add(Action("Clear events",()=>{
            RuntimeDiagnostics.Clear();rgbMonitor.Reset();lastRgbHealthSignature="";
            RefreshDiagnosticsView();
        }));
        actions.Children.Add(Action("Copy RGB report",async ()=>{
            var clipboard=TopLevel.GetTopLevel(this)?.Clipboard;
            if(clipboard is not null)
                await clipboard.SetTextAsync(rgbMonitor.ExportJson());
        }));
        actions.Children.Add(Action("Save RGB report",()=>{
            try
            {
                string folder=Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "LazyG","diagnostics");
                Directory.CreateDirectory(folder);
                string filename="RGB-"+DateTime.UtcNow.ToString("yyyyMMdd-HHmmss-fff")+".json";
                File.WriteAllText(Path.Combine(folder,filename),rgbMonitor.ExportJson());
                RuntimeDiagnostics.Add("RGBMON",
                    "Saved private report to %LOCALAPPDATA%\\LazyG\\diagnostics\\"+filename);
            }
            catch(Exception ex)
            {
                RuntimeDiagnostics.Add("RGBMON","Report save failed: "+ex.GetType().Name);
            }
            RefreshDiagnosticsView();
        }));
        actions.Children.Add(Action("Create support ZIP",()=>{
            try
            {
                string folder=Path.Combine(Environment.GetFolderPath(
                    Environment.SpecialFolder.LocalApplicationData),"LazyG","reports");
                var source=sourceManager.Snapshot(DateTimeOffset.UtcNow);
                var safe=new RotationSupportArchive.SafeState("0.4.0-dev",
                    source.Confirmed?.ToString(),source.Health.ToString(),source.Reason,
                    "forever",null,rgbMonitor.V3.Lost,rgbMonitor.V3.Frozen,0,0);
                string file=RotationSupportArchive.Create(folder,safe,"ManualSupport");
                RuntimeDiagnostics.Add("SUPPORT","Local support ZIP created: "+
                    Path.GetFileName(file)+" (review before sharing; no auto upload)");
            }
            catch(Exception ex)
            {
                RuntimeDiagnostics.Add("SUPPORT","ZIP creation failed: "+ex.GetType().Name);
            }
            RefreshDiagnosticsView(force:true);
        }));
        actions.Children.Add(Action(hunterAuditRecording?"Stop Hunter audit":"Start Hunter BM audit",()=>{
            if(hunterAuditRecording)
            {
                hunterAuditRecording=false;
                RuntimeDiagnostics.Add("HUNTERAUDIT","Recording stopped; "+hunterAudit.Summary());
            }
            else
            {
                try
                {
                    hunterAuditProfile=RotationProfileCatalog.Load("hunter","beast-mastery","PvE");
                    if(hunterAuditProfile is null)throw new InvalidDataException("No BM PvE XML");
                    var path=Path.Combine(Environment.GetFolderPath(
                        Environment.SpecialFolder.LocalApplicationData),"LazyG","rotations",
                        "forever-hunter-beast-mastery-pve.json");
                    hunterAuditSettings=RotationSettingsStore.Load(path,hunterAuditProfile);
                    hunterAudit.Clear();
                    lastHunterAuditSample=default;
                    lastCastEventSequence=null;
                    lastCastEventSpellId=0;
                    hunterAuditRecording=true;
                    RuntimeDiagnostics.Add("HUNTERAUDIT",
                        "Started XML snapshot comparison; cast success UNOBSERVABLE with current RGB; keys never sent");
                }
                catch(Exception ex) {RuntimeDiagnostics.Add("HUNTERAUDIT",
                    "Could not start: "+ex.GetType().Name);}
            }
            ShowSupport();
        }));
        actions.Children.Add(Action("Save Hunter audit JSON",()=>{
            try
            {
                string folder=Path.Combine(Environment.GetFolderPath(
                    Environment.SpecialFolder.LocalApplicationData),"LazyG","diagnostics");
                Directory.CreateDirectory(folder);
                string file="HunterBM-Audit-"+DateTime.UtcNow.ToString("yyyyMMdd-HHmmss-fff")+".json";
                File.WriteAllText(Path.Combine(folder,file),hunterAudit.ExportJson());
                RuntimeDiagnostics.Add("HUNTERAUDIT","Saved local bounded XML audit: "+file+
                    " (no raw RGB, names, input or cast claims)");
            }
            catch(Exception ex){RuntimeDiagnostics.Add("HUNTERAUDIT",
                "Save failed: "+ex.GetType().Name);}
            RefreshDiagnosticsView(force:true);
        }));
        b.Children.Add(Text("HUNTER BM DEV · Experimental F-key execution (not yet game-tested)",13,"#E9B26D",FontWeight.Bold));
        b.Children.Add(Text("Map only F1..F12 keys that you bound to the matching spell ranks in WoW. No defaults. Disabled until explicit ARM. Does not bypass Unknown GCD, target, debuffs or ranks. DISARM before typing/chatting.",11,"#E9B26D"));
        var keyInputs=new System.Collections.Generic.Dictionary<int,TextBox>();
        var keyRow=Stack(Orientation.Horizontal,9);
        foreach(var pair in new[] {(1130,"Mark"),(1978,"Sting"),(3044,"Arcane"),(75,"Auto")})
        {
            keyRow.Children.Add(Text(pair.Item2,12,"#AACCDD"));
            var keyInput=new TextBox {
                Width=64,Watermark="F1-F12",
                Text=hunterExecutionKeys.TryGetValue(pair.Item1,out int previous) ?
                    "F"+(previous-0x70+1) : ""
            };
            keyInputs[pair.Item1]=keyInput;
            keyRow.Children.Add(keyInput);
        }
        b.Children.Add(keyRow);
        actions.Children.Add(Action(hunterExecutionArmed?"DISARM Hunter keys":"ARM Hunter F-keys",()=>{
            if(hunterExecutionArmed)
            {
                hunterExecutionArmed=false;
                RuntimeDiagnostics.Add("HUNTEREXEC","Manually DISARMED");
            }
            else
            {
                var chosen=new System.Collections.Generic.Dictionary<int,int>();
                bool valid=true;
                foreach(var id in new[] {1130,1978,3044,75})
                {
                    string value=(keyInputs[id].Text??"").Trim().ToUpperInvariant();
                    if(value.Length<2 || value[0]!='F' ||
                       !int.TryParse(value.Substring(1),out int number) ||
                       number is <1 or >12){valid=false;break;}
                    chosen[id]=0x6F+number;
                }
                if(!valid || chosen.Values.Distinct().Count()!=4)
                    RuntimeDiagnostics.Add("HUNTEREXEC","NOT ARMED: four distinct F1..F12 bindings required");
                else
                {
                    hunterExecutionKeys.Clear();
                    foreach(var item in chosen)hunterExecutionKeys[item.Key]=item.Value;
                    hunterLastKeyAt=default;
                    hunterLastAutoShotEpoch=null;
                    hunterKeyAttempts=hunterKeySubmitted=0;
                    hunterExecutionArmed=true;
                    RuntimeDiagnostics.Add("HUNTEREXEC","ARMED: strict evidence-only Hunter BM pilot. No keys on Unknown values.");
                }
            }
            ShowSupport();
        }));
        actions.Children.Add(Action("Emergency DISARM",()=>{
            hunterExecutionArmed=false;
            RuntimeDiagnostics.Add("HUNTEREXEC","Emergency DISARM");
            ShowSupport();
        }));
        b.Children.Add(Text("Execution attempt/submitted: "+hunterKeyAttempts+"/"+hunterKeySubmitted+
            " · "+(hunterExecutionArmed?"ARMED":"DISARMED")+
            ". Key submission is not proof of spell execution.",11,"#B7A88E"));
        b.Children.Add(Text("Hunter BM: /lgprobe audit on (in WoW) enables optional LGE player spellcast event strip. Start Hunter BM audit enables Windows comparison; an event is NOT proof of hit/effect or LazyG input.",11,"#E9B26D"));
        hunterAuditSummaryText=Text(hunterAudit.Summary(),12,"#72D9F3");
        b.Children.Add(hunterAuditSummaryText);
        actions.Children.Add(Action("Full RGB diagnostics ON/OFF",()=>{
            fullRgbDiagnosticMode=!fullRgbDiagnosticMode;
            spellDiagnosticEnabled=fullRgbDiagnosticMode;
            cooldownDiagnosticEnabled=fullRgbDiagnosticMode;
            lastSpellPacket=null;lastSpellSequence=null;lastSpellDiagnostic="";
            cooldownObserver.Reset();lastCooldownDiagnostic="";
            rgbMonitor.Reset();lastRgbHealthSignature="";
            RuntimeDiagnostics.Add("RGBMON",fullRgbDiagnosticMode
                ?"Full RGB receive diagnostics ON; use /lgprobe diag 13795 in WoW"
                :"Optional LGD/LGC receive diagnostics OFF; base v2/v3/Curve still monitored");
            RefreshDiagnosticsView();
        }));
        actions.Children.Add(Action("Refresh",()=>RefreshDiagnosticsView(force:true)));
        actions.Children.Add(Action("Copy all",async ()=>{
            var clipboard=TopLevel.GetTopLevel(this)?.Clipboard;
            if(clipboard is not null)
                await clipboard.SetTextAsync(RuntimeDiagnostics.Snapshot());
        }));
        actions.Children.Add(Action("XML preview ON/OFF",()=>{
            xmlPreviewEnabled=!xmlPreviewEnabled;
            lastXmlPreview="";
            if(xmlPreviewEnabled)
            {
                try
                {
                    using var stream=typeof(MainWindow).Assembly.GetManifestResourceStream(
                        "LazyG.ForeverXmlDiagnosticExample");
                    if(stream is null)throw new InvalidDataException("Embedded XML missing");
                    using var reader=new StreamReader(stream);
                    xmlPreviewProfile=XmlRotationDispatcher.Parse(reader.ReadToEnd());
                    RuntimeDiagnostics.Add("XML","Read-only Forever preview enabled (example only, NO INPUT)");
                }
                catch(Exception ex)
                {
                    xmlPreviewEnabled=false;
                    xmlPreviewProfile=null;
                    RuntimeDiagnostics.Add("XML","Preview unavailable: "+ex.GetType().Name);
                }
            }
            else
            {
                xmlPreviewProfile=null;
                RuntimeDiagnostics.Add("XML","Preview disabled");
            }
            RefreshDiagnosticsView();
        }));
        actions.Children.Add(Action("LGD SpellProbe ON/OFF",()=>{
            spellDiagnosticEnabled=!spellDiagnosticEnabled;
            lastSpellPacket=null;lastSpellSequence=null;
            lastSpellDiagnostic="";
            RuntimeDiagnostics.Add("LGD",spellDiagnosticEnabled
                ?"Opt-in capture enabled; use /lgprobe rgb on in WoW"
                :"Capture disabled");
            RefreshDiagnosticsView();
        }));
        actions.Children.Add(Action("LGC Cooldown RGB ON/OFF",()=>{
            cooldownDiagnosticEnabled=!cooldownDiagnosticEnabled;
            cooldownObserver.Reset();
            lastCooldownDiagnostic="";
            RuntimeDiagnostics.Add("LGC",cooldownDiagnosticEnabled
                ?"Read-only capture enabled; use /lgprobe cdstrip 13795 in WoW"
                :"Capture disabled");
            RefreshDiagnosticsView();
        }));
        b.Children.Add(actions);
        diagnosticsOutput=new TextBox {
            Text=RuntimeDiagnostics.Snapshot(),
            IsReadOnly=true,
            AcceptsReturn=true,
            TextWrapping=TextWrapping.NoWrap,
            FontFamily=new Avalonia.Media.FontFamily("Consolas"),
            FontSize=12,
            Foreground=Palette.Brush("#C5E1EF"),
            Background=Palette.Brush("#041624"),
            BorderThickness=new Thickness(0),
            Height=440
        };
        b.Children.Add(Pane(diagnosticsOutput,"#041624",8,"#275B78",new Thickness(12)));
        b.Children.Add(Text("Select lines with the mouse, Ctrl+C to copy. Live refresh pauses while the log has keyboard focus; Refresh updates it manually.",12,"#99BCCC"));
        b.Children.Add(Text("RGB v2 / v3 CRC / Curve, window visibility, Setup and Overlay events appear here. Automatic rotation is not implemented.",12,"#99BCCC"));
        Go(Page("SUPPORT","Local live status and event history",Pane(b)));
        RefreshDiagnosticsView();
    }
    private void RefreshDiagnosticsView(bool force=false)
    {
        if(view!="support" || diagnosticsOutput is null)return;
        // Replacing Text clears its selection. Keep the visible text stable
        // while the user is selecting/copying, even though events accumulate.
        if(!force && diagnosticsOutput.IsFocused)return;
        var snapshot=RuntimeDiagnostics.Snapshot();
        if(diagnosticsOutput.Text!=snapshot)
            diagnosticsOutput.Text=snapshot;
    }
    private void RequestStart(GameClass cls, Specialization spec)
    {
        RuntimeDiagnostics.Add("ROTATION", $"Start requested: {cls.Name} / {spec.Name}; XML rotation engine is not installed");
        RefreshDiagnosticsView();
        var notice=new Window {
            Title="LazyG · Start",
            Width=430,Height=175,CanResize=false,
            WindowStartupLocation=WindowStartupLocation.CenterOwner,
            Background=Palette.Surface,Foreground=Palette.White
        };
        var content=Stack(spacing:15);
        content.Margin=new Thickness(24);
        content.Children.Add(Text("ROTATION NOT AVAILABLE",17,"#4BE2F4",FontWeight.Bold));
        content.Children.Add(Text("The Start control is reserved for running your selected XML rotation. No rotation engine is implemented in this dev build.",13));
        content.Children.Add(Action("OK",notice.Close,true));
        notice.Content=content;
        notice.ShowDialog(this);
    }
    private void ToggleOverlay()
    {
        if (overlay is not null)
        {
            var toClose=overlay;
            overlay=null;
            toClose.Close();
            if(overlayButton is not null)overlayButton.Content="Overlay OFF";
            RuntimeDiagnostics.Add("OVERLAY","Closed");
            return;
        }
        var previewClass=client.Classes.FirstOrDefault(c=>c.Id==session.LastClass)?.Name ?? "Hunter";
        overlay=new OverlayWindow(()=>{
            var current=overlay;overlay=null;current?.Close();
            if(overlayButton is not null)overlayButton.Content="Overlay OFF";
            RuntimeDiagnostics.Add("OVERLAY","Closed by user");
        },previewClass);
        overlay.Closed+=(_,_)=> {
            overlay=null;
            if(overlayButton is not null)overlayButton.Content="Overlay OFF";
        };
        overlay.Show();
        if(overlayButton is not null)overlayButton.Content="Overlay ON";
        RuntimeDiagnostics.Add("OVERLAY",$"Shown · icon preview class {previewClass} · {ForeverSpellCatalog.Count} Forever spell records");
    }
    private void ShowSetup()
    {
        if(setupOpen || finished)return;
        setupOpen=true;
        RuntimeDiagnostics.Add("SETUP","Opened; main window hidden");
        var dialog=new SetupDialog(session);
        // The main window is hidden for the *entire* Setup session.
        dialog.WindowStartupLocation=WindowStartupLocation.CenterScreen;
        dialog.Closed+=(_,_)=>{
            setupOpen=false;
            if(dialog.SetupCompleted)
            {
                clientText.Text="WOW FOREVER";
                ShowClasses();
                RuntimeDiagnostics.Add("SETUP","Finished · Forever client active");
            }
            else RuntimeDiagnostics.Add("SETUP","Closed without completing RGB setup");
            if(!finished){Show();Activate();}
        };
        dialog.Show();
        Hide();
    }
    private async Task PollBridgeAsync()
    {
        if (scanning || finished || setupOpen) return;
        scanning=true;
        try
        {
            var result=await Task.Run(() => {
                var stopwatch=System.Diagnostics.Stopwatch.StartNew();
                bool ok=WowRgbBridge.TryReadCombined(out var state,out var packet,
                    out var detail,out var v3,out var thresholds,
                    spellDiagnosticEnabled,out var spell,
                    cooldownDiagnosticEnabled,out var cooldown,
                    hunterAuditRecording,out var castEvent);
                stopwatch.Stop();
                return (ok,state,packet,detail,v3,thresholds,spell,cooldown,castEvent,
                    capturedAt:DateTimeOffset.UtcNow,
                    captureMs:stopwatch.Elapsed.TotalMilliseconds);
            });
            if(finished)return;
            var connected=result.ok && result.state is not null;
            var crc=result.packet is not null;
            var curve=result.thresholds is not null;
            bool foreground=!result.detail.StartsWith("Switch to WoW",StringComparison.Ordinal) &&
                !result.detail.StartsWith("WoW window not found",StringComparison.Ordinal) &&
                !result.detail.StartsWith("Cannot",StringComparison.Ordinal) &&
                !result.detail.StartsWith("RGB screen capture failed",StringComparison.Ordinal);
            string reason=connected?"OK":!foreground?"WindowOrCaptureUnavailable":"BaseV2NotFound";
            rgbMonitor.Accept(new RgbSample(
                result.capturedAt,result.captureMs,foreground,connected,
                crc,result.packet?.FrameCounter,curve,
                spellDiagnosticEnabled,result.spell is not null,result.spell?.Sequence,
                cooldownDiagnosticEnabled,result.cooldown is not null,result.cooldown?.Sequence,
                reason));
            rgbMonitor.SetDecoded(connected ? new RgbDecodedView(
                result.state?.ClassId,result.state?.RaceId,
                result.state?.Level,result.state?.SpecIndex,result.state?.CombatFlags,
                result.packet?.ProfileHash,result.packet?.PlayerHealth,
                result.packet?.TargetHealth,result.packet?.PlayerPower,
                result.packet?.CombatFlags,result.packet?.TargetFlags,
                result.thresholds?.PlayerHp,result.thresholds?.TargetHp,
                result.thresholds?.Resource,
                result.spell?.SpellId,result.spell?.Learned.ToString(),
                result.spell?.Usable.ToString(),result.spell?.CooldownActive.ToString(),
                result.spell?.GcdActive.ToString(),
                result.cooldown?.SpellId,result.cooldown?.SpellActive.ToString(),
                result.cooldown?.SpellOnGcd.ToString(),
                result.cooldown?.Gcd29515Active.ToString(),
                result.cooldown?.Gcd29515OnGcd.ToString()) : null);
            var rgbHealth=rgbMonitor.Summary();
            if(rgbHealthText is not null)rgbHealthText.Text=rgbHealth;
            // Suppress per-frame event spam while preserving transitions and counters.
            var signature=rgbHealth.Split(" frames=")[0]+
                " recoveries="+rgbMonitor.LGC.Recovered+
                " stale="+rgbMonitor.LGC.Frozen;
            if(signature!=lastRgbHealthSignature)
            {
                RuntimeDiagnostics.Add("RGBMON",rgbHealth);
                lastRgbHealthSignature=signature;
            }
            string now=connected?(curve?"RGB CONNECTED · CURVE":crc?"RGB CONNECTED · CRC PASS":"RGB CONNECTED"):"GAME NOT CONNECTED";
            statusText.Text=now;
            if(now != lastBridgeState)
            {
                RuntimeDiagnostics.Add("RGB",now+(connected?"":(" · "+result.detail)));
                lastBridgeState=now;
            }
            string probe=connected?(crc?"RGB v3 CRC PASS":result.v3)+
                (curve?" · "+result.thresholds:" · Curve unavailable"):"No live game data";
            if(probe!=lastProbeState)
            {
                RuntimeDiagnostics.Add("PROBE",probe);
                lastProbeState=probe;
            }
            // Safe initial engine snapshot: ONLY v2-confirmed fields; future signals remain Unknown.
            latestGameState=ForeverGameStateBridge.FromRgb(connected?result.state:null,crc,
                result.capturedAt, crc && (result.packet!.TargetFlags & 4)!=0);
            // Curve is an independent, coarse 5% band, never exact mana/rage.
            if(connected && curve && HealthBand.TryParse(result.thresholds!.Resource,
                out var resourceBand))
                latestGameState=latestGameState with {
                    PowerBand=Observed<HealthBand>.Known(resourceBand,result.capturedAt)
                };
            if(spellDiagnosticEnabled && connected && result.spell is not null)
            {
                if(lastSpellSequence!=result.spell.Sequence || lastSpellPacket?.SpellId!=result.spell.SpellId)
                {
                    lastSpellPacket=result.spell;
                    lastSpellSequence=result.spell.Sequence;
                    lastSpellPacketAt=result.capturedAt;
                }
            }
            if(spellDiagnosticEnabled && connected && lastSpellPacket is not null &&
               result.capturedAt-lastSpellPacketAt<=TimeSpan.FromSeconds(1.5))
            {
                latestGameState=ForeverSpellProbeCodec.ApplyDiagnostic(latestGameState,
                    lastSpellPacket,lastSpellPacketAt,result.capturedAt,TimeSpan.FromSeconds(1.5));
            }
            string lgdStatus=!spellDiagnosticEnabled?"OFF":!connected?"No RGB v2 identity":
                lastSpellPacket is null?"LGD strip not found":
                result.capturedAt-lastSpellPacketAt>TimeSpan.FromSeconds(1.5)?"STALE (frozen or absent)":
                "SpellID "+lastSpellPacket.SpellId+" learned="+lastSpellPacket.Learned+
                " usable="+lastSpellPacket.Usable+" cooldownActive="+lastSpellPacket.CooldownActive+
                " gcdActive="+lastSpellPacket.GcdActive+" · remaining/GCD time Unknown";
            if(lgdStatus!=lastSpellDiagnostic)
            {
                RuntimeDiagnostics.Add("LGD",lgdStatus);
                lastSpellDiagnostic=lgdStatus;
            }
            // Read-only, independent boolean observation. Never writes to
            // latestGameState GCD/CD-millisecond authorization fields.
            if(cooldownDiagnosticEnabled)
                cooldownObserver.Update(connected &&
                    latestGameState.Transport==Knowledge.Known &&
                    latestGameState.ClassId.Quality==Knowledge.Known,
                    result.cooldown,result.capturedAt);
            else cooldownObserver.Reset();
            string cooldownStatus=!cooldownDiagnosticEnabled?"OFF":
                cooldownObserver.Describe();
            if(cooldownStatus!=lastCooldownDiagnostic)
            {
                RuntimeDiagnostics.Add("LGC",cooldownStatus);
                lastCooldownDiagnostic=cooldownStatus;
            }
            if(xmlPreviewEnabled && xmlPreviewProfile is not null)
            {
                // The sample's Curve band comes from the SAME captured bitmap,
                // never from a previous target. It does not imply target alive.
                var hpBand=Observed<HealthBand>.Missing();
                if(connected && curve && HealthBand.TryParse(result.thresholds!.TargetHp,
                    out var parsedBand))
                    hpBand=Observed<HealthBand>.Known(parsedBand,result.capturedAt);
                string preview=XmlRotationPreview.Describe(xmlPreviewProfile,latestGameState,
                    hpBand,result.capturedAt);
                if(preview!=lastXmlPreview)
                {
                    RuntimeDiagnostics.Add("XML",preview);
                    lastXmlPreview=preview;
                }
            }
            // Opt-in dev pilot, entirely separate from read-only Hunter audit.
            // Foreground is rechecked natively by the sender, and UNKNOWN
            // input predicates never become True.
            if(hunterExecutionArmed && !connected)
            {
                hunterExecutionArmed=false;
                RuntimeDiagnostics.Add("HUNTEREXEC","Auto DISARM: RGB identity unavailable");
            }
            if(hunterExecutionArmed && connected &&
               (hunterLastKeyAt==default ||
                result.capturedAt-hunterLastKeyAt>=TimeSpan.FromMilliseconds(1700)))
            {
                try
                {
                    var executeProfile=hunterAuditProfile ??
                        RotationProfileCatalog.Load("hunter","beast-mastery","PvE");
                    var plan=HunterExecutionGate.Decide(executeProfile,latestGameState,
                        hunterAuditSettings,hunterExecutionKeys,true,foreground,
                        result.capturedAt);
                    if(plan is not null)
                    {
                        int epoch=latestGameState.TargetEpoch.Value??-1;
                        // Auto Shot is a toggle; never send it twice for the
                        // same target epoch from this pilot.
                        if(plan.BaseSpellId!=75 || hunterLastAutoShotEpoch!=epoch)
                        {
                            hunterKeyAttempts++;
                            bool sent=WowRgbBridge.TrySendBoundFKey(plan.VirtualKey);
                            hunterLastKeyAt=result.capturedAt;
                            if(sent)
                            {
                                hunterKeySubmitted++;
                                if(plan.BaseSpellId==75)hunterLastAutoShotEpoch=epoch;
                            }
                            RuntimeDiagnostics.Add("HUNTEREXEC",
                                "F-key "+(plan.VirtualKey-0x6F)+" base="+plan.BaseSpellId+
                                " learned="+plan.LearnedSpellId+" submitted="+sent+
                                "; game effect unverified");
                        }
                    }
                }
                catch(Exception ex)
                {
                    hunterExecutionArmed=false;
                    RuntimeDiagnostics.Add("HUNTEREXEC","DISARM after exception: "+ex.GetType().Name);
                }
            }
            if(hunterAuditRecording && hunterAuditProfile is not null &&
                (lastHunterAuditSample==default ||
                 result.capturedAt-lastHunterAuditSample>=TimeSpan.FromMilliseconds(400)))
            {
                // Record a bounded, read-only evaluation even when the game state is
                // incomplete. Never convert an LGD/LGC change into a cast event.
                hunterAudit.Capture(hunterAuditProfile,latestGameState,
                    hunterAuditSettings,result.capturedAt);
                lastHunterAuditSample=result.capturedAt;
                if(hunterAuditSummaryText is not null)
                    hunterAuditSummaryText.Text=hunterAudit.Summary();
                if(hunterAudit.Rows.Count%20==0)
                    RuntimeDiagnostics.Add("HUNTERAUDIT",hunterAudit.Summary());
            }
            if(hunterAuditRecording && !connected && lastCastEventSequence is not null)
            {
                // Sequence after a reconnect cannot be compared to a previous
                // process/session epoch. Re-establish baseline, never replay.
                lastCastEventSequence=null;
                lastCastEventSpellId=0;
                RuntimeDiagnostics.Add("HUNTERAUDIT","LGE disconnected; event baseline invalidated");
            }
            if(hunterAuditRecording && connected && result.castEvent is not null)
            {
                var cast=result.castEvent;
                if(lastCastEventSequence is null)
                {
                    // Baseline a potentially old/latched event. First frame is
                    // not evidence that the cast happened after recording began.
                    lastCastEventSequence=cast.Sequence;
                    lastCastEventSpellId=cast.SpellId;
                    RuntimeDiagnostics.Add("HUNTERAUDIT","LGE event baseline established; historical event ignored");
                }
                else if(cast.PlayerEvent)
                {
                    // Unchanged latched event means a repeated RGB frame, NOT
                    // a second cast. Track separately for transport diagnostics.
                    hunterAudit.RecordDuplicateEvent();
                }
                else if(cast.Sequence!=lastCastEventSequence || cast.SpellId!=lastCastEventSpellId)
                {
                    lastCastEventSequence=cast.Sequence;
                    lastCastEventSpellId=cast.SpellId;
                    var correlated=hunterAudit.Observe(new RotationObservedCast(cast.SpellId,
                        result.capturedAt,RotationCastEvidence.UnitSpellcastSucceeded,
                        cast.TargetEpoch,cast.PlayerEvent));
                    if(correlated is null)hunterAudit.RecordUncorrelatedEvent();
                    RuntimeDiagnostics.Add("HUNTERAUDIT",correlated is null
                        ?"LGE player event observed but no eligible XML frame (not matched)"
                        :"LGE player event "+cast.SpellId+" · "+correlated.Reason);
                    if(hunterAuditSummaryText is not null)
                        hunterAuditSummaryText.Text=hunterAudit.Summary();
                }
            }
            var engineDiagnostic=ForeverGameStateBridge.Diagnostic(latestGameState);
            if(engineDiagnostic!=lastGameStateDiagnostic)
            {
                RuntimeDiagnostics.Add("GAMESTATE",engineDiagnostic);
                lastGameStateDiagnostic=engineDiagnostic;
            }
            overlay?.SetConnection(connected,crc,curve,connected && result.state?.InCombat == true,
                result.state?.ClassName, result.state?.SpecName);
            RefreshDiagnosticsView();
        }
        catch(Exception e)
        {
            statusText.Text="RGB CAPTURE ERROR";
            cooldownObserver.Reset();
            rgbMonitor.Accept(new RgbSample(DateTimeOffset.UtcNow,0,false,
                false,false,null,false,
                spellDiagnosticEnabled,false,null,
                cooldownDiagnosticEnabled,false,null,"Exception"));
            rgbMonitor.SetDecoded(null);
            if(rgbHealthText is not null)rgbHealthText.Text=rgbMonitor.Summary();
            if(lastBridgeState!="RGB CAPTURE ERROR")
                RuntimeDiagnostics.Add("ERROR","RGB capture: "+e.GetType().Name);
            lastBridgeState="RGB CAPTURE ERROR";
        }
        finally{scanning=false;}
    }
}
