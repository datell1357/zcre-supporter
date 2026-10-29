using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using ZcreSupporter;

internal static class TrayChecks
{
    internal static int Run(string directory)
    {
        if (!Path.IsPathFullyQualified(directory) || Directory.Exists(directory)) throw new ArgumentException();
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        app.Resources["BackgroundBrush"] = new SolidColorBrush(Color.FromRgb(17, 18, 20));
        app.Startup += async (_, _) =>
        {
            DashboardWindow? dashboard = null;
            try
            {
                LocalData.Initialize(["--data-dir", directory]);
                using var store = new CompanionStore(); using var status = new ServiceStatus();
                using var tray = new TrayIcon(store);
                for (var attempt = 0; attempt < 50; attempt++) { tray.Anchor(); if (tray.HasIconRectangle) break; await Task.Delay(100); }
                dashboard = new(store, status) { PopupAnchor = tray.Anchor }; dashboard.Present();
                if (dashboard.WindowStyle != WindowStyle.None || dashboard.ShowInTaskbar || dashboard.ResizeMode != ResizeMode.NoResize)
                    throw new InvalidOperationException("Tray dashboard must have no native caption, resize frame or taskbar button. Actual=" + dashboard.WindowStyle);
                Console.WriteLine("PASS actual WPF dashboard has no title bar, resize frame or taskbar button");
                var handle = new WindowInteropHelper(dashboard).Handle;
                if ((GetWindowLongPtr(handle, -16).ToInt64() & 0x00C00000) != 0) throw new InvalidOperationException("Native WS_CAPTION remained set.");
                var anchor = tray.Anchor(); var expected = ZcreSupporter.Core.TrayPopupPlacement.Place(anchor);
                if (!tray.HasIconRectangle) throw new InvalidOperationException("Shell did not expose the registered tray icon rectangle; cursor fallback cannot certify tray anchoring. Registered=" + tray.Registered + "; HRESULT=" + tray.IconRectangleResult.ToString("X8"));
                if (!GetWindowRect(handle, out var actual) || Math.Abs(actual.Left - expected.X) > 2 || Math.Abs(actual.Top - expected.Y) > 2 || Math.Abs(actual.Right - actual.Left - expected.Width) > 2 || Math.Abs(actual.Bottom - actual.Top - expected.Height) > 2)
                    throw new InvalidOperationException("Actual HWND rectangle differs from the tray placement.");
                Console.WriteLine("PASS Shell tray anchor and actual HWND placement: " + ZcreSupporter.Core.TrayPopupPlacement.Edge(anchor) + " / scale=" + anchor.Scale + " / HRESULT=" + tray.IconRectangleResult.ToString("X8") + " / popup=" + expected);
                var other = new Window { Title = "Isolated popup dismissal test", Width = 200, Height = 120 };
                other.Show(); other.Activate(); await app.Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle);
                if (dashboard.IsVisible) throw new InvalidOperationException("Dashboard stayed open after a different normal window became active.");
                other.Close(); dashboard.Present();
                Console.WriteLine("PASS actual activation of another WPF window dismisses the popup");
                dashboard.ShowSettings();
                var settings = app.Windows.Cast<Window>().Single(w => w.Title == "ZCRE 서포터 · 설정");
                if (dashboard.IsVisible || !settings.IsVisible || settings.WindowStyle != WindowStyle.SingleBorderWindow) throw new InvalidOperationException("Independent settings window was hidden or lost its normal chrome.");
                if (!GetWindowRect(new WindowInteropHelper(settings).Handle, out var settingsRect)) throw new InvalidOperationException("Settings frame bounds are unavailable.");
                var settingsArea = TrayPopupHost.ForIcon(new(settingsRect.Left, settingsRect.Top, 1, 1)).WorkArea;
                if (!settingsArea.Contains(new(settingsRect.Left, settingsRect.Top, settingsRect.Right - settingsRect.Left, settingsRect.Bottom - settingsRect.Top))) throw new InvalidOperationException("Settings frame extends outside its monitor work area.");
                await store.StartAsync(true); settings.UpdateLayout();
                if (Buttons(dashboard).Any(b => Equals(b.Content, "ZCRE 계정 연결") && b.Visibility != Visibility.Collapsed)) throw new InvalidOperationException("Verified snapshot still displayed the initial account-connection prompt.");
                if (!Buttons(settings).Any(b => Equals(b.Content, "미리보기 종료"))) throw new InvalidOperationException("Open settings did not update its demo action after a state transition.");
                var demoButton = Buttons(settings).Single(b => Equals(b.Content, "미리보기 종료"));
                if (System.Windows.Automation.Peers.UIElementAutomationPeer.CreatePeerForElement(demoButton)?.GetName() != "미리보기 종료") throw new InvalidOperationException("Dynamic action retained a stale accessibility name after its visible label changed.");
                settings.Close(); dashboard.Present(); dashboard.ShowDetails();
                var detail = app.Windows.Cast<Window>().Single(w => w.Title == "ZCRE 서포터 · 상세 현황");
                if (dashboard.IsVisible || !detail.IsVisible || detail.WindowStyle != WindowStyle.SingleBorderWindow) throw new InvalidOperationException("Independent detail window was hidden or lost its normal chrome.");
                Console.WriteLine("PASS opening settings/details dismisses only the popup and preserves normal child-window chrome");
                if (!tray.Notify(new("tray-qa", "completed", "ZCRE 로컬 알림 검사", "격리된 Windows 검증입니다. 생성 요청과 크레딧 사용이 없습니다.", DateTimeOffset.Now, false, "notification", null), false)) throw new InvalidOperationException("Shell rejected the local notification request.");
                Console.WriteLine("PASS Windows Shell accepted a local no-sound notification; banner visibility is not asserted");
                app.Shutdown(0);
            }
            catch (Exception error) { Console.WriteLine("FAIL native tray popup: " + error.GetType().Name + ": " + error.Message); app.Shutdown(1); }
            finally { dashboard?.Shutdown(); }
        };
        return app.Run();
    }
    [StructLayout(LayoutKind.Sequential)] private struct NativeRect { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] private static extern IntPtr GetWindowLongPtr(IntPtr hwnd, int index);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hwnd, out NativeRect rect);
    private static IEnumerable<System.Windows.Controls.Button> Buttons(DependencyObject root)
    {
        if (root is System.Windows.Controls.Button button) yield return button;
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++)
            foreach (var child in Buttons(VisualTreeHelper.GetChild(root, i))) yield return child;
    }
}
