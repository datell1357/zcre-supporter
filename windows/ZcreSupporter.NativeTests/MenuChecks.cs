using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Runtime.InteropServices;
using System.Windows.Interop;
using ZcreSupporter;

internal static class MenuChecks
{
    internal static int Interactive(string directory)
    {
        if (!Path.IsPathFullyQualified(directory) || Directory.Exists(directory)) throw new ArgumentException();
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        app.Startup += async (_, _) =>
        {
            LocalData.Initialize(["--data-dir", directory]);
            using var store = new CompanionStore();
            store.Preferences.Roaming = false;
            await store.StartAsync(true);
            var pet = new PetWindow(store); pet.Show(); pet.Left = 900; pet.Top = 360;
            var state = new TextBlock { Margin = new Thickness(20), FontSize = 18 };
            var panel = new StackPanel { Background = Brushes.White };
            var host = new Window { Title = "ZCRE radial menu isolated QA", Left = 100, Top = 100, Width = 1200, Height = 800, Content = panel };
            var open = new Button { Content = "Open menu without activation", Width = 300, Height = 45, Margin = new Thickness(20) };
            open.Click += (_, _) => { pet.ShowMenu("home"); state.Text = "Menu opened"; };
            panel.Children.Add(open); panel.Children.Add(state);
            panel.Children.Add(new TextBlock { Text = "Blank area: outside menu click. Pet/menu are the actual product windows. All data is synthetic; no generation.", Margin = new Thickness(20) });
            var quit = new Button { Content = "Finish isolated QA", Width = 220, Height = 45, Margin = new Thickness(20) };
            quit.Click += (_, _) => host.Close(); panel.Children.Add(quit);
            var outsideClicks = 0;
            var outside = new Window { Title = "Nonactivating outside click target", Left = 250, Top = 550, Width = 300, Height = 150, WindowStyle = WindowStyle.None, ShowActivated = false, ShowInTaskbar = false, Topmost = true, Background = Brushes.LightBlue, Content = new TextBlock { Text = "Outside target: does not take focus", Margin = new Thickness(20) } };
            outside.SourceInitialized += (_, _) =>
            {
                var handle = new WindowInteropHelper(outside).Handle;
                SetWindowLongPtr(handle, -20, GetWindowLongPtr(handle, -20) | 0x08000000L);
                HwndSource.FromHwnd(handle).AddHook((IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled) =>
                {
                    if (message != 0x21) return IntPtr.Zero;
                    handled = true; return new IntPtr(3); // MA_NOACTIVATE, while still delivering the click.
                });
            };
            outside.MouseDown += (_, _) => outsideClicks++;
            string? requested = null; pet.ToolRequested += route => requested = route;
            var timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(100) };
            timer.Tick += (_, _) => state.Text = $"Menu windows: {app.Windows.Cast<Window>().Count(w => w.Title == "지크 원형 메뉴")} / active: {app.Windows.Cast<Window>().Where(w => w.IsActive).Select(w => w.Title).FirstOrDefault()} / route: {requested ?? "none"}\nPet: {pet.Left:F0},{pet.Top:F0} / outside clicks: {outsideClicks}";
            timer.Start();
            host.Closed += (_, _) => { timer.Stop(); outside.Close(); pet.Shutdown(); app.Shutdown(); };
            host.Show(); outside.Show();
            await Task.Delay(Timeout.Infinite);
        };
        return app.Run();
    }

    internal static int Run(string directory)
    {
        if (!Path.IsPathFullyQualified(directory) || Directory.Exists(directory)) throw new ArgumentException();
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        app.Startup += async (_, _) =>
        {
            PetWindow? pet = null;
            try
            {
                LocalData.Initialize(["--data-dir", directory]);
                using var store = new CompanionStore();
                pet = new PetWindow(store); pet.Show(); await Task.Delay(250);
                pet.ShowMenu("home"); await Task.Delay(100);
                var connect = Buttons(app).SingleOrDefault(b => Equals(b.Content, "ZCRE 연결"));
                if (connect is null || !connect.IsVisible) throw new InvalidOperationException("Disconnected radial summary omitted its account connection action.");
                var summary = Window.GetWindow(connect);
                if (summary.ActualHeight > 104) throw new InvalidOperationException("Disconnected radial summary exceeds its reserved frame.");
                await store.StartAsync(true); await Task.Delay(100);
                if (connect.IsVisible) throw new InvalidOperationException("Connected radial summary retained its login action.");
                pet.CloseMenu();
                var image = Descendants(pet).OfType<Image>().Single(); var transform = image.RenderTransform;
                await Task.Delay(250);
                if (!ReferenceEquals(transform, image.RenderTransform)) throw new InvalidOperationException("Pet rebuilt its transform graph on subsequent animation frames.");
                Console.WriteLine("PASS actual animated pet reuses its transform graph across frames");
                pet.ShowMenu("home"); await Task.Delay(250);
                var windows = app.Windows.Cast<Window>().Where(w => w.Title == "지크 원형 메뉴").ToArray();
                if (windows.Length != 7 || windows.Any(w => !w.IsVisible)) throw new InvalidOperationException("Expected summary and six visible menu actions, including canvas; actual windows=" + windows.Length);
                if (!pet.HasMenuMouseListener) throw new InvalidOperationException("Open radial menu has no outside-click listener.");
                pet.MenuPointerDown(new WindowInteropHelper(pet).Handle);
                foreach (var window in windows) pet.MenuPointerDown(new WindowInteropHelper(window).Handle);
                await app.Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle);
                if (!pet.HasMenuMouseListener || windows.Any(w => !w.IsVisible)) throw new InvalidOperationException("Pet or menu pointer target dismissed the menu.");
                CheckVisuals(windows);
                var texts = windows.SelectMany(Descendants).OfType<TextBlock>().ToArray();
                var credit = texts.Single(t => t.Text.StartsWith("사용 가능 "));
                var counts = texts.Single(t => t.Text.StartsWith("이미지 "));
                var beforeCredit = credit.Text; var beforeCounts = counts.Text;
                if (!beforeCredit.Contains("1,160") || !beforeCounts.EndsWith("합계 2/4")) throw new InvalidOperationException("Radial summary omitted the available total concurrency limit.");
                store.Sleep(); await Task.Delay(100);
                if (!credit.Text.StartsWith("갱신 지연")) throw new InvalidOperationException("Paused radial summary presented its cached credits as fresh.");
                store.Wake(); await Task.Delay(100);
                if (!credit.Text.StartsWith("사용 가능")) throw new InvalidOperationException("Radial summary did not recover its normal credit presentation.");
                Console.WriteLine("PASS disconnected radial summary has a reachable connection action; demo connection updates it in place; paused credits visibly show their stale state");
                store.SimulateCompletion(); await Task.Delay(250);
                if (!credit.Text.Contains("1,240") || !counts.Text.EndsWith("합계 1/4") || windows.Any(w => !w.IsVisible) || app.Windows.Cast<Window>().Count(w => w.Title == "지크 원형 메뉴") != 7) throw new InvalidOperationException();
                var outside = new Window { Title = "Isolated menu dismissal test", Width = 200, Height = 120 };
                outside.Show(); outside.Activate(); await app.Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle);
                if (app.Windows.Cast<Window>().Any(w => w.Title == "지크 원형 메뉴")) throw new InvalidOperationException("Radial menu did not close after outside activation.");
                outside.Close(); pet.ShowMenu("home");
                if (!pet.HasMenuMouseListener) throw new InvalidOperationException("Reopened radial menu did not restart its listener.");
                using (var target = new HwndSource(new HwndSourceParameters("Nonactivating outside target") { Width = 10, Height = 10 }))
                {
                    pet.MenuPointerDown(target.Handle);
                    await app.Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle);
                    if (pet.HasMenuMouseListener || app.Windows.Cast<Window>().Any(w => w.Title == "지크 원형 메뉴")) throw new InvalidOperationException("Pointer target outside the menu did not dismiss it without an activation event.");
                    pet.ShowMenu("home");
                    pet.MenuPointerDown(target.Handle); pet.ShowMenu("image");
                    await app.Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle);
                    if (!pet.HasMenuMouseListener || Buttons(app).Length != 8) throw new InvalidOperationException("Deferred outside click dismissed a replacement submenu.");
                    pet.CloseMenu();
                    if (pet.HasMenuMouseListener) throw new InvalidOperationException("Explicit close retained the outside-click listener.");
                }
                Console.WriteLine("PASS native hook starts on open; pet/menu targets are excluded; foreign target dismisses without activation; stale callbacks cannot close replacement menu; close releases hook");
                pet.ShowMenu("home");
                var canvas = Buttons(app).Single(b => System.Windows.Automation.AutomationProperties.GetName(b) == "캔버스");
                string? requested = null; pet.ToolRequested += path => requested = path;
                canvas.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                if (requested != "/studio/canvas" || app.Windows.Cast<Window>().Any(w => w.Title == "지크 원형 메뉴")) throw new InvalidOperationException("Canvas action did not close the menu and request its official route.");
                Console.WriteLine("PASS six WPF radial-menu actions and summary; original TextBlocks update in place; outside activation dismisses; canvas requests official route without generation");
                Console.WriteLine("Synthetic demo before: " + beforeCredit + " / " + beforeCounts);
                Console.WriteLine("Synthetic demo after: " + credit.Text + " / " + counts.Text);
                foreach (var (category, routes) in new[]
                {
                    ("home", new[] { ("주짓수", "/studio/jiujitsu"), ("오디오", "/studio/audio"), ("캔버스", "/studio/canvas") }),
                    ("image", new[] { ("이미지 생성", "/studio/image"), ("캐릭터 시트", "/studio/character-sheet"), ("부분 수정", "/studio/partial-edit"), ("배경 제거", "/studio/image?tool=background-removal"), ("고화질 변환", "/studio/image?tool=upscale"), ("크기 변환", "/studio/image?tool=resize") }),
                    ("video", new[] { ("영상 생성", "/studio/video"), ("고화질 변환", "/studio/image?tool=upscale&media=video"), ("프레임 보간", "/studio/frame-interpolation"), ("영상 번역", "/studio/video-translate") })
                })
                {
                    pet.ShowMenu("home");
                    if (category != "home") Buttons(app).Single(b => System.Windows.Automation.AutomationProperties.GetName(b) == (category == "image" ? "이미지" : "영상")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                    await app.Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle);
                    if (Buttons(app).Length != (category == "image" ? 8 : 6)) throw new InvalidOperationException("Category navigation lost an action.");
                    CheckVisuals(app.Windows.Cast<Window>().Where(w => w.Title == "지크 원형 메뉴").ToArray());
                    if (category != "home")
                    {
                        Buttons(app).Single(b => System.Windows.Automation.AutomationProperties.GetName(b) == "뒤로").RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                        if (!Buttons(app).Any(b => System.Windows.Automation.AutomationProperties.GetName(b) == "이미지")) throw new InvalidOperationException("Back did not restore the home menu.");
                    }
                    Buttons(app).Single(b => System.Windows.Automation.AutomationProperties.GetName(b) == "닫기").RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                    if (Buttons(app).Length != 0) throw new InvalidOperationException("Close left a menu action open.");
                    foreach (var (name, path) in routes)
                    {
                        pet.ShowMenu(category); requested = null;
                        Buttons(app).Single(b => System.Windows.Automation.AutomationProperties.GetName(b) == name).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                        if (requested != path || Buttons(app).Length != 0) throw new InvalidOperationException("A tool action lost its official route or menu dismissal.");
                    }
                }
                Console.WriteLine("PASS all 20 home/image/video actions have visible vector icons, unclipped labels and accessible names; category/back/close and all 13 tool routes preserved without opening the web or generating media");
                pet.ShowMenu("home"); var stoppedPet = pet; pet.Shutdown(); pet = null;
                if (stoppedPet.HasMenuMouseListener) throw new InvalidOperationException("Shutdown retained the outside-click listener.");
                Console.WriteLine("PASS pet shutdown releases the outside-click listener");
                app.Shutdown(0);
            }
            catch (Exception error) { Console.WriteLine("FAIL native radial menu: " + error.GetType().Name + ": " + error.Message); app.Shutdown(1); }
            finally { pet?.Shutdown(); }
        };
        return app.Run();
    }

    private static void CheckVisuals(Window[] windows)
    {
        foreach (var button in windows.SelectMany(Descendants).OfType<Button>().Where(b => b.IsVisible))
        {
            var icon = Descendants(button).OfType<Image>().SingleOrDefault();
            if (icon?.Source is not DrawingImage drawing || icon.ActualWidth != 16 || icon.ActualHeight != 16) throw new InvalidOperationException("A radial action is missing its visible 16 DIP vector icon.");
            if (drawing.Drawing is not DrawingGroup group || group.Children.OfType<GeometryDrawing>().Last().Geometry.Bounds.IsEmpty) throw new InvalidOperationException("A radial icon contains no vector geometry.");
            var title = Descendants(button).OfType<TextBlock>().Single();
            var name = new System.Windows.Automation.Peers.ButtonAutomationPeer(button).GetName();
            if (name != title.Text.Replace("\n", " ") || !Equals(button.ToolTip, name)) throw new InvalidOperationException("A radial action lost its accessible name or tooltip.");
            var frame = new Rect(new Point(), button.RenderSize);
            var iconFrame = icon.TransformToAncestor(button).TransformBounds(new Rect(new Point(), icon.RenderSize));
            var textFrame = title.TransformToAncestor(button).TransformBounds(new Rect(new Point(), title.RenderSize));
            if (!frame.Contains(iconFrame) || !frame.Contains(textFrame) || iconFrame.IntersectsWith(textFrame)) throw new InvalidOperationException("A radial icon and title overlap or leave the button.");
            foreach (var line in title.Text.Split('\n'))
            {
                var measured = new FormattedText(line, System.Globalization.CultureInfo.CurrentUICulture, title.FlowDirection, new Typeface(title.FontFamily, title.FontStyle, title.FontWeight, title.FontStretch), title.FontSize, title.Foreground, VisualTreeHelper.GetDpi(title).PixelsPerDip);
                if (measured.WidthIncludingTrailingWhitespace > title.ActualWidth || measured.Height > title.LineHeight || title.Text.Split('\n').Length * title.LineHeight > title.ActualHeight) throw new InvalidOperationException($"A radial title is clipped: {name}, line {measured.WidthIncludingTrailingWhitespace}x{measured.Height}, label {title.ActualWidth}x{title.ActualHeight}.");
            }
        }
    }

    private static Button[] Buttons(Application app) => app.Windows.Cast<Window>().Where(w => w.Title == "지크 원형 메뉴").SelectMany(Descendants).OfType<Button>().Where(b => b.IsVisible).ToArray();

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] private static extern long GetWindowLongPtr(IntPtr hwnd, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] private static extern long SetWindowLongPtr(IntPtr hwnd, int index, long value);

    private static IEnumerable<DependencyObject> Descendants(DependencyObject root)
    {
        yield return root;
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++)
            foreach (var child in Descendants(VisualTreeHelper.GetChild(root, i))) yield return child;
    }
}
