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
                foreach (var edge in Enum.GetValues<ZcreSupporter.Core.TaskbarEdge>())
                {
                    var offset = TrayPopupHost.EntranceOffset(edge, true);
                    if (offset.Length != 16 || TrayPopupHost.EntranceOffset(edge, false) != new Vector()) throw new InvalidOperationException("Tray entrance lost its reduced-motion path.");
                    if (edge == ZcreSupporter.Core.TaskbarEdge.Bottom && offset.Y <= 0 || edge == ZcreSupporter.Core.TaskbarEdge.Top && offset.Y >= 0 || edge == ZcreSupporter.Core.TaskbarEdge.Left && offset.X >= 0 || edge == ZcreSupporter.Core.TaskbarEdge.Right && offset.X <= 0) throw new InvalidOperationException("Tray entrance moves toward the taskbar.");
                }
                await Task.Delay(220);
                var content = (UIElement)dashboard.Content;
                if (content.Opacity != 1 || content.RenderTransform is TranslateTransform t && (Math.Abs(t.X) > .01 || Math.Abs(t.Y) > .01)) throw new InvalidOperationException($"Tray entrance did not settle to its final layout: opacity={content.Opacity}, transform={content.RenderTransform}, visible={dashboard.IsVisible}.");
                dashboard.Hide(); dashboard.Present(); dashboard.Present();
                if (content.Opacity != 1 || content.RenderTransform is TranslateTransform repeated && (Math.Abs(repeated.X) > .01 || Math.Abs(repeated.Y) > .01)) throw new InvalidOperationException("Repeated tray presentation retained an in-progress entrance.");
                Console.WriteLine("PASS 160ms tray content entrance settles; repeated presentation clears animation; all taskbar directions and reduced-motion offsets preserved; native frame stays in work area");
                var other = new Window { Title = "Isolated popup dismissal test", Width = 200, Height = 120 };
                other.Show(); other.Activate(); await app.Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle);
                if (dashboard.IsVisible) throw new InvalidOperationException("Dashboard stayed open after a different normal window became active.");
                other.Close(); dashboard.Present();
                Console.WriteLine("PASS actual activation of another WPF window dismisses the popup");
                dashboard.ShowSettings();
                var settings = app.Windows.Cast<Window>().Single(w => w.Title == "ZCRE 서포터 · 설정");
                if (dashboard.IsVisible || !settings.IsVisible || settings.WindowStyle != WindowStyle.None || settings.AllowsTransparency) throw new InvalidOperationException("Settings must use themed chrome without a native title bar or transparent capture surface.");
                if (!GetWindowRect(new WindowInteropHelper(settings).Handle, out var settingsRect)) throw new InvalidOperationException("Settings frame bounds are unavailable.");
                var settingsArea = TrayPopupHost.ForIcon(new(settingsRect.Left, settingsRect.Top, 1, 1)).WorkArea;
                if (!settingsArea.Contains(new(settingsRect.Left, settingsRect.Top, settingsRect.Right - settingsRect.Left, settingsRect.Bottom - settingsRect.Top))) throw new InvalidOperationException("Settings frame extends outside its monitor work area.");
                var settingsHandle = new WindowInteropHelper(settings).Handle;
                if (HitTest(settingsHandle, settingsRect.Left + 100, settingsRect.Top + 24) != 2) throw new InvalidOperationException("The themed settings header is not a native draggable caption.");
                var close = Buttons(settings).Single(b => System.Windows.Automation.AutomationProperties.GetAutomationId(b) == "SettingsClose");
                var closePoint = close.PointToScreen(new Point(close.ActualWidth / 2, close.ActualHeight / 2));
                if (HitTest(settingsHandle, (int)closePoint.X, (int)closePoint.Y) != 1 || !close.Focusable || string.IsNullOrEmpty(System.Windows.Automation.Peers.UIElementAutomationPeer.CreatePeerForElement(close)?.GetName())) throw new InvalidOperationException("Settings close button is not an accessible client-area control.");
                settings.Height = 360; settings.UpdateLayout();
                var scroll = Descendants(settings).OfType<System.Windows.Controls.ScrollViewer>().First(); scroll.ScrollToEnd();
                await app.Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle);
                if (scroll.ScrollableHeight <= 0 || scroll.VerticalOffset <= 0 || close.TranslatePoint(new Point(0, 0), settings).Y > 52) throw new InvalidOperationException("Compact settings lost content scrolling or its fixed close control.");
                Console.WriteLine("PASS themed settings header exposes native caption dragging, accessible close and compact content scrolling");
                await SettingsScrollChecks.Run(scroll);
                await store.StartAsync(true); settings.UpdateLayout();
                if (Buttons(dashboard).Any(b => Equals(b.Content, "ZCRE 계정 연결") && b.Visibility != Visibility.Collapsed)) throw new InvalidOperationException("Verified snapshot still displayed the initial account-connection prompt.");
                if (!Buttons(settings).Any(b => Equals(b.Content, "미리보기 종료"))) throw new InvalidOperationException("Open settings did not update its demo action after a state transition.");
                var demoButton = Buttons(settings).Single(b => Equals(b.Content, "미리보기 종료"));
                if (System.Windows.Automation.Peers.UIElementAutomationPeer.CreatePeerForElement(demoButton)?.GetName() != "미리보기 종료") throw new InvalidOperationException("Dynamic action retained a stale accessibility name after its visible label changed.");
                close.RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Button.ClickEvent));
                if (settings.IsVisible) throw new InvalidOperationException("The themed close action did not close settings.");
                dashboard.Present(); dashboard.ShowDetails();
                var detail = app.Windows.Cast<Window>().Single(w => w.Title == "ZCRE 서포터 · 상세 현황");
                if (dashboard.IsVisible || !detail.IsVisible || detail.WindowStyle != WindowStyle.SingleBorderWindow) throw new InvalidOperationException("Independent detail window was hidden or lost its normal chrome.");
                Console.WriteLine("PASS settings close action and independent normal detail window preserve popup dismissal behavior");
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
    [DllImport("user32.dll")] private static extern IntPtr SendMessage(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);
    private static int HitTest(IntPtr handle, int x, int y) => SendMessage(handle, 0x84, IntPtr.Zero, new IntPtr((y << 16) | (x & 0xffff))).ToInt32();
    private static IEnumerable<DependencyObject> Descendants(DependencyObject root)
    {
        yield return root;
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++)
            foreach (var child in Descendants(VisualTreeHelper.GetChild(root, i))) yield return child;
    }
    private static IEnumerable<System.Windows.Controls.Button> Buttons(DependencyObject root) => Descendants(root).OfType<System.Windows.Controls.Button>();
}
