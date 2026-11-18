using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Platform.Storage;
using LazyGPrototype;
using Control = Avalonia.Controls.Control;
using Button = Avalonia.Controls.Button;
using TextBox = Avalonia.Controls.TextBox;
using ComboBox = Avalonia.Controls.ComboBox;
using Orientation = Avalonia.Layout.Orientation;
using HAlign = Avalonia.Layout.HorizontalAlignment;

namespace LazyG.Desktop;

internal sealed class SetupDialog : Window
{
    private readonly UserSession session;
    private readonly ComboBox versions = new() { MinWidth=315 };
    private readonly TextBox addOns = new() { Watermark=".../World of Warcraft/_forever_/Interface/AddOns",MinWidth=410 };
    private readonly TextBox addonName = new() { Text="LazyGForever",MinWidth=200 };
    private readonly TextBlock status = new() { TextWrapping=TextWrapping.Wrap };
    private readonly Button install;
    private readonly Button test;
    private readonly Button finish;
    private bool installed;
    private bool validated;
    public bool SetupCompleted { get; private set; }
    public SetupDialog(UserSession session)
    {
        this.session=session;
        Title="LazyG · Setup";
        Width=710;Height=570;MinWidth=670;MinHeight=530;
        Background=Palette.Background;Foreground=Palette.White;
        SystemDecorations=SystemDecorations.None;
        WindowStartupLocation=WindowStartupLocation.CenterScreen;
        versions.ItemsSource=ClientCatalog.Clients.Select(x=>x.Name+(x.Available?"":"  ·  COMING LATER")).ToArray();
        versions.SelectedIndex=0;
        addOns.Text=session.ForeverAddonsPath;
        install=Act("Install AddOn",()=>Install(),true);
        test=Act("Test RGB",()=>_ = TestAsync());
        finish=Act("Finish",()=> { if(validated){ session.LastClient="forever";session.ForeverConfigured=true;session.Save();SetupCompleted=true;Close(); } },true);
        test.IsEnabled=false;finish.IsEnabled=false;
        Content=Build();
    }
    private static TextBlock T(string text,int size=13,string color="#EADCD0",bool bold=false) =>
        new() { Text=text,FontSize=size,Foreground=Palette.Brush(color),
            FontWeight=bold?FontWeight.Bold:FontWeight.Normal,TextWrapping=TextWrapping.Wrap };
    private static Button Act(string text,Action action,bool primary=false)
    {
        var b=new Button {Content=new TextBlock { Text=text, FontSize=13, FontWeight=FontWeight.SemiBold, VerticalAlignment=VerticalAlignment.Center, TextAlignment=TextAlignment.Center },MinHeight=42,Padding=new Thickness(22,8),VerticalContentAlignment=VerticalAlignment.Center,Background=Palette.Brush(primary?"#E5A34B":"#37271E"),
            Foreground=Palette.Brush(primary?"#281B11":"#F8E9DB"),CornerRadius=new CornerRadius(8),
            BorderBrush=Palette.Brush(primary?"#F6C46D":"#694A35"),BorderThickness=new Thickness(1)};
        b.Click+=(_,_)=>action();return b;
    }
    private Control Build()
    {
        var root=new Grid { RowDefinitions=new RowDefinitions("52,*,94") };
        var top=new Grid {ColumnDefinitions=new ColumnDefinitions("*,Auto"),Background=Palette.Brush("#241710")};
        top.PointerPressed+=(_,e)=> { if(e.GetCurrentPoint(top).Properties.IsLeftButtonPressed && e.Source is not Button) BeginMoveDrag(e); };
        var title=T("  LazyG   /   SETUP",19,"#F0BA70",true); title.VerticalAlignment=VerticalAlignment.Center;top.Children.Add(title);
        var x=Act("×",Close);Grid.SetColumn(x,1);top.Children.Add(x);
        root.Children.Add(top);
        var form=new StackPanel { Margin=new Thickness(32,24,32,20),Spacing=12 };
        form.Children.Add(T("Connect your WoW client",26,"#FFFFFF",true));
        form.Children.Add(T("Client profile",13,"#E6B47D",true));
        form.Children.Add(versions);
        form.Children.Add(T("Only Forever is implemented in this dev build. Other client profiles cannot be installed yet.",12,"#C4AD9F"));
        form.Children.Add(T("Interface / AddOns folder",13,"#E6B47D",true));
        var folderRow=new Grid { ColumnDefinitions=new ColumnDefinitions("*,Auto"),ColumnSpacing=10 };
        folderRow.Children.Add(addOns);
        var browse=Act("Browse",()=>_ = BrowseAsync());Grid.SetColumn(browse,1);folderRow.Children.Add(browse);
        form.Children.Add(folderRow);
        form.Children.Add(T("Addon folder name",13,"#E6B47D",true));
        form.Children.Add(addonName);
        form.Children.Add(T("The installer creates a new folder and never overwrites another addon. Disable older test LazyG addons before /reload.",12,"#C4AD9F"));
        form.Children.Add(new Border { Child=status,Background=Palette.Brush("#302019"),Padding=new Thickness(14),
            CornerRadius=new CornerRadius(8),MinHeight=66 });
        status.Text="Select WoW Forever, choose its AddOns folder, and install.";
        status.Foreground=Palette.Brush("#CFB09B");
        Grid.SetRow(form,1);
        var scroller=new ScrollViewer { Content=form,VerticalScrollBarVisibility=Avalonia.Controls.Primitives.ScrollBarVisibility.Auto };
        Grid.SetRow(scroller,1);
        root.Children.Add(scroller);
        var actions=new StackPanel { Orientation=Orientation.Horizontal,Spacing=12,
            HorizontalAlignment=HAlign.Right,VerticalAlignment=VerticalAlignment.Center,Margin=new Thickness(24,12,30,18) };
        actions.Children.Add(install);actions.Children.Add(test);actions.Children.Add(finish);
        Grid.SetRow(actions,2);root.Children.Add(actions);
        return root;
    }
    private async Task BrowseAsync()
    {
        var folders=await StorageProvider.OpenFolderPickerAsync(new Avalonia.Platform.Storage.FolderPickerOpenOptions
        {Title="Select the Interface/AddOns folder",AllowMultiple=false});
        if(folders.Count!=0 && folders[0].TryGetLocalPath() is { } path)
            addOns.Text=path;
    }
    private void Install()
    {
        validated=false;finish.IsEnabled=false;test.IsEnabled=false;
        if(versions.SelectedIndex!=0) { Failure("That WoW client is not supported yet.");return; }
        var path=(addOns.Text??"").Trim();
        var name=(addonName.Text??"").Trim();
        if(!Directory.Exists(path) || !string.Equals(Path.GetFileName(path.TrimEnd(Path.DirectorySeparatorChar,Path.AltDirectorySeparatorChar)), "AddOns",StringComparison.OrdinalIgnoreCase))
        {Failure("Please select an existing folder named AddOns.");return;}
        if(!Regex.IsMatch(name,"^[A-Za-z][A-Za-z0-9_]{2,39}$"))
        {Failure("Addon name must contain 3–40 Latin letters, digits or underscores.");return;}
        string[] banned={"WeakAuras","Details","DBM","BigWigs","ElvUI","WarMate","PeonSlayer"};
        if(banned.Contains(name,StringComparer.OrdinalIgnoreCase))
        {Failure("Choose an independent addon name.");return;}
        var target=Path.Combine(path,name);
        if(Directory.Exists(target)) { Failure("Folder already exists. Use another addon name; existing files were not modified.");return;}
        try
        {
            Directory.CreateDirectory(target);
            try
            {
                var toc=$"## Interface: 16001\n## Title: {name}\n## Notes: LazyG Forever RGB adapter\n## Version: 0.2.1-dev\nHunterProfile.lua\nPanel.lua\nRgbV3Encoder.lua\nRgbV3Panel.lua\nRgbV3Thresholds.lua\n";
                File.WriteAllText(Path.Combine(target,name+".toc"),toc,new UTF8Encoding(false));
                foreach(var f in new[]{"HunterProfile.lua","Panel.lua","RgbV3Encoder.lua","RgbV3Panel.lua","RgbV3Thresholds.lua"})
                {
                    using var src=typeof(SetupDialog).Assembly.GetManifestResourceStream("LazyG."+f)
                        ?? throw new FileNotFoundException("Embedded addon missing: "+f);
                    using var dest=File.Create(Path.Combine(target,f));
                    src.CopyTo(dest);
                }
            }
            catch { Directory.Delete(target,true);throw; }
            installed=true;session.ForeverAddonsPath=path;session.Save();
            RuntimeDiagnostics.Add("SETUP","Forever addon installed in a new directory");
            status.Text="Addon installed: "+target+"\nEnable it in WoW, disable older test addons, then /reload and click Test RGB.";
            status.Foreground=Palette.Brush("#92D09D");test.IsEnabled=true;
        }
        catch(Exception ex) { Failure("Installation failed: "+ex.Message); }
    }
    private async Task TestAsync()
    {
        test.IsEnabled=false;status.Text="Checking WoW RGB connection. Keep the game visible.";
        try
        {
            WowRgbBridge.ActivateGame();
            await Task.Delay(650);
            var result=await Task.Run(()=> {
                bool ok=WowRgbBridge.TryReadCombined(out var player,out var packet,out var detail,out var v3,out var curve);
                return (ok,player,packet,detail,v3,curve);
            });
            if(result.ok && result.player is not null)
            {
                validated=true;
                RuntimeDiagnostics.Add("SETUP","RGB test PASS · "+result.player.ClassName);
                status.Foreground=Palette.Brush("#97DDA4");
                status.Text="RGB PASS · "+result.player.ClassName+" / "+result.player.RaceName+
                    " · Lv "+result.player.Level+"\n"+(result.packet is null?"RGB v3 not detected":result.v3)+
                    (result.curve is null?" · Curve not detected":" · Curve detected");
                finish.IsEnabled=true;
            }
            else Failure("RGB not confirmed: "+result.detail);
        }
        catch(Exception e){Failure("Test failed: "+e.Message);}
        finally{test.IsEnabled=installed;}
    }
    private void Failure(string message){status.Text=message;status.Foreground=Palette.Brush("#F4A092");RuntimeDiagnostics.Add("SETUP","Setup validation failed");}
}
