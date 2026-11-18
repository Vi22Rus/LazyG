using System;
using System.Drawing;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using Forms = System.Windows.Forms;
namespace LazyGPrototype;
public partial class SetupWizard : Window
{
    private int step;
    private Rectangle? region;
    public bool Installed {get;private set;}
    public bool ConnectionPassed {get;private set;}
    public string InstalledName {get;private set;}="";
    public SetupWizard(){InitializeComponent();ShowStep();}
    private void Browse_Click(object sender,RoutedEventArgs e)
    {
        using var picker=new Forms.FolderBrowserDialog{Description="Select your World of Warcraft Interface\\AddOns directory",ShowNewFolderButton=false};
        if(picker.ShowDialog()==Forms.DialogResult.OK) FolderText.Text=picker.SelectedPath;
    }
    private void ShowStep()
    {
        string[] titles={"Choose AddOns directory","Name the addon","Install RGB addon","Launch WoW","Place and select RGB panel","Connection Test"};
        var panels=new UIElement[]{PathPanel,NamePanel,InstallPanel,GamePanel,DragPanel,TestPanel};
        for(int i=0;i<panels.Length;i++) panels[i].Visibility=i==step?Visibility.Visible:Visibility.Collapsed;
        StepLabel.Text=$"Step {step+1} / 6";StepTitle.Text=titles[step];
        BackButton.IsEnabled=step>0 && !Installed;
        NextButton.Content=step==2?"Install":step==5?"Finish":"Next";
        if(step==2) InstallSummary.Text=$"Destination: {System.IO.Path.Combine(FolderText.Text,AddonName.Text)}";
    }
    private void Next_Click(object sender,RoutedEventArgs e)
    {
        if(step==0 && (!Directory.Exists(FolderText.Text) || !string.Equals(Path.GetFileName(FolderText.Text.TrimEnd('\\','/')),"AddOns",StringComparison.OrdinalIgnoreCase)))
        { System.Windows.MessageBox.Show(this,"Select an existing folder named AddOns.","Setup",MessageBoxButton.OK,MessageBoxImage.Warning); return; }
        if(step==1 && !ValidConfig())return;
        if(step==2 && !Install())return;
        if(step==3 && !CheckGameRunning())return;
        if(step==4 && region is null){System.Windows.MessageBox.Show(this,"Select the RGB region first.");return;}
        if(step==5){DialogResult=ConnectionPassed;Close();return;}
        step++;ShowStep();
    }
    private bool ValidConfig()
    {
        if(!Regex.IsMatch(AddonName.Text,@"^[A-Za-z][A-Za-z0-9_]{2,39}$") || !Regex.IsMatch(SelectedInterfaceNumber(),@"^[0-9]{4,7}$"))
        {System.Windows.MessageBox.Show(this,"Use a unique addon name (3–40 Latin letters/digits/_), and select a client version or enter a valid custom Interface number.");return false;}
        string[] reserved={"WeakAuras","Details","DBM","BigWigs","ElvUI","WarMate","PeonSlayer"};
        if(reserved.Contains(AddonName.Text,StringComparer.OrdinalIgnoreCase))
        {System.Windows.MessageBox.Show(this,"Please choose a unique name that does not impersonate another addon.");return false;}
        return true;
    }
    private bool Install()
    {
        if(!ValidConfig())return false;
        var dir=Path.Combine(FolderText.Text,AddonName.Text);
        if(Directory.Exists(dir)){System.Windows.MessageBox.Show(this,"The addon directory already exists. No files were changed. Choose another name.");return false;}
        try
        {
            Directory.CreateDirectory(dir);
            try
            {
                File.WriteAllText(Path.Combine(dir,AddonName.Text+".toc"),$"## Interface: {SelectedInterfaceNumber()}\n## Title: {AddonName.Text}\n## Notes: RGB panel for setup and connection diagnostics\n## Version: 0.1.9-dev\n## SavedVariables: LazyGPixelPanelDB\nPanel.lua\nHunterProfile.lua\n",new UTF8Encoding(false));
                // Embedded addon is maintained as our own source, no WarMate assets.
                File.WriteAllText(Path.Combine(dir,"Panel.lua"),AddonTemplate.PanelLua,new UTF8Encoding(false));
                File.WriteAllText(Path.Combine(dir,"HunterProfile.lua"),AddonTemplate.HunterProfileLua,new UTF8Encoding(false));
            }
            catch{Directory.Delete(dir,true);throw;}
            Installed=true;InstalledName=AddonName.Text;return true;
        }
        catch(Exception ex){System.Windows.MessageBox.Show(this,"Installation failed: "+ex.Message);return false;}
    }
    private string SelectedInterfaceNumber()
    {
        if(ClientVersion.SelectedItem is ComboBoxItem item)
        {
            var value = item.Tag?.ToString() ?? "";
            return value == "custom" ? InterfaceNumber.Text.Trim() : value;
        }
        return "";
    }
    private void ClientVersion_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if(CustomInterfacePanel == null || ClientVersion == null) return;
        CustomInterfacePanel.Visibility = (ClientVersion.SelectedItem as ComboBoxItem)?.Tag?.ToString() == "custom"
            ? Visibility.Visible : Visibility.Collapsed;
    }
    private static readonly string[] WowProcessNames = { "Wow", "WowClassic", "WowB", "Wow-64", "WowClassicT" };
    private static Process? FindWowProcess()
    {
        foreach(var name in WowProcessNames)
        {
            try
            {
                var matches = Process.GetProcessesByName(name);
                foreach(var p in matches)
                {
                    if(!p.HasExited && p.MainWindowHandle != IntPtr.Zero) return p;
                    p.Dispose();
                }
            }
            catch (System.ComponentModel.Win32Exception) { }
            catch (InvalidOperationException) { }
        }
        return null;
    }
    private bool CheckGameRunning()
    {
        using var process = FindWowProcess();
        if(process == null)
        {
            GameCheckText.Text = "WoW not found. Launch the game, then press Next again.";
            System.Windows.MessageBox.Show(this,"WoW window not found. Launch a client and try again. No process ID is saved.", "Setup", MessageBoxButton.OK, MessageBoxImage.Information);
            return false;
        }
        GameCheckText.Text = "WoW found. Continue to panel placement.";
        return true;
    }
    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    private static void BringGameToFront()
    {
        using var process = FindWowProcess();
        if(process == null) return;
        ShowWindow(process.MainWindowHandle, 9); // SW_RESTORE
        SetForegroundWindow(process.MainWindowHandle);
    }
    private async void ShowGame_Click(object sender,RoutedEventArgs e)
    {
        if(!CheckGameRunning()) return;
        // Unlike capture, placement is user-driven: minimize the wizard so the
        // user can restore it from the taskbar after dragging the panel in WoW.
        ShowInTaskbar = true;
        WindowState = WindowState.Minimized;
        await Task.Delay(230);
        BringGameToFront();
    }
    private async void SelectRegion_Click(object sender,RoutedEventArgs e)
    {
        if(!CheckGameRunning()) return;
        // Minimize instead of Hide: hiding a ShowDialog window can end its modal loop.
        WindowState = WindowState.Minimized;
        try
        {
            await Task.Delay(250);
            BringGameToFront();
            await Task.Delay(150);
            var selector = new RegionSelector();
            if(selector.ShowDialog() == true)
            {
                region = selector.SelectedRegion;
                ConnectionPassed = false;
                RegionText.Text = $"Region: X={region.Value.X}, Y={region.Value.Y}, W={region.Value.Width}, H={region.Value.Height}";
                step = 5;
                ShowStep();
                await CaptureRegionAsync();
            }
        }
        catch(Exception ex)
        {
            TestResult.Text = "Region selection error: " + ex.Message;
        }
        finally { WindowState = WindowState.Normal; Activate(); }
    }
    private void Reselect_Click(object sender,RoutedEventArgs e)
    {
        ConnectionPassed=false;
        region=null;
        step=4;
        ShowStep();
    }
    private async void Test_Click(object sender,RoutedEventArgs e)
    {
        if(region is null){TestResult.Text="No region selected";return;}
        WindowState = WindowState.Minimized;
        try { await CaptureRegionAsync(); }
        finally { WindowState = WindowState.Normal; Activate(); }
    }
    private async Task CaptureRegionAsync()
    {
        ConnectionPassed = false;
        if(region is null){TestResult.Text="No region selected";return;}
        var r=region.Value;
        if(r.Width<40 || r.Height<3 || r.Width>2500 || r.Height>350)
        {
            TestResult.Text="FAIL — select the whole compact RGB bar (you may include a small margin).";
            return;
        }
        try
        {
            await Task.Delay(230);
            BringGameToFront();
            await Task.Delay(270);
            using var image=new Bitmap(r.Width,r.Height);
            using(var g=Graphics.FromImage(image))
                g.CopyFromScreen(r.Left,r.Top,0,0,new System.Drawing.Size(r.Width,r.Height));
            ConnectionPassed = RgbPanelDetector.FindPanel(image, out var detail);
            TestResult.Text=ConnectionPassed
                ? "PASS — compact RGB markers found. " + detail
                : "FAIL — full calibration pattern not found. " + detail;
        }
        catch(Exception ex){TestResult.Text="Capture error: "+ex.Message;}
    }
    private void Back_Click(object sender,RoutedEventArgs e){if(step>0 && !Installed){step--;ShowStep();}}
    private void Cancel_Click(object sender,RoutedEventArgs e){Close();}
}
