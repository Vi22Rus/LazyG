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
    private readonly TextBlock statusText = Text("CORE —",12,"#93CBE5");
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
    // Isolated experiment: direct LazyGCore-native recommendations.
    private bool lazyGCoreMode;
    private bool connectorRunning;
    // Isolated fork: never sample the legacy RGB transport in this build.
    private const bool NativeOnlyExperiment = true;
    private bool coreComparisonRecording;
    private RotationProfileV2? nativeXmlProfile;
    private byte? lastNativeInputSequence;
    private DateTimeOffset lastNativeInputAt;
    private DateTimeOffset lastCoreComparisonAt;
    private LazyGCoreRgbPacket? lazyGCorePacket;
    private byte? lastLazyGCoreSequence;
    private DateTimeOffset lastLazyGCoreSequenceAt;
    private bool lazyGCoreSequenceEstablished;
    private string lastLazyGCoreDiagnostic="";
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
        // External addon supplies the already-computed recommendation.
        Content = CreateShell();
        ShowClasses();
        timer.Tick += async (_, _) => await PollBridgeAsync();
        timer.Start();
        Closed += (_, _) => { finished = true; StopGhub("WINDOW CLOSED"); timer.Stop(); overlay?.Close(); };
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
        statusText.MaxWidth=68;
        game.Children.Add(clientText);game.Children.Add(statusText);
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
        wrap.Children.Add(Action(connectorRunning?"Stop Connector":"Start Connector",
            ToggleConnector,true));
        wrap.Children.Add(Text("External recommendations only: JustAC / Hekili (choose source with /lgconnector). No LazyG XML engine.",12,"#A3CADA"));
        var selection = client.Classes.FirstOrDefault(c=>c.Id==session.LastClass);
        var lastSpec = selection?.Specs.FirstOrDefault(s=>s.Id==session.LastSpec);
        if(selection is not null && lastSpec is not null)
        {
            var last = new Grid { ColumnDefinitions=new ColumnDefinitions("Auto,*,Auto"), ColumnSpacing=17 };
            last.Children.Add(SpellIcon(lastSpec.Icon,59));
            var labels=Stack(spacing:3);labels.Children.Add(Text("LAST USED",11,"#52E3F4",FontWeight.Bold));
            labels.Children.Add(Text(lastSpec.Name+"  ·  "+selection.Name,20,"#FFFFFF",FontWeight.SemiBold));
            labels.Children.Add(Text("Class and spell catalogue (recommendations come from installed addon)",12,"#A3BCCC"));
            Grid.SetColumn(labels,1);last.Children.Add(labels);
            var b=Action(connectorRunning?"Stop":"Start Connector",
                ToggleConnector,true);b.VerticalAlignment=VerticalAlignment.Center;

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
        body.Children.Add(Text("Ротации рассчитывают только JustAC или Hekili. Встроенные XML/приоритеты LazyG отключены.",13,"#A3CADA"));
        body.Children.Add(Action(connectorRunning?"Stop Connector":"Start Connector",ToggleConnector,true));
        body.Children.Add(Action("Support — RGB / G HUB журнал",ShowSupport));
        Go(Page(spec.Name.ToUpperInvariant(),"External addon connector",body,cls.Name,()=>ShowClass(cls)));
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
            0+
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
        body.Children.Add(Text("JustAC/Hekili → RGB v3 → Logitech G HUB. No internal rotation/XML/GCD. Successful driver IO does not prove a WoW cast.",12,"#E9B26D"));
        body.Children.Add(Text("Connector RGB v3 only · see source/CRC diagnostic log below",12,"#72D9F3"));
        body.Children.Add(Text("Bindings: from connector RGB · Logitech: "+LastGhubStatus,12,"#C5E1EF"));
        body.Children.Add(Text("Rotation trace: "+executionTrace.Summary(),12,"#72D9F3"));


        var actions=Stack(Orientation.Horizontal,8);
        actions.Children.Add(Action(executionTrace.Recording?"Stop recording":"Start recording",()=>{
            if(executionTrace.Recording)
            {
                executionTrace.Stop(DateTimeOffset.UtcNow,"USER STOP RECORDING");
                // External recommendations only.
            }
            else
            {
                executionTrace.Start(DateTimeOffset.UtcNow,
                    connectorRunning?"JustAC/Hekili external connector":"Forever diagnostic only");
                // No internal Hunter XML audit in connector mode.
            }
            ShowSupport();
        }));
        actions.Children.Add(Action("Export diagnostic ZIP",()=>{
            try
            {
                var folder=Path.Combine(Environment.GetFolderPath(
                    Environment.SpecialFolder.LocalApplicationData),"LazyG","reports");
                var file=executionTrace.ExportZip(folder,"{\"source\":\"LazyGConnector-v3\"}",
                    RuntimeDiagnostics.Snapshot());
                RuntimeDiagnostics.Add("REPORT","Diagnostic ZIP saved to "+
                    Path.GetFileName(file)+" in %LOCALAPPDATA%\\LazyG\\reports");
            }
            catch(Exception ex)
            {
                RuntimeDiagnostics.Add("REPORT","Export failed: "+ex.GetType().Name);
            }
            RefreshDiagnosticsView(true);
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
        body.Children.Add(Text("Use /lgconnector justac or /lgconnector hekili in WoW. Log records source, SpellID, HID binding and driver result; game cast is not verified.",11,"#E9B26D"));
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
        Go(Page("SUPPORT","External RGB source · Logitech G HUB",Pane(body)));
        RefreshDiagnosticsView(true);
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
    private void ToggleConnector()
    {
        if(connectorRunning)
        {
            StopGhub("CONNECTOR STOPPED BY USER");
            overlay?.SetReadOnlyRecommendation(false,null,"STOPPED");
            ShowClasses();
            return;
        }
        try
        {
            if(!GHubRuntime.IsRunning())
                throw new InvalidOperationException("Logitech G HUB is not running");
            ghub.Connect();
            ghubGeneration++;
            ghubArmed=true;
            connectorRunning=true;
            lazyGCoreMode=true; // Native frame sender, never legacy/XML
            lazyGCorePacket=null;
            lastLazyGCoreSequence=null;
            lastLazyGCoreSequenceAt=default;
            lazyGCoreSequenceEstablished=false;
            lastNativeInputSequence=null;
            lastNativeInputAt=default;
            lastPreviewStatus="";
            lastPreviewSpell=null;
            lastInputGateReason="";
            LastGhubStatus="EXTERNAL CONNECTOR v3 / G HUB ARMED";
            executionTrace.Start(DateTimeOffset.UtcNow,"Forever JustAC/Hekili connector (RGB v3)");
            RuntimeDiagnostics.Add("CONNECTOR","Started: source selected inside WoW with /lgconnector; no XML, class rotations or game-state calculations");
            overlay?.SetReadOnlyRecommendation(true,null,"CONNECTOR WAITING RGB v3");
            ShowClasses();
        }
        catch(Exception ex)
        {
            StopGhub("CONNECTOR START FAILED");
            RuntimeDiagnostics.Add("CONNECTOR","Start failed: "+ex.Message);
            ShowClasses();
        }
    }

    private void UpdateConnectorPreview(DateTimeOffset at)
    {
        if(!connectorRunning)return;
        var p=lazyGCorePacket;
        bool fresh=lazyGCoreSequenceEstablished &&
            p is { Version:3 } && lastLazyGCoreSequenceAt!=default &&
            at-lastLazyGCoreSequenceAt<=TimeSpan.FromMilliseconds(900);
        string provider=p?.ProviderId switch
        {
            1=>"JustAC",2=>"Hekili",_=>"NONE"
        };
        int? spell=fresh && p?.Status==1?p.SpellId:null;
        string status=!fresh?"CONNECTOR RGB v3 WAITING":
            p?.Status==1 ? provider+" SPELL "+p.SpellId :
            provider+" NO RECOMMENDATION ("+(p?.Status.ToString()??"NONE")+")";
        if(status!=lastPreviewStatus || spell!=lastPreviewSpell)
        {
            RuntimeDiagnostics.Add("CONNECTOR",status);
            if(spell is int id)
                executionTrace.Add(at,"EXTERNAL_RECOMMENDED",id,
                    "Source="+provider+"; exactly published addon first pick, not XML");
            lastPreviewStatus=status;
            lastPreviewSpell=spell;
        }
        overlay?.SetReadOnlyRecommendation(true,spell,status);
        if(spell is int selected && p is not null && ghubArmed)
        {
            var src=p.ProviderId==1?RotationSourceId.JustAC:RotationSourceId.Hekili;
            QueueNativeLogitechCommand(new RotationRecommendation(src,selected,0,
                "connector-"+provider,at),at);
        }
    }

    private void StopGhub(string reason)
    {
        bool hadTrace=executionTrace.Recording;
        executionTrace.Stop(DateTimeOffset.UtcNow,reason);
        // No internal Hunter XML audit.
        if(hadTrace)
        {
            try
            {
                var dir=Path.Combine(Environment.GetFolderPath(
                    Environment.SpecialFolder.LocalApplicationData),"LazyG","reports");
                var file=executionTrace.ExportZip(dir,"{\"source\":\"LazyGConnector-v3\"}",
                    RuntimeDiagnostics.Snapshot());
                RuntimeDiagnostics.Add("REPORT","Automatic stop report: "+
                    Path.GetFileName(file)+" in %LOCALAPPDATA%\\LazyG\\reports");
            }
            catch(Exception ex)
            {
                RuntimeDiagnostics.Add("REPORT","Auto-save failed: "+ex.GetType().Name);
            }
        }
        ghubArmed=false;
        lazyGCoreMode=false;
        connectorRunning=false;
        lazyGCorePacket=null;
        lazyGCoreSequenceEstablished=false;
        lastNativeInputSequence=null;
        lastNativeInputAt=default;
        ghubGeneration++;
        // No internal command/debuff planners.
        LastGhubStatus=reason;
        // The 12-ms report already in flight always releases its key.
        // No new report may start after generation invalidation.
        if(!ghubBusy)ghub.Disconnect();
        RuntimeDiagnostics.Add("GHUB",reason);
    }
    private void QueueNativeLogitechCommand(RotationRecommendation rec,DateTimeOffset frameAt)
    {
        if(!lazyGCoreMode || !ghubArmed || ghubBusy)return;
        var now=DateTimeOffset.UtcNow;
        var packet=lazyGCorePacket;
        string? reason=null;
        if(packet is null || packet.Version!=3 || packet.Status!=1 ||
           packet.SpellId!=rec.SpellId ||
           !lazyGCoreSequenceEstablished || now-lastLazyGCoreSequenceAt>
               TimeSpan.FromMilliseconds(900))reason="NATIVE RGB STALE / INVALID";
        else if(!packet.NativeInputReady)reason=
            "NATIVE UNVERIFIED: binding="+packet.HasNativeBinding+
            " selfBuff="+packet.NativeSelfBuff+
            " target="+packet.NativeTargetReady+
            " gcd="+packet.NativeGcdReady+" spell="+packet.NativeSpellReady+
            " range="+packet.NativeRangeReady+
            " usable="+packet.NativeUsableReady;
        else if(lastNativeInputSequence==packet.Sequence)reason="NATIVE DUPLICATE FRAME";
        else if(lastNativeInputAt!=default && now-lastNativeInputAt<
                TimeSpan.FromMilliseconds(1500))reason="NATIVE INPUT PACING";
        else if(!GHubDriver.IsWowForeground())reason="WOW NOT FOREGROUND";
        else if(!ghub.Connected)reason="LOGITECH NOT CONNECTED";
        if(reason is not null)
        {
            if(reason!=lastInputGateReason)
            {
                executionTrace.Add(now,"INPUT_BLOCKED",rec.SpellId,reason);
                lastInputGateReason=reason;
            }
            return;
        }
        lastInputGateReason="";
        // Provider has already chosen its spell. Connector does not calculate
        // cooldowns, target, auras, class rotation or GCD.

        lastNativeInputSequence=packet.Sequence;
        lastNativeInputAt=now;
        var mod=packet.HidModifier;
        var usage=packet.HidUsage;
        long attempt=executionTrace.Attempt(now,rec.SpellId,rec.RuleId);
        executionTrace.Add(now,"NATIVE_HID_BINDING",rec.SpellId,
            "modifier="+mod+" usage="+usage+" sequence="+packet.Sequence+
            " provider="+(packet.ProviderId==1?"JustAC":"Hekili"),attempt,
            rec.RuleId);
        ghubBusy=true;
        long generation=ghubGeneration;
        _=Task.Run(()=>{
            try
            {
                if(generation==System.Threading.Interlocked.Read(ref ghubGeneration) &&
                   ghubArmed && ghub.Connected)
                {
                    ghub.TapKey(mod,usage);
                    executionTrace.DriverResult(DateTimeOffset.UtcNow,rec.SpellId,
                        attempt,true,"External RGB v3 HID press/release returned; not proof of WoW cast");
                }
                else executionTrace.Add(DateTimeOffset.UtcNow,"HID_SKIPPED",
                    rec.SpellId,"Stop/disconnect before native key",attempt,"lazygcore-native");
            }
            catch(Exception ex)
            {
                executionTrace.DriverResult(DateTimeOffset.UtcNow,rec.SpellId,
                    attempt,false,ex.GetType().Name);
                Dispatcher.UIThread.Post(()=>{
                    if(generation!=ghubGeneration)return;
                    StopGhub("NATIVE LOGITECH ERROR: "+ex.GetType().Name);
                    overlay?.SetReadOnlyRecommendation(false,null,"LOGITECH DISCONNECTED");
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
        if(connectorRunning)
            overlay.SetReadOnlyRecommendation(true,lastPreviewSpell,lastPreviewStatus);
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
                RuntimeDiagnostics.Add("SETUP","Finished · Forever client active");
            }
            else RuntimeDiagnostics.Add("SETUP","Closed without completing RGB setup");
            if(!finished){Show();Activate();}
        };
        StopGhub("SETUP OPENED");
        overlay?.SetReadOnlyRecommendation(false,null,"SETUP OPENED");
        dialog.Show();
        Hide();
    }
    // External-provider-only transport: no XML evaluator, no legacy RGB or
    // redundant game-state/GCD/aura probes. Fail closed on missing v3 frames.
    private async Task PollBridgeAsync()
    {
        if(scanning || finished || setupOpen)return;
        scanning=true;
        try
        {
            var native=await Task.Run(()=>{
                bool ok=WowRgbBridge.TryReadLazyGConnector(out var packet,
                    out var detail);
                return (ok,packet,detail,at:DateTimeOffset.UtcNow);
            });
            if(finished)return;
            if(native.ok && native.packet is not null)
            {
                lazyGCorePacket=native.packet;
                byte seq=native.packet.Sequence;
                if(lastLazyGCoreSequence is not byte prev)
                    lastLazyGCoreSequence=seq;
                else if(prev!=seq)
                {
                    lastLazyGCoreSequence=seq;
                    lastLazyGCoreSequenceAt=native.at;
                    lazyGCoreSequenceEstablished=true;
                }
            }
            else
            {
                lazyGCorePacket=null;
                lastLazyGCoreSequence=null;
                lastLazyGCoreSequenceAt=default;
                lazyGCoreSequenceEstablished=false;
            }
            var packet=lazyGCorePacket;
            var provider=packet?.ProviderId switch {1=>"JustAC",2=>"Hekili",_=>"NONE"};
            statusText.Text=native.ok ? (provider=="JustAC"?"JAC ●":"HEK ●"):"RGB —";
            string diag=packet is null?"Connector RGB not found: "+native.detail:
                "CONNECTOR CRC OK v3 provider="+provider+
                " spell="+packet.SpellId+" status="+packet.Status+
                " bind="+packet.HasNativeBinding+
                " modifier="+packet.HidModifier+" usage="+packet.HidUsage+
                " sequence="+packet.Sequence;
            if(diag!=lastLazyGCoreDiagnostic)
            {
                RuntimeDiagnostics.Add("CONNECTOR",diag);
                lastLazyGCoreDiagnostic=diag;
            }
            UpdateConnectorPreview(native.at);
            overlay?.SetConnection(lazyGCoreSequenceEstablished,true,false,false,null,null);
            RefreshDiagnosticsView();
        }
        catch(Exception ex)
        {
            lazyGCorePacket=null;
            lazyGCoreSequenceEstablished=false;
            RuntimeDiagnostics.Add("CONNECTOR","RGB read failure: "+ex.GetType().Name);
        }
        finally{scanning=false;}
    }
}
