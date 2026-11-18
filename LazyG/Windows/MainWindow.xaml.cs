using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using System;
using System.Threading.Tasks;
using Color = System.Windows.Media.Color;
using Brushes = System.Windows.Media.Brushes;
namespace LazyGPrototype;
public partial class MainWindow : Window
{
    private readonly System.Collections.Generic.List<(System.Windows.Controls.Button tab, UIElement page)> tabs;
    // UI diagnostics only. Rotation processing will use its own pipeline when implemented.
    private readonly DispatcherTimer bridgeTimer = new() { Interval = TimeSpan.FromMilliseconds(150) };
    private bool bridgeReadInProgress;
    private bool closing;
    public MainWindow()
    {
        InitializeComponent();
        tabs = new() { (TabDashboard,DashboardPage),(TabSetup,SetupPage),(TabRotations,RotationsPage),
            (TabOverlay,OverlayPage),(TabSettings,SettingsPage),(TabAbout,AboutPage) };
        Select(TabDashboard, "Overview", "Status and quick access", DashboardPage);
        bridgeTimer.Tick += async (_, _) => await RefreshBridgeStatusAsync();
        bridgeTimer.Start();
        Closed += (_, _) => { closing = true; bridgeTimer.Stop(); };
    }
    private void Select(System.Windows.Controls.Button active, string title, string subtitle, UIElement page)
    {
        PageTitle.Text = title;
        PageSubtitle.Text = subtitle;
        foreach(var (tab, view) in tabs)
        {
            view.Visibility = ReferenceEquals(view,page) ? Visibility.Visible : Visibility.Collapsed;
            tab.BorderBrush = ReferenceEquals(tab,active) ? new SolidColorBrush(Color.FromRgb(244,155,59)) : Brushes.Transparent;
            tab.Foreground = ReferenceEquals(tab,active) ? new SolidColorBrush(Color.FromRgb(255,184,112)) : new SolidColorBrush(Color.FromRgb(224,209,200));
        }
    }
    private void Dashboard_Click(object sender,RoutedEventArgs e) => Select(TabDashboard,"Overview","Status and quick access",DashboardPage);
    private void SetupTab_Click(object sender,RoutedEventArgs e) => Select(TabSetup,"Setup","AddOn installation and RGB calibration",SetupPage);
    private void Rotations_Click(object sender,RoutedEventArgs e) => Select(TabRotations,"Rotations","Profiles and specialization selection (preview)",RotationsPage);
    private void Overlay_Click(object sender,RoutedEventArgs e) => Select(TabOverlay,"Overlay","Movement modes and calibration (preview)",OverlayPage);
    private void Settings_Click(object sender,RoutedEventArgs e) => Select(TabSettings,"Settings","Application configuration",SettingsPage);
    private void About_Click(object sender,RoutedEventArgs e) => Select(TabAbout,"About","Independent LazyG project",AboutPage);
    private void Stationary_Click(object sender,RoutedEventArgs e)
    {
        MovementModeText.Text = "Preview mode: stationary only";
        StationaryButton.Background = new SolidColorBrush(Color.FromRgb(225,138,50));
        MovingButton.Background = new SolidColorBrush(Color.FromRgb(52,43,39));
    }
    private void Moving_Click(object sender,RoutedEventArgs e)
    {
        MovementModeText.Text = "Preview mode: moving allowed";
        MovingButton.Background = new SolidColorBrush(Color.FromRgb(225,138,50));
        StationaryButton.Background = new SolidColorBrush(Color.FromRgb(52,43,39));
    }
    private async Task RefreshBridgeStatusAsync()
    {
        // Skip overlapping polls if a screen capture takes longer than the interval.
        if (bridgeReadInProgress || closing) return;
        bridgeReadInProgress = true;
        try
        {
            // Screen capture and RGB decoding are blocking GDI operations.
            // Keep them off the WPF dispatcher thread.
            var result = await Task.Run(() =>
            {
                bool ok = WowRgbBridge.TryReadCombined(out var state, out var telemetry, out var detail, out var v3Detail);
                return (ok, state, telemetry, detail, v3Detail);
            });
            if (closing) return;
            if (result.ok && result.state != null)
            {
                var state = result.state;
                ConnectionStatus.Text = $"RGB v2: {state.ClassName} · {state.RaceName} · lvl {state.Level} · {state.SpecName} · target {(state.TargetExists ? "yes" : "no")} · hostile {(state.TargetHostile ? "yes" : "no")} · alive {(state.TargetAlive ? "yes" : "no")} · combat {(state.InCombat ? "yes" : "no")}";
                if (result.telemetry is RgbV3Packet extra)
                {
                    string hp = extra.PlayerHealth <= 100 ? extra.PlayerHealth + "%" : "unknown";
                    string targetHp = extra.TargetHealth <= 100 ? extra.TargetHealth + "%" : "unknown";
                    var kind = extra.GetCell(9).R;
                    var max = extra.GetCell(10);
                    int powerMax = (max.R << 8) | max.G;
                    string resource = kind < 255 && powerMax > 0
                        ? $"{extra.PlayerPower}/{powerMax} (type {kind})" : "unknown";
                    ConnectionStatus.Text += $" | RGB v3 CRC PASS · frame {extra.FrameCounter} · HP {hp} · target HP {targetHp} · resource {resource}";
                }
                else
                    ConnectionStatus.Text += " | RGB v3: pending (install new addon to test)";
            }
            else if (!result.detail.StartsWith("Switch to WoW", StringComparison.Ordinal))
                ConnectionStatus.Text = "RGB disconnected: " + result.detail;
        }
        catch (Exception ex)
        {
            if (!closing) ConnectionStatus.Text = "RGB diagnostic error: " + ex.Message;
        }
        finally
        {
            bridgeReadInProgress = false;
        }
    }

    private void Setup_Click(object sender,RoutedEventArgs e)
    {
        // The wizard is deliberately not owned by the main window:
        // hiding an owner can also hide its owned modal windows in WPF.
        var wizard = new SetupWizard { WindowStartupLocation = WindowStartupLocation.CenterScreen };
        Hide();
        try
        {
            wizard.ShowDialog();
            if(wizard.Installed) SetupStatus.Text = $"Addon installed: {wizard.InstalledName}";
            if(wizard.ConnectionPassed) ConnectionStatus.Text = "RGB connected: " + wizard.PlayerSummary;
            else if(wizard.Installed) ConnectionStatus.Text = "Addon installed; RGB connection pending";
        }
        finally { Show(); Activate(); }
    }
}
