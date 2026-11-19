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
    public string PlayerSummary { get; private set; } = "";
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
        string[] titles={"Choose AddOns directory","Name the addon","Install RGB addon","Launch WoW","Automatic RGB connection"};
        var panels=new UIElement[]{PathPanel,NamePanel,InstallPanel,GamePanel,TestPanel};
        for(int i=0;i<panels.Length;i++) panels[i].Visibility=i==step?Visibility.Visible:Visibility.Collapsed;
        StepLabel.Text=$"Step {step+1} / 5";StepTitle.Text=titles[step];
        BackButton.IsEnabled=step>0 && !Installed;
        NextButton.Content=step==2?"Install":step==4?"Finish":"Next";
        if(step==2) InstallSummary.Text=$"Destination: {System.IO.Path.Combine(FolderText.Text,AddonName.Text)}";
    }
    private async void Next_Click(object sender,RoutedEventArgs e)
    {
        if(step==0 && (!Directory.Exists(FolderText.Text) || !string.Equals(Path.GetFileName(FolderText.Text.TrimEnd('\\','/')),"AddOns",StringComparison.OrdinalIgnoreCase)))
        { System.Windows.MessageBox.Show(this,"Select an existing folder named AddOns.","Setup",MessageBoxButton.OK,MessageBoxImage.Warning); return; }
        if(step==1 && !ValidConfig())return;
        if(step==2 && !Install())return;
        if(step==3 && !CheckGameRunning())return;
        if(step==4)
        {
            if(!ConnectionPassed)
            {
                System.Windows.MessageBox.Show(this, "RGB connection not confirmed. Check the installed addon in WoW and run the test again.");
                return;
            }
            DialogResult=true;
            Close();
            return;
        }
        step++;
        ShowStep();
        if(step==4) await RunConnectionTestAsync();
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
                File.WriteAllText(Path.Combine(dir,AddonName.Text+".toc"),$"## Interface: {SelectedInterfaceNumber()}\n## Title: {AddonName.Text}\n## Notes: RGB Bridge v2 for WoW Forever\n## Version: 0.1.19-dev\nHunterProfile.lua\nPanel.lua\nRgbV3Encoder.lua\nHunterCompactManifest.lua\nHunterCompactProfileEncoder.lua\nHunterCompactCollector.lua\nRgbV3Panel.lua\nRgbV3Thresholds.lua\n",new UTF8Encoding(false));
                // Embedded addon is maintained as our own source, no WarMate assets.
                File.WriteAllText(Path.Combine(dir,"Panel.lua"),AddonTemplate.PanelLua,new UTF8Encoding(false));
                File.WriteAllText(Path.Combine(dir,"HunterProfile.lua"),AddonTemplate.HunterProfileLua,new UTF8Encoding(false));
                File.WriteAllText(Path.Combine(dir,"RgbV3Encoder.lua"),AddonTemplate.ReadEmbeddedLua("RgbV3Encoder.lua"),new UTF8Encoding(false));
                foreach(var module in new[]{"HunterCompactManifest.lua","HunterCompactProfileEncoder.lua","HunterCompactCollector.lua"})
                    File.WriteAllText(Path.Combine(dir,module),AddonTemplate.ReadEmbeddedLua(module),new UTF8Encoding(false));
                File.WriteAllText(Path.Combine(dir,"RgbV3Panel.lua"),AddonTemplate.ReadEmbeddedLua("RgbV3Panel.lua"),new UTF8Encoding(false));
                File.WriteAllText(Path.Combine(dir,"RgbV3Thresholds.lua"),AddonTemplate.ReadEmbeddedLua("RgbV3Thresholds.lua"),new UTF8Encoding(false));
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
        GameCheckText.Text = "WoW found. Continue to automatic RGB verification.";
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
    private async void Test_Click(object sender, RoutedEventArgs e)
    {
        await RunConnectionTestAsync();
    }

    private async Task RunConnectionTestAsync()
    {
        ConnectionPassed = false;
        PlayerSummary = "";
        TestResult.Text = "Checking the automatic RGB connection...";
        WindowState = WindowState.Minimized;
        try
        {
            WowRgbBridge.ActivateGame();
            await Task.Delay(550);
            ConnectionPassed = WowRgbBridge.TryRead(out var player, out var detail);
            if (ConnectionPassed && player != null)
            {
                PlayerSummary = $"{player.ClassName} · {player.RaceName} · Level {player.Level} · {player.SpecName}";
                TestResult.Text = "PASS — " + PlayerSummary + "\n" + detail + "\n" + $"Target: {(player.TargetExists ? "yes" : "no")} | Hostile: {(player.TargetHostile ? "yes" : "no")} | Alive: {(player.TargetAlive ? "yes" : "no")} | Combat: {(player.InCombat ? "yes" : "no")}";
            }
            else
                TestResult.Text = "FAIL — " + detail;
        }
        finally
        {
            WindowState = WindowState.Normal;
            Activate();
        }
    }
    private void Back_Click(object sender,RoutedEventArgs e){if(step>0 && !Installed){step--;ShowStep();}}
    private void Cancel_Click(object sender,RoutedEventArgs e){Close();}
}
