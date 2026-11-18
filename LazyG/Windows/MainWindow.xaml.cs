using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using System;
using Color = System.Windows.Media.Color;
using Brushes = System.Windows.Media.Brushes;
namespace LazyGPrototype;
public partial class MainWindow : Window
{
    private readonly System.Collections.Generic.List<(System.Windows.Controls.Button tab, UIElement page)> tabs;
    private readonly DispatcherTimer bridgeTimer = new() { Interval = TimeSpan.FromSeconds(3) };
    public MainWindow()
    {
        InitializeComponent();
        tabs = new() { (TabDashboard,DashboardPage),(TabSetup,SetupPage),(TabRotations,RotationsPage),
            (TabOverlay,OverlayPage),(TabSettings,SettingsPage),(TabAbout,AboutPage) };
        Select(TabDashboard, "Overview", "Status and quick access", DashboardPage);
        bridgeTimer.Tick += (_, _) => RefreshBridgeStatus();
        bridgeTimer.Start();
        Closed += (_, _) => bridgeTimer.Stop();
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
    private void RefreshBridgeStatus()
    {
        if (!WowRgbBridge.GameRunning())
        {
            ConnectionStatus.Text = "WoW window not detected";
            return;
        }

        if (WowRgbBridge.TryRead(out var state, out var detail) && state != null)
            ConnectionStatus.Text = $"RGB connected: {state.ClassName} · {state.RaceName} · level {state.Level} · {state.SpecName}";
        else if (!detail.StartsWith("Switch to WoW", StringComparison.Ordinal))
            ConnectionStatus.Text = "RGB disconnected: " + detail;
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
