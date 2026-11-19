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
        Title = "LazyG · 0.3.0-dev";
        RuntimeDiagnostics.Add("APP", "LazyG 0.2.20-dev started · Forever UI");
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
        footer.Children.Add(Text("  LazyG 0.2.13-dev  ·  Forever profile  ·  Local desktop application",11,"#719BB2"));
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
    private void ShowSpec(GameClass cls,Specialization spec)
    {
        selectedClass=cls;selectedSpec=spec;view="rotation";
        session.LastClient="forever";session.LastClass=cls.Id;session.LastSpec=spec.Id;session.Save();
        var body=Stack(spacing:18);
        var top=Stack(Orientation.Horizontal,16);top.Children.Add(SpellIcon(spec.Icon,86));
        var identity=Stack(spacing:5);
        identity.Children.Add(Text(spec.Name,27,"#FFFFFF",FontWeight.Bold));
        identity.Children.Add(Text(cls.Name+"  ·  WoW Forever  ·  PvE / PvP",13,cls.Accent));
        top.Children.Add(identity);body.Children.Add(Pane(top,"#0B2941"));
        var blank=Stack(spacing:12);
        blank.Children.Add(Text("ROTATION SETTINGS",14,"#ECB66E",FontWeight.Bold));
        blank.Children.Add(Text("No rotation profile installed",21,"#F1FAFF",FontWeight.SemiBold));
        blank.Children.Add(Text("This page is intentionally empty. Ability toggles, thresholds and priorities will be defined by LazyG XML rotations.",13,"#C7B1A4"));
        body.Children.Add(Pane(blank,"#261B16",12,"#594032",new Thickness(25,34)));
        Go(Page(spec.Name.ToUpperInvariant(),"Class → Specialization → Rotation settings",body,cls.Name,()=>ShowClass(cls)));
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
                    cooldownDiagnosticEnabled,out var cooldown);
                stopwatch.Stop();
                return (ok,state,packet,detail,v3,thresholds,spell,cooldown,
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
