using System.Diagnostics;
using Microsoft.Win32;

namespace ZcreSupporter;

public partial class App : Application
{
    private Mutex? single;
    private EventWaitHandle? showEvent;
    private RegisteredWaitHandle? wait;
    private CompanionStore? store;
    private DashboardWindow? dashboard;
    private PetWindow? pet;
    private TrayIcon? tray;
    private ServiceStatus? status;
    private Window? banner;
    private DispatcherTimer? bannerTimer;
    private DispatcherTimer? notificationTimer;
    private readonly List<Alert> pendingAlerts = [];
    private bool exiting;
    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        DispatcherUnhandledException += (_, error) => { error.Handled = true; MessageBox.Show("앱 동작을 마치지 못했어요. 계정 정보가 없는 진단을 설정에서 저장할 수 있습니다.\n오류 종류: " + error.Exception.GetType().Name, "ZCRE 서포터"); };
        single = new Mutex(true, @"Local\ZcreSupporter.Windows", out var first);
        if (!first) { try { using var existing = EventWaitHandle.OpenExisting(@"Local\ZcreSupporter.Show"); existing.Set(); } catch (WaitHandleCannotBeOpenedException) { } Shutdown(); return; }
        LocalData.Initialize(e.Args);
        showEvent = new(false, EventResetMode.AutoReset, @"Local\ZcreSupporter.Show");
        wait = ThreadPool.RegisterWaitForSingleObject(showEvent, (_, _) => Dispatcher.BeginInvoke(() => dashboard?.Present()), null, Timeout.Infinite, false);
        try
        {
            store = new(); status = new(); dashboard = new(store, status); MainWindow = dashboard;
            pet = new(store); pet.DashboardRequested += dashboard.Present; pet.SettingsRequested += dashboard.ShowSettings; pet.ToolRequested += path => DashboardWindow.OpenWeb("https://www.zcre.co.kr" + path);
            dashboard.ResetPetRequested += () => { store.Preferences.PetX = store.Preferences.PetY = null; pet.RestorePosition(); store.SavePreferences(); }; dashboard.MotionTestsRequested += pet.ShowMotionTests;
            tray = new(store) { IsDebugWorking = () => pet.DebugWorking }; tray.Open += dashboard.Present; tray.OpenSettings += dashboard.ShowSettings; tray.OpenAlerts += dashboard.ShowDetails; tray.Exit += ExitApp;
            notificationTimer = new() { Interval = TimeSpan.FromMilliseconds(150) };
            notificationTimer.Tick += (_, _) =>
            {
                notificationTimer.Stop(); if (pendingAlerts.Count == 0) return;
                var batch = pendingAlerts.ToArray(); pendingAlerts.Clear();
                if (store.FocusActive || store.IsSleeping) return;
                var alert = batch.Length == 1 ? batch[0] : new Alert(Guid.NewGuid().ToString(), "completed", batch.Length + "개의 작업 알림", string.Join(" · ", batch.Select(a => a.Title)), DateTimeOffset.Now, false, "notification", null);
                if (!store.IsDemo) store.SetNotificationStatus(tray.Notify(alert, store.Preferences.NotificationSound));
                if (!store.Preferences.PetVisible && store.Preferences.BannerAlerts) ShowBanner(alert);
            };
            store.AlertRaised += alert => { pendingAlerts.Add(alert); notificationTimer.Stop(); notificationTimer.Start(); };
            store.ResetAlerts += () => { pendingAlerts.Clear(); notificationTimer.Stop(); banner?.Close(); tray.ClearNotification(); };
            SystemEvents.PowerModeChanged += PowerChanged; SystemEvents.SessionSwitch += SessionChanged;
            pet.Show();
            if (!e.Args.Contains("--background") && (!store.Preferences.HasLaunched || e.Args.Contains("--demo") || e.Args.Contains("--show-dashboard"))) dashboard.Present();
            store.Preferences.HasLaunched = true; store.SavePreferences();
            await store.StartAsync(e.Args.Contains("--demo"));
            if (e.Args.Contains("--connect") && !store.IsDemo) await store.ConnectAsync();
            if (e.Args.Contains("--demo") && e.Args.Contains("--render-proof"))
            {
                await Task.Delay(500); dashboard.UpdateLayout();
                var bitmap = new System.Windows.Media.Imaging.RenderTargetBitmap((int)dashboard.ActualWidth, (int)dashboard.ActualHeight, 96, 96, PixelFormats.Pbgra32); bitmap.Render(dashboard);
                var encoder = new System.Windows.Media.Imaging.PngBitmapEncoder(); encoder.Frames.Add(System.Windows.Media.Imaging.BitmapFrame.Create(bitmap)); using var file = File.Create(LocalData.PathFor("dashboard-demo.png")); encoder.Save(file);
                pet.UpdateLayout(); var petBitmap = new System.Windows.Media.Imaging.RenderTargetBitmap((int)pet.ActualWidth, (int)pet.ActualHeight, 96, 96, PixelFormats.Pbgra32); petBitmap.Render(pet); var petEncoder = new System.Windows.Media.Imaging.PngBitmapEncoder(); petEncoder.Frames.Add(System.Windows.Media.Imaging.BitmapFrame.Create(petBitmap)); using var petFile = File.Create(LocalData.PathFor("pet-demo.png")); petEncoder.Save(petFile);
            }
            if (e.Args.Contains("--smoke-test"))
            {
                var assertions = Sprites.Names.Select(name => new { name, frames = Sprites.Get(name).Frames.Length, duration = Sprites.Get(name).Duration }).ToArray();
                LocalData.Save("smoke.json", new { status = "passed", os = Environment.OSVersion.VersionString, pid = Environment.ProcessId, assertions, dashboard = dashboard.IsVisible, pet = pet.IsVisible, demo = store.IsDemo });
                await Task.Delay(2000); ExitApp();
            }
        }
        catch (Exception error) { MessageBox.Show("시작하지 못했어요. WebView2 런타임과 리소스를 확인해 주세요.\n오류 종류: " + error.GetType().Name, "ZCRE 서포터"); ExitApp(); }
    }
    private void PowerChanged(object sender, PowerModeChangedEventArgs e) => Dispatcher.BeginInvoke(() => { if (e.Mode == PowerModes.Suspend) { store?.Sleep(); status?.Pause(true); } else if (e.Mode == PowerModes.Resume) { store?.Wake(); status?.Pause(false); } });
    private void SessionChanged(object sender, SessionSwitchEventArgs e) => Dispatcher.BeginInvoke(() => { if (e.Reason == SessionSwitchReason.SessionLock) { store?.Sleep(); status?.Pause(true); } else if (e.Reason == SessionSwitchReason.SessionUnlock) { store?.Wake(); status?.Pause(false); } });
    private void ShowBanner(Alert alert)
    {
        banner?.Close(); bannerTimer?.Stop();
        var panel = new StackPanel(); panel.Children.Add(Ui.Text(alert.Title, 14, true)); panel.Children.Add(Ui.Text(alert.Body, 12));
        var work = SystemParameters.WorkArea;
        banner = new Window { Title = "ZCRE 알림", Width = 360, SizeToContent = SizeToContent.Height, Left = work.Right - 380, Top = work.Top + 20, WindowStyle = WindowStyle.None, AllowsTransparency = true, Background = Brushes.Transparent, ShowActivated = false, ShowInTaskbar = false, Topmost = true, Content = Ui.Card(panel) };
        banner.SourceInitialized += (_, _) => { var handle = new System.Windows.Interop.WindowInteropHelper(banner).Handle; NativeNoActivate(handle); };
        banner.MouseLeftButtonUp += (_, _) => { banner.Close(); dashboard?.ShowDetails(); };
        banner.Show(); bannerTimer = new() { Interval = TimeSpan.FromSeconds(8) }; bannerTimer.Tick += (_, _) => { bannerTimer.Stop(); banner?.Close(); }; bannerTimer.Start();
    }
    private static void NativeNoActivate(IntPtr handle) => SetWindowLongPtr(handle, -20, GetWindowLongPtr(handle, -20) | 0x08000000L);
    private void ExitApp()
    {
        if (exiting) return; exiting = true;
        SystemEvents.PowerModeChanged -= PowerChanged; SystemEvents.SessionSwitch -= SessionChanged;
        bannerTimer?.Stop(); notificationTimer?.Stop(); pendingAlerts.Clear(); banner?.Close(); pet?.Shutdown(); dashboard?.Shutdown(); tray?.Dispose(); status?.Dispose(); store?.Dispose();
        wait?.Unregister(null); showEvent?.Dispose(); Shutdown();
    }
    internal void Quit() => ExitApp();
    protected override void OnExit(ExitEventArgs e) { if (single is not null) { try { single.ReleaseMutex(); } catch (ApplicationException) { } single.Dispose(); } base.OnExit(e); }
    [System.Runtime.InteropServices.DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] private static extern long GetWindowLongPtr(IntPtr hwnd, int index);
    [System.Runtime.InteropServices.DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] private static extern long SetWindowLongPtr(IntPtr hwnd, int index, long value);
}
