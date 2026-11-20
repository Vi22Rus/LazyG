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
    private readonly RotationPreviewSession rotationPreview=new();
    private readonly GHubDriver ghub=new();
    private readonly RotationCommandGate commandGate=new();
    private readonly DebuffConfirmationGate debuffConfirmation=new();
    private DebuffConfirmationState lastDebuffState=DebuffConfirmationState.Idle;
    private readonly RotationExecutionTrace executionTrace=new();
    private readonly AutoBindingRegistry autoBindings=new();
    private System.Collections.Generic.IReadOnlyDictionary<int,string> activeBindings=
        new System.Collections.Generic.Dictionary<int,string>();
    private bool ghubArmed;
    private bool ghubBusy;
    private long ghubGeneration;
    private string LastGhubStatus="STOPPED";
    private string lastPreviewStatus="";
    private int? lastPreviewSpell;
    private string lastInputGateReason="";
    private int lastAutoBindingCount=-1;
    private readonly ProfileDataManifest? hunterCompactManifest;
    private byte? lastCompactFrame;
    private DateTimeOffset lastCompactFrameAt;
    private bool compactSequenceEstablished;
    private string lastCompactDiagnostic="";
    private TextBlock? hunterAuditSummaryText;
    private bool hunterAuditRecording;
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
        try
        {
            var bm=RotationProfileCatalog.Load("hunter","beast-mastery","PvE");
            if(bm is not null)hunterCompactManifest=ProfileDataManifestBuilder.Build(bm);
        }
        catch(Exception ex) {RuntimeDiagnostics.Add("COMPACT","Profile rejected: "+ex.GetType().Name);}
        Content = CreateShell();
        ShowClasses();
        timer.Tick += async (_, _) => await PollBridgeAsync();
        timer.Start();
        Closed += (_, _) => { finished = true; StopGhub("WINDOW CLOSED"); rotationPreview.Stop("WINDOW CLOSED"); timer.Stop(); overlay?.Close(); };
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
            var b=Action(rotationPreview.Running?"Stop":"Start",
                ()=>RequestStart(selection,lastSpec),true);b.VerticalAlignment=VerticalAlignment.Center;

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
        overlay?.SetClass(cls.Name);
        var body=Stack(spacing:17);
        var top=Stack(Orientation.Horizontal,16);top.Children.Add(SpellIcon(spec.Icon,76));
        var identity=Stack(spacing:5);
        identity.Children.Add(Text(spec.Name,25,"#FFFFFF",FontWeight.Bold));
        identity.Children.Add(Text(cls.Name+" · Forever · Internal XML (DEV; live input only for supported profiles)",12,cls.Accent));
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
            body.Children.Add(Action(rotationPreview.Running?"Stop":"Start",
                ()=>{RequestStart(cls,spec);ShowSpec(cls,spec,mode,tier,changedOnly);},true));
            body.Children.Add(Text("Start connects Logitech G HUB; Lua automatically reads the WoW action bar bindings through RGB v3. Only a fresh exact SpellID match can send a key. In-game validation required.",11,"#B7A88E"));
            body.Children.Add(Action("Hunter BM — открыть диагностику XML",ShowSupport));
            body.Children.Add(Text("Для теста: Start включает XML-аудит; Support сохраняет полный диагностический ZIP. Успешное нажатие Logitech не доказывает каст WoW.",11,"#B7A88E"));
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
        const string amber="#F9B72E", ivory="#FAEDE0", muted="#C0A999";
        var settingsSurface=Stack(spacing:12);
        var toolbar=Stack(Orientation.Horizontal,11);
        Button tab(string name,bool active,Action click)
        {
            var button=Action(name,click,active);
            button.Padding=new Thickness(17,8);
            button.Background=Palette.Brush(active?"#DA8E15":"#291D19");
            button.Foreground=Palette.Brush(active?"#21120D":"#E9D4BF");
            button.BorderBrush=Palette.Brush(active?"#FFCE5B":"#62442A");
            return button;
        }
        toolbar.Children.Add(tab("Essentials",tier=="Essentials",
            ()=>ShowSpec(cls,spec,mode,"Essentials",changedOnly)));
        toolbar.Children.Add(tab("Advanced",tier=="Advanced",
            ()=>ShowSpec(cls,spec,mode,"Advanced",changedOnly)));
        toolbar.Children.Add(tab(mode,mode=="PvE",
            ()=>ShowSpec(cls,spec,mode=="PvE"?"PvP":"PvE","Essentials")));
        toolbar.Children.Add(tab(changedOnly?"Changed only ✓ "+changes:"Changed only · "+changes,
            changedOnly,()=>ShowSpec(cls,spec,mode,tier,!changedOnly)));
        var reset=tab("Reset to defaults",false,()=>{
            if(!externalActive)
                ShowRotationResetConfirmation(cls,spec,profile,settingsFile,mode,tier);
        });
        reset.IsEnabled=!externalActive;
        toolbar.Children.Add(reset);
        settingsSurface.Children.Add(toolbar);
        var finder=new TextBox { Watermark="Filter settings…",Width=340,
            HorizontalAlignment=HAlign.Left,Background=Palette.Brush("#241A17"),
            Foreground=Palette.Brush(ivory),BorderBrush=Palette.Brush("#664933"),
            BorderThickness=new Thickness(1),CornerRadius=new CornerRadius(12),
            Padding=new Thickness(13,8) };
        settingsSurface.Children.Add(finder);
        settingsSurface.Children.Add(Text("PvE and PvP profiles store separate settings. Only the current XML profile is displayed.",
            11,muted));
        var renderedRows=new System.Collections.Generic.List<(Border Row,string SearchText)>();
        var orderedGroups=new[]{"Utility","Defensives","Cooldowns","Rotation","AoE","Resource"};
        var visibleSettings=profile.Settings.Values.Where(x=>x.Tier==tier &&
            (!changedOnly || (overrides.TryGetValue(x.Id,out var value) &&
                              value!=x.Default)))
            .OrderBy(x=>Array.IndexOf(orderedGroups,x.Group)<0?99:Array.IndexOf(orderedGroups,x.Group))
            .ThenBy(x=>x.Parent is null?0:1).ThenBy(x=>x.Id).ToArray();
        string[] sectionGroups=visibleSettings.Select(x=>x.Group).Distinct().ToArray();
        foreach(string group in sectionGroups)
        {
            settingsSurface.Children.Add(Text(group.ToUpperInvariant(),11,amber,FontWeight.Bold));
            foreach(var setting in visibleSettings.Where(x=>x.Group==group))
            {
                var current=overrides.TryGetValue(setting.Id,out var saved)?saved:setting.Default;
                var row=new Grid { ColumnDefinitions=new ColumnDefinitions("Auto,*,Auto"),
                    ColumnSpacing=13,Margin=new Thickness(setting.Parent is null?0:24,0,0,0),
                    MinHeight=58 };
                var icon=HunterSettingIcon(cls.Id,setting.IconSpellId,setting.LabelEn,setting.Parent is null?34:30);
                Grid.SetColumn(icon,0);row.Children.Add(icon);
                var labels=Stack(spacing:3);
                labels.Children.Add(Text(setting.LabelEn+" · "+setting.LabelRu,
                    13,ivory,FontWeight.SemiBold));
                string description=string.IsNullOrWhiteSpace(setting.DescriptionRu)
                    ? setting.DescriptionEn:setting.DescriptionRu;
                if(description.Length>0)
                    labels.Children.Add(Text(description,11,muted));
                if(setting.ExclusiveGroup is not null)
                    labels.Children.Add(Text("Общий кулдаун · "+setting.ExclusiveGroup+
                        " · включение отключит остальные способности группы",10,"#E0AE65"));
                if(setting.Type==RotationSettingType.Integer && setting.Unit=="percent")
                    labels.Children.Add(Text("Ресурс WoW Forever: только проверенные интервалы по 5%.",10,muted));
                Grid.SetColumn(labels,1);row.Children.Add(labels);
                void SaveSetting(int newValue)
                {
                    if(externalActive)return;
                    try
                    {
                        var updated=RotationSettingsExclusivity.Apply(
                            profile,overrides,setting.Id,newValue);
                        RotationSettingsStore.Save(settingsFile,profile,updated);
                        if(rotationPreview.Running)
                        {
                            StopGhub("SETTINGS CHANGED");
                            rotationPreview.Stop("SETTINGS CHANGED · RESTART PREVIEW");
                            overlay?.SetReadOnlyRecommendation(false,null,rotationPreview.Status);
                        }
                        overrides=new System.Collections.Generic.Dictionary<string,int>(updated);
                        RuntimeDiagnostics.Add("XML2","Setting saved: "+setting.Id+
                            (setting.ExclusiveGroup is null?"":" (exclusive "+setting.ExclusiveGroup+")"));
                        if(setting.Type==RotationSettingType.Boolean)
                            ShowSpec(cls,spec,mode,tier,changedOnly);
                    }
                    catch(Exception ex)
                    {
                        RuntimeDiagnostics.Add("XML2","Settings update rejected: "+ex.GetType().Name);
                        ShowSpec(cls,spec,mode,tier,changedOnly);
                    }
                }
                Control control;
                if(setting.Type==RotationSettingType.Boolean)
                {
                    var toggle=new ToggleSwitch {
                        IsChecked=current==1,IsEnabled=!externalActive,
                        OnContent="",OffContent="",Width=74,Height=36,
                        HorizontalAlignment=HAlign.Right };
                    toggle.IsCheckedChanged+=(_,_)=>SaveSetting(toggle.IsChecked==true?1:0);
                    control=toggle;
                }
                else
                {
                    var controlRow=Stack(Orientation.Horizontal,12);
                    var slider=new Slider {
                        Minimum=setting.Min,Maximum=setting.Max,
                        TickFrequency=setting.Step,IsSnapToTickEnabled=true,
                        Value=current,Width=155,
                        IsEnabled=!externalActive,
                        VerticalAlignment=VerticalAlignment.Center
                    };
                    var value=Text(current+(setting.Unit=="percent"?" %":" "+setting.Unit),13,amber,FontWeight.Bold);
                    value.Width=65;
                    value.TextAlignment=TextAlignment.Right;
                    slider.ValueChanged+=(_,_)=>{
                        int proposed=(int)Math.Round(slider.Value);
                        value.Text=proposed+(setting.Unit=="percent"?" %":" "+setting.Unit);
                        if(proposed!= (overrides.TryGetValue(setting.Id,out var previous)
                            ? previous:setting.Default))
                            SaveSetting(proposed);
                    };
                    controlRow.Children.Add(slider);controlRow.Children.Add(value);
                    control=controlRow;
                }
                Grid.SetColumn(control,2);row.Children.Add(control);
                var container=new Border {Child=row,Padding=new Thickness(10,9),
                    Background=Palette.Brush("#271A18"),CornerRadius=new CornerRadius(8),
                    BorderBrush=Palette.Brush("#483025"),
                    BorderThickness=new Thickness(0,0,0,1)};
                settingsSurface.Children.Add(container);
                renderedRows.Add((container,setting.LabelEn+" "+setting.LabelRu+" "+description+" "+setting.Group));
            }
        }
        finder.TextChanged+=(_,_)=>{
            string filter=finder.Text?.Trim()??"";
            foreach(var item in renderedRows)
                item.Row.IsVisible=filter.Length==0 ||
                    item.SearchText.Contains(filter,StringComparison.OrdinalIgnoreCase);
        };
        if(renderedRows.Count==0)
            settingsSurface.Children.Add(Text(changedOnly
                ?"No changed settings in this category.":"No XML settings in this category.",
                13,muted));
        body.Children.Add(Pane(settingsSurface,"#1D1514",14,"#64432F",new Thickness(19)));
        Go(Page(spec.Name.ToUpperInvariant(),mode+" · XML-driven settings · experimental",body,
            cls.Name,()=>ShowClass(cls)));
    }
    private static Border HunterSettingIcon(string classSlug,int spellId,string fallback,int size)
    {
        var spell=spellId>0?ForeverSpellCatalog.Find(classSlug,spellId):null;
        var atlasIcon=spell is null?null:ForeverSpellCatalog.Icon(spell);
        Control visual=atlasIcon is null
            ? Text(string.IsNullOrEmpty(fallback)?"?":fallback[..1],size/2,"#F9B72E",FontWeight.Bold)
            : new Avalonia.Controls.Image {Source=atlasIcon,Stretch=Stretch.UniformToFill,
                Width=size-2,Height=size-2};
        return new Border {Width=size,Height=size,Child=visual,
            CornerRadius=new CornerRadius(5),ClipToBounds=true,
            Background=Palette.Brush("#2A211D"),
            BorderBrush=Palette.Brush("#A17C4D"),BorderThickness=new Thickness(1)};
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
            try {
                RotationSettingsStore.Reset(settingsFile,profile);
                if(rotationPreview.Running)
                {
                    StopGhub("SETTINGS CHANGED");
                            rotationPreview.Stop("SETTINGS RESET · RESTART PREVIEW");
                    overlay?.SetReadOnlyRecommendation(false,null,rotationPreview.Status);
                }
            }
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
        var mapping=Stack(spacing:9);
        mapping.Children.Add(Text("AUTOMATIC WOW KEYBINDS · RGB V3",15,"#45E5F7",FontWeight.Bold));
        mapping.Children.Add(Text("Bindings are read from the actual WoW action bars (Ctrl/Alt/Shift combinations included) and sent through the existing RGB v3 row. No manual SpellID mapping required. Logitech G HUB is the only input driver.",12,"#CDB29C"));
        mapping.Children.Add(Text("Verified RGB bindings currently received: "+
            autoBindings.Bindings(DateTimeOffset.UtcNow).Count+
            ". No matching key = no input. Macros and ambiguous matches are blocked pending separate validation.",12,"#E5B778"));
        all.Children.Add(Pane(mapping));
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
        Go(Page("RACIALS & CONSUMABLES","Logitech G HUB is the only keyboard input backend",all));
    }
    private void ShowSupport()
    {
        view="support";
        var body=Stack(spacing:13);
        body.Children.Add(Text("SUPPORT · ROTATION DIAGNOSTICS",18,"#45E5F7",FontWeight.Bold));
        body.Children.Add(Text("One report compares XML decisions, Logitech driver IO and independently observed WoW events. An IOCTL call never proves that WoW cast the spell.",12,"#E9B26D"));
        rgbHealthText=Text(rgbMonitor.Summary(),12,"#72D9F3");
        body.Children.Add(Pane(rgbHealthText));
        body.Children.Add(Text("Auto keybinds: "+autoBindings.Bindings(DateTimeOffset.UtcNow).Count+
            " · Logitech: "+LastGhubStatus,12,"#C5E1EF"));
        body.Children.Add(Text("Rotation trace: "+executionTrace.Summary(),12,"#72D9F3"));
        hunterAuditSummaryText=Text(hunterAudit.Summary(),11,"#C5E1EF");
        body.Children.Add(hunterAuditSummaryText);

        var actions=Stack(Orientation.Horizontal,8);
        actions.Children.Add(Action(executionTrace.Recording?"Stop recording":"Start recording",()=>{
            if(executionTrace.Recording)
            {
                executionTrace.Stop(DateTimeOffset.UtcNow,"USER STOP RECORDING");
                hunterAuditRecording=false;
            }
            else
            {
                executionTrace.Start(DateTimeOffset.UtcNow,
                    rotationPreview.Running?"Forever Hunter BM PvE":"Forever diagnostic only");
                if(rotationPreview.Running)StartRotationAudit();
            }
            ShowSupport();
        }));
        actions.Children.Add(Action("Export diagnostic ZIP",()=>{
            try
            {
                var folder=Path.Combine(Environment.GetFolderPath(
                    Environment.SpecialFolder.LocalApplicationData),"LazyG","reports");
                var file=executionTrace.ExportZip(folder,rgbMonitor.ExportJson(),
                    RuntimeDiagnostics.Snapshot(),hunterAudit.ExportJson());
                RuntimeDiagnostics.Add("REPORT","Diagnostic ZIP saved to "+
                    Path.GetFileName(file)+" in %LOCALAPPDATA%\\LazyG\\reports");
            }
            catch(Exception ex)
            {
                RuntimeDiagnostics.Add("REPORT","Export failed: "+ex.GetType().Name);
            }
            RefreshDiagnosticsView(true);
        }));
        actions.Children.Add(Action(fullRgbDiagnosticMode?"Deep RGB OFF":"Deep RGB ON",()=>{
            fullRgbDiagnosticMode=!fullRgbDiagnosticMode;
            spellDiagnosticEnabled=fullRgbDiagnosticMode;
            cooldownDiagnosticEnabled=fullRgbDiagnosticMode;
            lastSpellPacket=null;lastSpellSequence=null;lastSpellDiagnostic="";
            cooldownObserver.Reset();lastCooldownDiagnostic="";
            RuntimeDiagnostics.Add("RGBMON",fullRgbDiagnosticMode?
                "Deep LGD/LGC capture enabled (in-game probe setup required)":
                "Optional LGD/LGC capture disabled");
            ShowSupport();
        }));
        body.Children.Add(actions);

        var tools=Stack(Orientation.Horizontal,8);
        tools.Children.Add(Action("Refresh",()=>RefreshDiagnosticsView(true)));
        tools.Children.Add(Action("Copy log",async ()=>{
            var clipboard=TopLevel.GetTopLevel(this)?.Clipboard;
            if(clipboard is not null)
                await clipboard.SetTextAsync(RuntimeDiagnostics.Snapshot());
        }));
        tools.Children.Add(Action("Clear visible log",()=>{
            RuntimeDiagnostics.Clear();
            RefreshDiagnosticsView(true);
        }));
        body.Children.Add(tools);
        body.Children.Add(Text("For optional WoW spellcast observations enable /lgprobe audit on in game. Without LGE events the report marks results UNOBSERVABLE, never FAILED. XML audit is captured automatically when a rotation runs.",11,"#E9B26D"));
        diagnosticsOutput=new TextBox {
            Text=RuntimeDiagnostics.Snapshot(),
            IsReadOnly=true,AcceptsReturn=true,
            TextWrapping=TextWrapping.NoWrap,
            FontFamily=new Avalonia.Media.FontFamily("Consolas"),
            FontSize=12,Foreground=Palette.Brush("#C5E1EF"),
            Background=Palette.Brush("#041624"),
            BorderThickness=new Thickness(0),Height=285
        };
        body.Children.Add(Pane(diagnosticsOutput,"#041624",8,"#275B78",new Thickness(12)));
        Go(Page("SUPPORT","RGB status · XML versus Logitech versus WoW",Pane(body)));
        RefreshDiagnosticsView(true);
    }
    private void StartRotationAudit()
    {
        hunterAuditProfile=RotationProfileCatalog.Load("hunter","beast-mastery","PvE");
        if(hunterAuditProfile is null)
        {
            hunterAuditRecording=false;
            return;
        }
        string path=Path.Combine(Environment.GetFolderPath(
            Environment.SpecialFolder.LocalApplicationData),"LazyG","rotations",
            "forever-hunter-beast-mastery-pve.json");
        hunterAuditSettings=RotationSettingsStore.Load(path,hunterAuditProfile);
        hunterAudit.Clear();
        lastHunterAuditSample=default;
        lastCastEventSequence=null;
        lastCastEventSpellId=0;
        hunterAuditRecording=true;
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
        if(rotationPreview.Running)
        {
            StopGhub("STOPPED BY USER");
            rotationPreview.Stop("STOPPED BY USER");
            lastPreviewStatus="";
            lastPreviewSpell=null;
            overlay?.SetReadOnlyRecommendation(false,null,rotationPreview.Status);
            RuntimeDiagnostics.Add("ROTATION","User stopped XML rotation and Logitech input");
            if(view=="classes")ShowClasses();
            return;
        }
        try
        {
            // Check G HUB itself on EVERY Start; the virtual bus alone can
            // exist after G HUB was closed. A failed check leaves us stopped.
            if(!GHubRuntime.IsRunning())
                throw new InvalidOperationException(GHubRuntime.NotRunningMessage);
            if(sourceManager.Snapshot(DateTimeOffset.UtcNow).Confirmed is
                RotationSourceId.Hekili or RotationSourceId.JustAC)
                throw new InvalidOperationException("External rotation source selected");
            var profile=RotationProfileCatalog.Load(cls.Id,spec.Id,"PvE");
            if(profile is null)throw new InvalidDataException("No embedded XML for specialization");
            string file=Path.Combine(Environment.GetFolderPath(
                Environment.SpecialFolder.LocalApplicationData),"LazyG","rotations",
                "forever-"+cls.Id+"-"+spec.Id+"-pve.json");
            var settings=RotationSettingsStore.Load(file,profile);
            // Bindings arrive automatically from the Forever Lua RGB tail.
            // Start may precede collection; without a matching key no input.
            ghub.Connect();
            try { rotationPreview.Start(profile,settings); }
            catch {ghub.Disconnect();throw;}
            activeBindings=new System.Collections.Generic.Dictionary<int,string>();
            commandGate.Reset();
            debuffConfirmation.Reset();
            lastDebuffState=DebuffConfirmationState.Idle;
            ghubGeneration++;
            ghubArmed=true;
            LastGhubStatus="CONNECTED / RUNNING";
            executionTrace.Start(DateTimeOffset.UtcNow,
                "forever/"+cls.Id+"/"+spec.Id+"/PvE");
            try {StartRotationAudit();}
            catch(Exception auditEx){
                hunterAuditRecording=false;
                RuntimeDiagnostics.Add("HUNTERAUDIT","Audit unavailable: "+auditEx.GetType().Name);
            }
            executionTrace.Add(DateTimeOffset.UtcNow,"GHUB_CONNECTED",null,
                "Virtual bus opened; keyboard effects not yet proven");
            lastPreviewStatus="";
            lastPreviewSpell=null;
            overlay?.SetReadOnlyRecommendation(true,null,rotationPreview.Status);
            RuntimeDiagnostics.Add("ROTATION","Started XML rotation with Logitech virtual bus · DEV game-untested");
            if(view=="classes")ShowClasses();
        }
        catch(Exception ex)
        {
            StopGhub("START FAILED");
            RuntimeDiagnostics.Add("ROTATION","Start rejected: "+ex.GetType().Name+" · "+ex.Message);
            var notice=new Window {
                Title=!GHubRuntime.IsRunning()?"LazyG · Logitech G HUB required":
                    "LazyG · Logitech Start unavailable",
                Width=490,Height=180,CanResize=false,
                WindowStartupLocation=WindowStartupLocation.CenterOwner,
                Background=Palette.Surface,Foreground=Palette.White
            };
            var content=Stack(spacing:14);
            content.Margin=new Thickness(22);
            content.Children.Add(Text("LOGITECH ROTATION NOT STARTED",15,"#4BE2F4",FontWeight.Bold));
            content.Children.Add(Text(ex is InvalidDataException?
                "The selected XML rotation or its settings are unavailable.":
                ex.Message,13));
            content.Children.Add(Action("OK",notice.Close,true));
            notice.Content=content;notice.ShowDialog(this);
        }
    }
    private void UpdateRotationPreview(DateTimeOffset at)
    {
        if(!rotationPreview.Running)return;
        if(sourceManager.Snapshot(at).Confirmed is
            RotationSourceId.Hekili or RotationSourceId.JustAC)
        {
            StopGhub("EXTERNAL SOURCE SELECTED");
            rotationPreview.Stop("EXTERNAL SOURCE SELECTED");
            overlay?.SetReadOnlyRecommendation(false,null,rotationPreview.Status);
            RuntimeDiagnostics.Add("ROTATION","Internal XML preview stopped: external source");
            return;
        }
        var rec=rotationPreview.Update(latestGameState,at);
        var debuffStatus=debuffConfirmation.Observe(latestGameState,at);
        if(debuffStatus.State!=lastDebuffState)
        {
            executionTrace.Add(at,"DEBUFF_VERIFICATION",debuffStatus.PendingSpellId,
                debuffStatus.State+": "+debuffStatus.Detail);
            RuntimeDiagnostics.Add("DEBUFF",debuffStatus.State+": "+debuffStatus.Detail);
            lastDebuffState=debuffStatus.State;
        }
        string status=rotationPreview.Status;
        if(debuffConfirmation.HasPending)
            status+=" · "+debuffStatus.Detail;
        if(status!=lastPreviewStatus || rec?.SpellId!=lastPreviewSpell)
        {
            RuntimeDiagnostics.Add("ROTATION",status);
            if(rec is not null)
                executionTrace.Recommend(at,rec.SpellId,rec.RuleId);
            else executionTrace.Add(at,"XML_BLOCKED",null,status);
            lastPreviewStatus=status;
            lastPreviewSpell=rec?.SpellId;
        }
        // Sonah-like ADVICE, independent of Logitech execution:
        // never hide the outstanding Mark/Sting icon simply because HID
        // completed or auras became unreadable. A pending same-target debuff
        // takes visual precedence over later lower-priority XML candidates.
        var markAdvice=HunterDebuffAdvice.SuggestMark(latestGameState,at,
            rotationPreview.IsSettingEnabled("useHuntersMark"));
        int? displaySpell=debuffConfirmation.PendingSpellId ??
            markAdvice?.SpellId ?? rec?.SpellId;
        bool adviceOnly=debuffConfirmation.HasPending ||
            (markAdvice is not null && markAdvice.SpellId!=rec?.SpellId);
        string displayStatus=status;
        if(adviceOnly)
            displayStatus+=" · "+(debuffConfirmation.HasPending?
                "PENDING DEBUFF (not yet observed)":
                markAdvice?.Reason ?? "Advisory only");
        overlay?.SetReadOnlyRecommendation(true,displaySpell,displayStatus,
            adviceOnly);
        if(ghubArmed)
            QueueLogitechCommand(rec,at);
    }
    private void StopGhub(string reason)
    {
        bool hadTrace=executionTrace.Recording;
        executionTrace.Stop(DateTimeOffset.UtcNow,reason);
        hunterAuditRecording=false;
        if(hadTrace)
        {
            try
            {
                var dir=Path.Combine(Environment.GetFolderPath(
                    Environment.SpecialFolder.LocalApplicationData),"LazyG","reports");
                var file=executionTrace.ExportZip(dir,rgbMonitor.ExportJson(),
                    RuntimeDiagnostics.Snapshot(),hunterAudit.ExportJson());
                RuntimeDiagnostics.Add("REPORT","Automatic stop report: "+
                    Path.GetFileName(file)+" in %LOCALAPPDATA%\\LazyG\\reports");
            }
            catch(Exception ex)
            {
                RuntimeDiagnostics.Add("REPORT","Auto-save failed: "+ex.GetType().Name);
            }
        }
        ghubArmed=false;
        ghubGeneration++;
        activeBindings=new System.Collections.Generic.Dictionary<int,string>();
        commandGate.Reset();
        debuffConfirmation.Reset();
        lastDebuffState=DebuffConfirmationState.Idle;
        LastGhubStatus=reason;
        // The 12-ms report already in flight always releases its key.
        // No new report may start after generation invalidation.
        if(!ghubBusy)ghub.Disconnect();
        RuntimeDiagnostics.Add("GHUB",reason);
    }
    private void QueueLogitechCommand(RotationRecommendation? rec,DateTimeOffset frameAt)
    {
        if(!ghubArmed || ghubBusy || rec is null)return;
        var now=DateTimeOffset.UtcNow;
        if(!debuffConfirmation.MaySend(rec,latestGameState,now,out var debuffReason))
        {
            if(debuffReason!=lastInputGateReason)
            {
                executionTrace.Add(now,"INPUT_BLOCKED",rec.SpellId,
                    debuffReason,null,rec.RuleId);
                lastInputGateReason=debuffReason;
            }
            return;
        }
        // SRC has not shipped: explicitly running embedded Internal XML may
        // use only the locally verified internal path + freshly decoded RGB.
        // A failed/confirmed external provider never qualifies for fallback.
        var src=sourceManager.Snapshot(now);
        if(src.Confirmed is not null || src.Health!=RotationSourceHealth.AwaitingTransport)
        {
            StopGhub("SOURCE NOT INTERNAL");
            rotationPreview.Stop("SOURCE NOT INTERNAL");
            return;
        }
        var internalSource=new RotationSourceSnapshot(RotationSourceId.Internal,
            RotationSourceHealth.Ready,ghubGeneration,0,frameAt,null,
            "Explicit local XML / fresh RGB");
        // Only confirmed, CRC-decoded, fresh auto bindings can authorize
        // Logitech HID input. Legacy user-entered mappings are not used.
        activeBindings=autoBindings.Bindings(now);
        var cmd=commandGate.TryPlan(rec,internalSource,latestGameState,now,
            ghubArmed,GHubDriver.IsWowForeground(),activeBindings,out var reason);
        if(cmd is null)
        {
            if(reason!=lastInputGateReason)
            {
                executionTrace.Add(now,"INPUT_BLOCKED",rec.SpellId,reason,
                    null,rec.RuleId);
                lastInputGateReason=reason;
            }
            if(reason=="WOW NOT FOREGROUND")
            {
                StopGhub("WOW LOST FOCUS");
                rotationPreview.Stop("WOW LOST FOCUS");
                overlay?.SetReadOnlyRecommendation(false,null,rotationPreview.Status);
            }
            return;
        }
        if(!GHubKeys.TryParse(cmd.Key,out var mod,out var usage))
        {
            executionTrace.Add(now,"INPUT_BLOCKED",rec.SpellId,"Invalid HID binding",
                null,rec.RuleId);
            return;
        }
        lastInputGateReason="";
        long attempt=executionTrace.Attempt(now,rec.SpellId,rec.RuleId);
        executionTrace.Add(now,"HID_BINDING",rec.SpellId,
            "modifier="+mod+" usage="+usage,attempt,rec.RuleId);
        ghubBusy=true;
        long generation=ghubGeneration;
        var stateAtPlan=latestGameState;
        _=Task.Run(()=>{
            try
            {
                // No queued stale keystrokes and a second foreground check
                // inside TapKey at the moment of DeviceIoControl.
                if(generation==System.Threading.Interlocked.Read(ref ghubGeneration) &&
                   ghubArmed && ghub.Connected)
                {
                    ghub.TapKey(mod,usage);
                    Dispatcher.UIThread.Post(()=>{
                        if(generation!=ghubGeneration)return;
                        if(debuffConfirmation.MarkSent(rec,stateAtPlan,
                            DateTimeOffset.UtcNow))
                            executionTrace.Add(DateTimeOffset.UtcNow,
                                "DEBUFF_PENDING",rec.SpellId,
                                "HID completed; waiting for observed target aura",attempt,
                                rec.RuleId);
                    });
                    executionTrace.DriverResult(DateTimeOffset.UtcNow,rec.SpellId,
                        attempt,true,"DeviceIoControl press/release returned; WoW action not proven");
                }
                else executionTrace.Add(DateTimeOffset.UtcNow,"HID_SKIPPED",
                    rec.SpellId,"Stop or disconnected before HID call",attempt,rec.RuleId);
            }
            catch(Exception ex)
            {
                executionTrace.DriverResult(DateTimeOffset.UtcNow,rec.SpellId,
                    attempt,false,ex.GetType().Name);
                Dispatcher.UIThread.Post(()=>{
                    if(generation!=ghubGeneration)return;
                    StopGhub("LOGITECH ERROR: "+ex.GetType().Name);
                    rotationPreview.Stop("LOGITECH DISCONNECTED");
                    overlay?.SetReadOnlyRecommendation(false,null,rotationPreview.Status);
                });
            }
            finally
            {
                Dispatcher.UIThread.Post(()=>{
                    ghubBusy=false;
                    if(!ghubArmed)ghub.Disconnect();
                });
            }
        });
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
        if(rotationPreview.Running)
            overlay.SetReadOnlyRecommendation(true,rotationPreview.Current?.SpellId,
                rotationPreview.Status);
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
                StopGhub("SETUP CHANGED");
                rotationPreview.Stop("SETUP CHANGED");
                RuntimeDiagnostics.Add("SETUP","Finished · Forever client active");
            }
            else RuntimeDiagnostics.Add("SETUP","Closed without completing RGB setup");
            if(!finished){Show();Activate();}
        };
        StopGhub("SETUP OPENED");
        rotationPreview.Stop("SETUP OPENED");
        overlay?.SetReadOnlyRecommendation(false,null,rotationPreview.Status);
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
                    hunterAuditRecording,out var castEvent,
                    hunterCompactManifest is null?0:
                        HunterCompactProfileWire.ExtensionCells(hunterCompactManifest));
                stopwatch.Stop();
                return (ok,state,packet,detail,v3,thresholds,spell,cooldown,castEvent,
                    capturedAt:DateTimeOffset.UtcNow,
                    captureMs:stopwatch.Elapsed.TotalMilliseconds);
            });
            if(finished)return;
            var connected=result.ok && result.state is not null;
            if(connected && result.packet is not null)
                autoBindings.Accept(result.packet,hunterCompactManifest is null?0:
                    HunterCompactProfileWire.ExtensionCells(hunterCompactManifest),
                    result.capturedAt);
            else autoBindings.Reset();
            int bindingCount=autoBindings.Bindings(result.capturedAt).Count;
            if(lastAutoBindingCount!=bindingCount)
            {
                lastAutoBindingCount=bindingCount;
                executionTrace.Add(result.capturedAt,"AUTO_BINDINGS",null,
                    "Confirmed active mappings="+bindingCount);
            }
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
            // Optional, versioned Hunter BM snapshot in the SAME v3 RGB row.
            // A first new frame after loss is baseline only. Two distinct CRC-
            // valid frames are required; malformed/stale packets never persist.
            bool compactValid=connected && result.packet is not null &&
                result.packet.ExtensionCells>0 && hunterCompactManifest is not null &&
                HunterCompactProfileWire.TryDecode(result.packet,hunterCompactManifest,
                    result.capturedAt,out var _);
            if(!compactValid)
            {
                lastCompactFrame=null;
                lastCompactFrameAt=default;
                compactSequenceEstablished=false;
            }
            else if(hunterCompactManifest is not null &&
                    HunterCompactProfileWire.TryDecode(result.packet,hunterCompactManifest,
                        result.capturedAt,out var compact) && compact is not null)
            {
                var frameCounter=result.packet!.FrameCounter;
                if(lastCompactFrame is null)
                {
                    lastCompactFrame=frameCounter;
                    lastCompactFrameAt=result.capturedAt;
                }
                else
                {
                    if(lastCompactFrame.Value!=frameCounter)
                    {
                        lastCompactFrame=frameCounter;
                        lastCompactFrameAt=result.capturedAt;
                        compactSequenceEstablished=true;
                    }
                    if(compactSequenceEstablished &&
                       result.capturedAt-lastCompactFrameAt<=TimeSpan.FromMilliseconds(900))
                        latestGameState=HunterCompactProfileWire.ToGameState(
                            latestGameState,compact);
                }
            }
            string compactDiagnostic=HunterCompactProfileWire.Explain(
                connected?result.packet:null,hunterCompactManifest,result.capturedAt)+
                (compactValid?(compactSequenceEstablished?" / SEQUENCE LIVE":
                    " / AWAITING SECOND FRAME"):" / NO GAMESTATE APPLICATION");
            if(lastCompactDiagnostic!=compactDiagnostic)
            {
                executionTrace.Add(result.capturedAt,"COMPACT",null,compactDiagnostic);
                RuntimeDiagnostics.Add("COMPACT",compactDiagnostic);
                lastCompactDiagnostic=compactDiagnostic;
            }
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
            // LGC 29515.isActive is already observed in live Forever.
            // Publish only the fresh boolean into GameState: no synthetic
            // remaining GCD milliseconds, no effect/cast authorization.
            var gcdObservation=cooldownObserver.Snapshot;
            if(connected && gcdObservation.Transport==Knowledge.Known &&
               gcdObservation.Gcd29515Active.UpdatedAt<=result.capturedAt &&
               result.capturedAt-gcdObservation.Gcd29515Active.UpdatedAt <=
                   ForeverCooldownObserver.MaxFrameAge)
                latestGameState=latestGameState with {
                    GcdActive=gcdObservation.Gcd29515Active
                };
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
                else if(cast.Sequence==lastCastEventSequence &&
                    cast.SpellId==lastCastEventSpellId)
                {
                    // Repeated latched frame is not another cast.
                    if(cast.PlayerEvent)hunterAudit.RecordDuplicateEvent();
                }
                else if(cast.PlayerEvent)
                {
                    lastCastEventSequence=cast.Sequence;
                    lastCastEventSpellId=cast.SpellId;
                    executionTrace.CastEvent(result.capturedAt,cast.SpellId,true);
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
            UpdateRotationPreview(result.capturedAt);
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
            if(rotationPreview.Running)
            {
                latestGameState=GameState.Empty(DateTimeOffset.UtcNow);
                UpdateRotationPreview(DateTimeOffset.UtcNow);
            }
            autoBindings.Reset();
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
