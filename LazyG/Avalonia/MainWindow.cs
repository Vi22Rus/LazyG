using System;
using System.Linq;
using System.Threading.Tasks;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Threading;
using LazyGPrototype;
using Control = Avalonia.Controls.Control;
using Button = Avalonia.Controls.Button;
using Orientation = Avalonia.Layout.Orientation;
using HAlign = Avalonia.Layout.HorizontalAlignment;

namespace LazyG.Desktop;

public sealed class MainWindow : Window
{
    private readonly UserSession session = UserSession.Load();
    private readonly Border rootBody = new();
    private readonly TextBlock statusText = Text("GAME NOT CONNECTED",12,"#EFC28D");
    private readonly TextBlock clientText = Text("WOW FOREVER",12,"#E0B477");
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromMilliseconds(400) };
    private readonly GameClient client = ClientCatalog.Forever;
    private GameClass? selectedClass;
    private Specialization? selectedSpec;
    private string view = "classes";
    private bool scanning;
    private bool setupOpen;
    private OverlayWindow? overlay;
    private Button? overlayButton;
    private TextBlock? diagnosticsOutput;
    private string lastBridgeState = "";
    private string lastProbeState = "";
    private bool finished;
    public MainWindow()
    {
        Title = "LazyG · 0.2.1-dev";
        RuntimeDiagnostics.Add("APP", "LazyG 0.2.1-dev started · Forever UI");
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
    private static TextBlock Text(string text, double size = 14, string foreground = "#F7EDE4", FontWeight? weight = null) =>
        new() { Text = text, FontSize = size, Foreground = Palette.Brush(foreground),
            FontWeight = weight ?? FontWeight.Normal, TextWrapping = TextWrapping.Wrap,
            VerticalAlignment = VerticalAlignment.Center };
    private static Border Pane(Control child, string bg="#251B16", double radius=12, string stroke="#4D3526", Thickness? padding=null) =>
        new() { Child = child, Background = Palette.Brush(bg), CornerRadius = new CornerRadius(radius),
            BorderBrush = Palette.Brush(stroke), BorderThickness = new Thickness(1), Padding = padding ?? new Thickness(16) };
    private static StackPanel Stack(Orientation orientation = Orientation.Vertical, double spacing=0) =>
        new() { Orientation=orientation, Spacing=spacing };
    private static Button Action(string label, Action click, bool primary=false, double minWidth=0)
    {
        var b = new Button { Content=label, Padding=new Thickness(19,9), MinWidth=minWidth,
            HorizontalContentAlignment=HAlign.Center, VerticalContentAlignment=VerticalAlignment.Center,
            Background=Palette.Brush(primary?"#E3A143":"#32231A"), Foreground=Palette.Brush(primary?"#25170B":"#F8E9DB"),
            BorderBrush=Palette.Brush(primary?"#FBC675":"#69472A"), BorderThickness=new Thickness(1),
            CornerRadius=new CornerRadius(9), FontWeight=FontWeight.SemiBold };
        b.Click += (_,_)=>click();
        return b;
    }
    private Control CreateShell()
    {
        var shell = new Grid { RowDefinitions=new RowDefinitions("58,*,34") };
        var header = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,Auto,*,Auto,Auto,Auto,Auto"), Background=Palette.Brush("#1B120F") };
        header.PointerPressed += (_,e) => { if (e.GetCurrentPoint(header).Properties.IsLeftButtonPressed && e.Source is not Button) BeginMoveDrag(e); };
        var brand = Stack(Orientation.Horizontal,11);
        brand.VerticalAlignment=VerticalAlignment.Center;
        brand.Children.Add(Text("◆",22,"#E9A446",FontWeight.Bold));
        brand.Children.Add(Text("LazyG",24,"#F7F1E9",FontWeight.Bold));
        brand.Margin=new Thickness(20,0,28,0);
        header.Children.Add(brand);
        var tabs = Stack(Orientation.Horizontal,8);
        tabs.VerticalAlignment=VerticalAlignment.Center;
        tabs.Children.Add(Action("Classes & Specs",ShowClasses));
        tabs.Children.Add(Action("Racials & Consumables",ShowCommon));
        tabs.Children.Add(Action("Support",ShowSupport));
        Grid.SetColumn(tabs,1);header.Children.Add(tabs);
        var game = Stack(Orientation.Horizontal,9);
        game.VerticalAlignment=VerticalAlignment.Center;
        game.HorizontalAlignment=HAlign.Right;
        game.Margin=new Thickness(8);
        game.Children.Add(clientText);game.Children.Add(Text("●",12,"#5DC78C"));game.Children.Add(statusText);
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
        Grid.SetRow(header,0);shell.Children.Add(header);
        var bodyWrap = new Border { Background=new LinearGradientBrush { StartPoint=new RelativePoint(0,0,RelativeUnit.Relative),
            EndPoint=new RelativePoint(1,1,RelativeUnit.Relative),
            GradientStops=new GradientStops {
                new GradientStop(Avalonia.Media.Color.Parse("#3D2417"),0),
                new GradientStop(Avalonia.Media.Color.Parse("#20150F"),0.48),
                new GradientStop(Avalonia.Media.Color.Parse("#100D0C"),1)
            } }, Child=new ScrollViewer { Content=rootBody, HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled,
                 VerticalScrollBarVisibility=ScrollBarVisibility.Auto } };
        Grid.SetRow(bodyWrap,1);shell.Children.Add(bodyWrap);
        var footer = new Grid { ColumnDefinitions=new ColumnDefinitions("*,Auto"), Background=Palette.Brush("#15100E"),
            Margin=new Thickness(0) };
        footer.Children.Add(Text("  LazyG 0.2.1-dev  ·  Forever profile  ·  Local desktop application",11,"#8F7A6D"));
        var fw=Text("Rotation engine: not configured   ·   No automatic input",11,"#8F7A6D");
        fw.Margin=new Thickness(10,0,18,0);Grid.SetColumn(fw,1);footer.Children.Add(fw);
        Grid.SetRow(footer,2);shell.Children.Add(footer);
        return shell;
    }
    private Button WindowAction(string label,Action action,bool close=false)
    {
        var b=new Button { Content=label,Width=45,Padding=new Thickness(0),
            Background=Palette.Brush("#1B120F"), Foreground=Palette.White, BorderThickness=new Thickness(0),
            FontSize=17,VerticalContentAlignment=VerticalAlignment.Center,HorizontalContentAlignment=HAlign.Center };
        b.Click+=(_,_)=>action();
        if (close) b.PointerEntered+=(_,_)=>b.Background=Palette.Brush("#903F31");
        if (close) b.PointerExited+=(_,_)=>b.Background=Palette.Brush("#1B120F");
        return b;
    }
    private static Border SpellIcon(string key,int size=56)
    {
        var image=IconPack.Create(key,size);
        return new Border { Width=size,Height=size,CornerRadius=new CornerRadius(9),
            Background=Palette.Brush("#38251E"), ClipToBounds=true,
            BorderBrush=Palette.Brush("#795239"), BorderThickness=new Thickness(1),
            Child=image };
    }
    private Border Page(string title,string subtitle,Control content,string? back=null,Action? backAction=null)
    {
        var contentStack=Stack(spacing:20);
        contentStack.Margin = new Thickness(28,24,28,35);
        if(back is not null && backAction is not null)
            contentStack.Children.Add(Action("← "+back,backAction));
        contentStack.Children.Add(Text(title,30,"#F6ECDD",FontWeight.Bold));
        contentStack.Children.Add(Text(subtitle,13,"#B6A296"));
        contentStack.Children.Add(content);
        return new Border { MaxWidth=1600,HorizontalAlignment=HAlign.Center,
            Child=contentStack,Width=double.NaN };
    }
    private void Go(Control page) => rootBody.Child=page;
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
            var labels=Stack(spacing:3);labels.Children.Add(Text("LAST USED",11,"#EFAE56",FontWeight.Bold));
            labels.Children.Add(Text(lastSpec.Name+"  ·  "+selection.Name,20,"#FFFFFF",FontWeight.SemiBold));
            labels.Children.Add(Text("Your previous specialization · Start requires an installed XML rotation",12,"#C8ADA0"));
            Grid.SetColumn(labels,1);last.Children.Add(labels);
            var b=Action("Start",()=>RequestStart(selection,lastSpec),true);b.VerticalAlignment=VerticalAlignment.Center;

            Grid.SetColumn(b,2);last.Children.Add(b);
            wrap.Children.Add(Pane(last,"#332319"));
        }
        else
        {
            var top=Stack(Orientation.Horizontal,10);top.Children.Add(Text("●",12,"#EFB15A"));
            top.Children.Add(Text("Choose a class to browse its specializations",14,"#D7B49C"));
            wrap.Children.Add(Pane(top,"#302015"));
        }
        wrap.Children.Add(Text("CLASSES",15,"#E9B16F",FontWeight.Bold));
        // Viewbox scales both the five-column class layout and its icons uniformly.
        var board= new Grid { ColumnDefinitions=new ColumnDefinitions("*,*,*,*,*"),
             RowDefinitions=new RowDefinitions("Auto,Auto"), ColumnSpacing=13,RowSpacing=13 };
        for(int i=0;i<client.Classes.Length;i++)
        {
            var c=client.Classes[i];
            var tile=ClassTile(c);
            Grid.SetColumn(tile,i<5?i:i-5);Grid.SetRow(tile,i<5?0:1);
            board.Children.Add(tile);
        }
        var scaler=new Viewbox { Child=board,Stretch=Stretch.Uniform,StretchDirection=StretchDirection.Both,
            HorizontalAlignment=HAlign.Stretch };
        wrap.Children.Add(scaler);
        Go(Page("CLASSES & SPECS","WoW Forever · 9 classes · Select a class to explore its specializations",wrap));
    }
    private Control ClassTile(GameClass cls)
    {
        var body=Stack(spacing:10);
        body.HorizontalAlignment=HAlign.Center;
        body.Children.Add(SpellIcon(cls.Icon,73));
        body.Children.Add(Text(cls.Name,17,cls.Accent,FontWeight.Bold));
        body.Children.Add(Text("3 specializations",11,"#BBA699"));
        var open=Action("View specs",()=>ShowClass(cls),true);
        open.HorizontalAlignment=HAlign.Stretch;
        body.Children.Add(open);
        var pane=Pane(body,"#302219",12,"#654631",new Thickness(18,19));
        pane.Width=180;pane.MinHeight=180;
        pane.PointerPressed+=(_,e)=> { if(e.Source is not Button) ShowClass(cls); };
        return pane;
    }
    private void ShowClass(GameClass cls)
    {
        selectedClass=cls;selectedSpec=null;view="specs";
        var body=Stack(spacing:21);
        var intro=Stack(Orientation.Horizontal,14);
        intro.Children.Add(SpellIcon(cls.Icon,63));
        var txt=Stack(spacing:4);txt.Children.Add(Text(cls.Name,23,cls.Accent,FontWeight.Bold));
        txt.Children.Add(Text("Choose a specialization · PvE / PvP settings will follow the rotation XML",12,"#CDB7A7"));
        intro.Children.Add(txt);
        body.Children.Add(Pane(intro,"#332219"));
        var grid=new Grid { ColumnDefinitions=new ColumnDefinitions("*,*,*"),ColumnSpacing=17 };
        for(int i=0;i<cls.Specs.Length;i++)
        {
            var spec=cls.Specs[i];
            var p=Stack(spacing:16);p.HorizontalAlignment=HAlign.Center;
            p.Children.Add(SpellIcon(spec.Icon,90));
            p.Children.Add(Text(spec.Name,18,"#FFFFFF",FontWeight.Bold));
            p.Children.Add(Text("Rotation not installed",12,"#B9A399"));
            p.Children.Add(Action("Open",()=>ShowSpec(cls,spec),true,140));
            var box=Pane(p,"#2D1F18",12,"#624631",new Thickness(24,26));
            Grid.SetColumn(box,i);grid.Children.Add(box);
        }
        body.Children.Add(new Viewbox { Child=grid, Stretch=Stretch.Uniform, StretchDirection=StretchDirection.Both, HorizontalAlignment=HAlign.Stretch });
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
        top.Children.Add(identity);body.Children.Add(Pane(top,"#322219"));
        var blank=Stack(spacing:12);
        blank.Children.Add(Text("ROTATION SETTINGS",14,"#ECB66E",FontWeight.Bold));
        blank.Children.Add(Text("No rotation profile installed",21,"#F7EDE4",FontWeight.SemiBold));
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
            entries.Children.Add(Text(group.Item1,15,"#EFB56B",FontWeight.Bold));
            foreach(var label in group.Item2)
            {
                var row=new Grid { ColumnDefinitions=new ColumnDefinitions("*,Auto,Auto"),ColumnSpacing=20 };
                row.Children.Add(Text(label,14,"#F2E5DB"));
                var pve=Text("PvE · not configured",12,"#927C70");Grid.SetColumn(pve,1);row.Children.Add(pve);
                var pvp=Text("PvP · not configured",12,"#927C70");Grid.SetColumn(pvp,2);row.Children.Add(pvp);
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
        b.Children.Add(Text("SUPPORT",15,"#EFB56B",FontWeight.Bold));
        b.Children.Add(Text("LIVE RGB & APPLICATION DIAGNOSTICS",18,"#F7EDE4",FontWeight.Bold));
        b.Children.Add(Text("In-memory only · No screenshots, character names, keys or credentials are logged.",12,"#BDAA9D"));
        var actions=Stack(Orientation.Horizontal,9);
        actions.Children.Add(Action("Clear events",()=>{ RuntimeDiagnostics.Clear();RefreshDiagnosticsView(); }));
        actions.Children.Add(Action("Refresh",RefreshDiagnosticsView));
        b.Children.Add(actions);
        diagnosticsOutput=Text(RuntimeDiagnostics.Snapshot(),12,"#D8C6B9");
        diagnosticsOutput.FontFamily=new Avalonia.Media.FontFamily("Consolas");
        var diagnosticPanel=new ScrollViewer { Content=diagnosticsOutput, MaxHeight=440,
            VerticalScrollBarVisibility=ScrollBarVisibility.Auto };
        b.Children.Add(Pane(diagnosticPanel,"#171110",8,"#5F4232",new Thickness(16)));
        b.Children.Add(Text("RGB v2 / v3 CRC / Curve, window visibility, Setup and Overlay events appear here. Automatic rotation is not implemented.",12,"#BDAA9D"));
        Go(Page("SUPPORT","Local live status and event history",Pane(b)));
        RefreshDiagnosticsView();
    }
    private void RefreshDiagnosticsView()
    {
        if (view == "support" && diagnosticsOutput is not null)
            diagnosticsOutput.Text=RuntimeDiagnostics.Snapshot();
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
        content.Children.Add(Text("ROTATION NOT AVAILABLE",17,"#EAB36F",FontWeight.Bold));
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
        overlay=new OverlayWindow(()=>{
            var current=overlay;overlay=null;current?.Close();
            if(overlayButton is not null)overlayButton.Content="Overlay OFF";
            RuntimeDiagnostics.Add("OVERLAY","Closed by user");
        });
        overlay.Closed+=(_,_)=> {
            overlay=null;
            if(overlayButton is not null)overlayButton.Content="Overlay OFF";
        };
        overlay.Show();
        if(overlayButton is not null)overlayButton.Content="Overlay ON";
        RuntimeDiagnostics.Add("OVERLAY","Shown · topmost compact status window");
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
                bool ok=WowRgbBridge.TryReadCombined(out var state,out var packet,out var detail,out var v3,out var thresholds);
                return (ok,state,packet,detail,v3,thresholds);
            });
            if(finished)return;
            var connected=result.ok && result.state is not null;
            var crc=result.packet is not null;
            var curve=result.thresholds is not null;
            string now=connected?(curve?"RGB CONNECTED · CURVE":crc?"RGB CONNECTED · CRC PASS":"RGB CONNECTED"):"GAME NOT CONNECTED";
            statusText.Text=now;
            if(now != lastBridgeState)
            {
                RuntimeDiagnostics.Add("RGB",now+(connected?"":(" · "+result.detail)));
                lastBridgeState=now;
            }
            string probe=connected?(crc?result.v3:"No RGB v3 packet")+
                (curve?" · "+result.thresholds:" · Curve unavailable"):"No live game data";
            if(probe!=lastProbeState)
            {
                RuntimeDiagnostics.Add("PROBE",probe);
                lastProbeState=probe;
            }
            overlay?.SetConnection(connected,crc,curve);
            RefreshDiagnosticsView();
        }
        catch(Exception e)
        {
            statusText.Text="RGB CAPTURE ERROR";
            if(lastBridgeState!="RGB CAPTURE ERROR")
                RuntimeDiagnostics.Add("ERROR","RGB capture: "+e.GetType().Name);
            lastBridgeState="RGB CAPTURE ERROR";
        }
        finally{scanning=false;}
    }
}
