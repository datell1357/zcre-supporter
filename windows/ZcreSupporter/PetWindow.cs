using System.Runtime.InteropServices;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media.Imaging;

namespace ZcreSupporter;

internal sealed class PetWindow : Window
{
    private readonly CompanionStore store;
    private readonly Canvas canvas = new() { Background = Brushes.Transparent };
    private readonly Image image = new() { Stretch = Stretch.Fill, Cursor = Cursors.Hand };
    private readonly TextBlock label = new() { TextAlignment = TextAlignment.Center, FontSize = 11, Foreground = Brushes.White };
    private readonly TextBlock bubbleText = new() { FontSize = 14, Foreground = Brushes.White, TextAlignment = TextAlignment.Center };
    private readonly Border bubble;
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(1d / 24) };
    private readonly IdleWaveSchedule waveSchedule = new();
    private double? waveStarted;
    private readonly PetAudio audio = new();
    private readonly List<Window> menuWindows = [];
    private Window? motionTests;
    private TextBlock? motionStatus;
    private double? lastTestDistance;
    private TextBlock? menuCreditText, menuCountText;
    private string motion = "idle";
    private double motionStarted = CompanionStore.Uptime, nextWalk, lastTick = CompanionStore.Uptime;
    private Point? destination, pressed;
    private Point testOrigin;
    private int direction;
    private bool dragging, mirrored, shuttingDown;
    private double turningX;
    private string? testMotion;
    private int? testDirection;
    private double testUntil;
    public event Action? DashboardRequested;
    public event Action? SettingsRequested;
    public event Action<string>? ToolRequested;
    public bool DebugWorking => testMotion == "working" && CompanionStore.Uptime < testUntil;
    public PetWindow(CompanionStore store)
    {
        this.store = store;
        Title = "ZCRE 지크"; Width = 280; Height = 265; AllowsTransparency = true; Background = Brushes.Transparent; WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize; ShowInTaskbar = false; Topmost = true; ShowActivated = false;
        Content = canvas; canvas.Children.Add(image); canvas.Children.Add(label);
        bubble = new Border { Background = new SolidColorBrush(Color.FromRgb(33, 36, 42)), BorderBrush = Brushes.DimGray, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(12), Padding = new Thickness(10), Width = 252, Child = bubbleText, IsHitTestVisible = false };
        canvas.Children.Add(bubble); Canvas.SetLeft(bubble, 14); Canvas.SetTop(bubble, 4); bubble.Visibility = Visibility.Collapsed;
        Canvas.SetTop(label, 230); Canvas.SetLeft(label, 35); label.Width = 210;
        image.MouseLeftButtonDown += Down; image.MouseMove += Move; image.MouseLeftButtonUp += Up;
        image.MouseRightButtonUp += (_, _) => ContextMenu = BuildContextMenu();
        image.ContextMenuOpening += (_, _) => image.ContextMenu = BuildContextMenu(); image.ContextMenu = BuildContextMenu();
        timer.Tick += (_, _) => Tick();
        store.Changed += Refresh;
        Loaded += (_, _) => { RestorePosition(); Refresh(); };
        SourceInitialized += (_, _) => { var hwnd = new WindowInteropHelper(this).Handle; SetWindowLongPtr(hwnd, -20, GetWindowLongPtr(hwnd, -20) | 0x08000000L); };
        Closing += (_, e) => { if (!shuttingDown) { e.Cancel = true; store.Preferences.PetVisible = false; store.SavePreferences(); } };
        Microsoft.Win32.SystemEvents.DisplaySettingsChanged += DisplayChanged;
    }
    private void DisplayChanged(object? sender, EventArgs e) => Dispatcher.BeginInvoke(RestoreIfLost);
    private Rect ScreenBounds()
    {
        var screen = System.Windows.Forms.Screen.FromHandle(new WindowInteropHelper(this).Handle).WorkingArea;
        var dpi = VisualTreeHelper.GetDpi(this);
        return new(screen.X / dpi.DpiScaleX, screen.Y / dpi.DpiScaleY, screen.Width / dpi.DpiScaleX, screen.Height / dpi.DpiScaleY);
    }
    public void RestorePosition()
    {
        var bounds = ScreenBounds(); Left = store.Preferences.PetX ?? bounds.Right - Width - 80; Top = store.Preferences.PetY ?? bounds.Bottom - Height - 20; RestoreIfLost();
    }
    private void RestoreIfLost()
    {
        var dpi = VisualTreeHelper.GetDpi(this);
        var visible = new System.Drawing.Rectangle((int)((Left + 95) * dpi.DpiScaleX), (int)((Top + 100) * dpi.DpiScaleY), (int)(90 * dpi.DpiScaleX), (int)(120 * dpi.DpiScaleY));
        if (System.Windows.Forms.Screen.AllScreens.Any(s => s.WorkingArea.IntersectsWith(visible))) return;
        var bounds = ScreenBounds(); Left = bounds.Right - Width - 60; Top = bounds.Bottom - Height;
    }
    private void Refresh()
    {
        UpdateMenuSummary();
        if (!store.DebugEnabled)
        {
            if (testMotion is not null) StopTest();
            if (motionTests is not null) { var old = motionTests; motionTests = null; old.Close(); }
        }
        var visible = store.Preferences.PetVisible;
        if (!visible) { Hide(); timer.Stop(); audio.Stop(); waveSchedule.Delay(CompanionStore.Uptime, false, false, .5); waveStarted = null; CloseMenu(); return; }
        if (!IsVisible) Show();
        if (store.IsSleeping) { timer.Stop(); audio.Stop(); return; }
        lastTick = CompanionStore.Uptime; timer.Start(); Tick();
    }
    private Point CursorPoint()
    {
        GetCursorPos(out var p); return new(p.X, p.Y);
    }
    private void Down(object sender, MouseButtonEventArgs e)
    {
        CloseMenu(); StopTest(); pressed = CursorPoint(); dragging = false; image.CaptureMouse(); e.Handled = true;
    }
    private void Move(object sender, MouseEventArgs e)
    {
        if (pressed is null || e.LeftButton != MouseButtonState.Pressed) return;
        var cursor = CursorPoint();
        if (!dragging && (cursor - pressed.Value).Length < 4) return;
        if (!dragging) { dragging = true; destination = null; turningX = cursor.X; SetMotion("drag"); }
        turningX = mirrored ? Math.Min(turningX, cursor.X) : Math.Max(turningX, cursor.X);
        if ((mirrored ? cursor.X - turningX : turningX - cursor.X) >= 8) { mirrored = !mirrored; turningX = cursor.X; }
        PositionAtScruff(cursor); e.Handled = true;
    }
    private void PositionAtScruff(Point cursor)
    {
        var clip = Sprites.Get("drag"); var frame = SpriteTiming.Frame(CompanionStore.Uptime - motionStarted, clip.Frames.Length, clip.Delay, clip.Loop);
        var anchor = clip.GrabAnchor(frame); var scale = 108.5 * store.Preferences.PetScale / clip.BodyHeight * clip.GrabScale(frame);
        var x = mirrored ? clip.Frames[0].PixelWidth - anchor.X : anchor.X;
        var dpi = VisualTreeHelper.GetDpi(this);
        var offsetX = ((Width - clip.Frames[0].PixelWidth * scale) / 2 + x * scale) * dpi.DpiScaleX;
        var offsetY = (223 - clip.Frames[0].PixelHeight * scale + anchor.Y * scale) * dpi.DpiScaleY;
        SetWindowPos(new WindowInteropHelper(this).Handle, IntPtr.Zero, (int)Math.Round(cursor.X - offsetX), (int)Math.Round(cursor.Y - offsetY), 0, 0, 0x1 | 0x4 | 0x10);
    }
    private void Up(object sender, MouseButtonEventArgs e)
    {
        image.ReleaseMouseCapture(); var wasDrag = dragging; pressed = null; dragging = false;
        if (wasDrag) { store.Preferences.PetX = Left; store.Preferences.PetY = Top; store.SavePreferences(); nextWalk = CompanionStore.Uptime + 4; }
        else ShowMenu("home");
        e.Handled = true;
    }
    private void SetMotion(string next) { if (motion == next) return; motion = next; motionStarted = CompanionStore.Uptime; }
    private static Point Vector(int value) => new(Math.Cos(value * Math.PI / 4), -Math.Sin(value * Math.PI / 4));
    private string WalkingMotion => direction switch { 2 => "walk-back", 6 => "walk-front", 0 or 4 => "walk-side", 1 or 3 => "walk-back-diagonal", _ => "walk" };
    private void Tick()
    {
        if (!IsVisible || store.IsSleeping) return;
        var now = CompanionStore.Uptime; var elapsed = Math.Min(.2, Math.Max(0, now - lastTick)); lastTick = now;
        if (testMotion is not null && now >= testUntil)
        {
            if (testDirection is { } finalDirection) { var vector = Vector(finalDirection); Left = testOrigin.X + vector.X * 60; Top = testOrigin.Y + vector.Y * 60; }
            StopTest();
        }
        var reacting = store.Celebration is { } c && (DateTimeOffset.UtcNow - c).TotalSeconds < Sprites.Get("complete").Duration;
        var failing = store.Failure is { } f && (DateTimeOffset.UtcNow - f).TotalSeconds < Sprites.Get("cry").Duration;
        var working = store.ActiveCount > 0;
        var reduced = !SystemParameters.ClientAreaAnimation;
        if (waveStarted is { } waveAt && now - waveAt >= Sprites.Get("wave").Duration) { waveStarted = null; waveSchedule.Finished(now, Random.Shared.NextDouble()); }
        var canWave = !working && !reacting && !failing && !dragging && testMotion is null && !reduced;
        if (waveSchedule.Delay(now, canWave, destination is null && menuWindows.Count == 0, Random.Shared.NextDouble()) == 0 && waveStarted is null) waveStarted = now;
        if (!dragging && testDirection is { } td)
        {
            var vector = Vector(td); var progress = Math.Clamp(2 - (testUntil - now), 0, 2) * 30;
            Left = testOrigin.X + vector.X * progress; Top = testOrigin.Y + vector.Y * progress;
        }
        else if (!dragging && !working && !reacting && !failing && store.Preferences.Roaming && testMotion is null && menuWindows.Count == 0 && !reduced && waveStarted is null)
        {
            if (destination is null && now >= nextWalk)
            {
                var bounds = ScreenBounds();
                foreach (var candidate in Enumerable.Range(0, 8).OrderBy(_ => Random.Shared.Next()))
                {
                    var v = Vector(candidate); var distance = Random.Shared.Next(40, 211); var p = new Point(Left + v.X * distance, Top + v.Y * distance);
                    if (bounds.Contains(new Point(p.X + Width / 2, p.Y + 190))) { destination = p; direction = candidate; break; }
                }
                if (destination is null) nextWalk = now + 3;
            }
            if (destination is { } target)
            {
                var p = ZcreSupporter.Core.Point.Step(new(Left, Top), new(target.X, target.Y), elapsed * 30); Left = p.X; Top = p.Y;
                if ((new Point(Left, Top) - target).Length < .1) { destination = null; nextWalk = now + Random.Shared.Next(3, 9); }
            }
        }
        else destination = null;
        var next = testMotion ?? (dragging ? "drag" : failing ? "cry" : reacting ? "complete" : working ? "working" : destination is not null ? WalkingMotion : waveStarted is not null ? "wave" : "idle");
        SetMotion(next);
        mirrored = PetFacing.Resolve(next, dragging, mirrored, Left + Width / 2 > ScreenBounds().Left + ScreenBounds().Width / 2, direction);
        var clip = Sprites.Get(motion); var animationElapsed = motion == "complete" && testMotion is null && store.Celebration is { } completeAt ? (DateTimeOffset.UtcNow - completeAt).TotalSeconds : motion == "cry" && testMotion is null && store.Failure is { } failAt ? (DateTimeOffset.UtcNow - failAt).TotalSeconds : now - motionStarted;
        if (motion == "idle") animationElapsed = Math.Floor(animationElapsed * 12) / 12;
        var index = SpriteTiming.Frame(animationElapsed, clip.Frames.Length, clip.Delay, clip.Loop, !reduced);
        var scale = 108.5 * store.Preferences.PetScale / clip.BodyHeight * (motion == "drag" ? clip.GrabScale(index) : 1);
        image.Source = clip.Frames[index]; image.Width = clip.Frames[index].PixelWidth * scale; image.Height = clip.Frames[index].PixelHeight * scale;
        Canvas.SetLeft(image, (Width - image.Width) / 2); Canvas.SetTop(image, 223 - image.Height);
        var transform = new TransformGroup(); transform.Children.Add(new ScaleTransform(mirrored ? -1 : 1, 1, image.Width / 2, image.Height / 2));
        if (motion == "drag") { var anchor = clip.GrabAnchor(index); var ax = (mirrored ? clip.Frames[index].PixelWidth - anchor.X : anchor.X) * scale; transform.Children.Add(new RotateTransform(mirrored ? -clip.GrabRotation : clip.GrabRotation, ax, anchor.Y * scale)); }
        image.RenderTransform = transform;
        if (motionStatus is not null) motionStatus.Text = $"모션 {motion} · 방향 {(mirrored ? "왼쪽" : "오른쪽")}" + (lastTestDistance is { } moved ? $" · 최근 이동 {moved:F1}pt" : "");
        if (dragging) PositionAtScruff(CursorPoint());
        timer.Interval = TimeSpan.FromSeconds(motion == "idle" ? 1d / 12 : 1d / 24);
        label.Text = working ? $"{store.ActiveCount}개의 작업을 지켜보고 있어요" : store.IsDemo ? "미리보기 · 가상 데이터" : "지크";
        bubbleText.Text = store.Bubble; bubble.Visibility = store.Bubble is null ? Visibility.Collapsed : Visibility.Visible;
        audio.Update(motion, store.Preferences.PetSounds && !store.FocusActive && !store.IsSleeping, store.Preferences.PetSoundVolume);
    }
    private ContextMenu BuildContextMenu()
    {
        var menu = new ContextMenu();
        void Add(string title, Action action) { var item = new MenuItem { Header = title }; item.Click += (_, _) => action(); menu.Items.Add(item); }
        Add("현황판", () => DashboardRequested?.Invoke()); Add("설정", () => SettingsRequested?.Invoke());
        Add(store.Preferences.Roaming ? "산책 비활성화" : "산책 활성화", () => { store.Preferences.Roaming = !store.Preferences.Roaming; store.SavePreferences(); });
        Add("지크 숨기기", () => { store.Preferences.PetVisible = false; store.SavePreferences(); });
        if (store.DebugEnabled) Add("모션 테스트", ShowMotionTests);
        return menu;
    }
    public void CloseMenu() { foreach (var panel in menuWindows) panel.Close(); menuWindows.Clear(); menuCreditText = menuCountText = null; }
    private void UpdateMenuSummary()
    {
        if (menuCreditText is null || menuCountText is null) return;
        menuCreditText.Text = "사용 가능 " + store.CreditText + " Credit";
        var limits = store.Snapshot?.Concurrency;
        menuCountText.Text = $"이미지 {store.Snapshot?.ActiveJobs.Count(j => j.MediaType == "image") ?? 0}{(limits is null ? "" : "/" + limits.ImagesLimit)}  ·  영상 {store.Snapshot?.ActiveJobs.Count(j => j.MediaType == "video") ?? 0}{(limits is null ? "" : "/" + limits.VideosLimit)}  ·  합계 {store.ActiveCount}";
    }
    private void ShowMenu(string category)
    {
        CloseMenu(); destination = null;
        var bounds = ScreenBounds();
        var summary = new StackPanel(); menuCreditText = Ui.Text("", 16, true); menuCountText = Ui.Text("", 11); summary.Children.Add(menuCreditText); summary.Children.Add(menuCountText); UpdateMenuSummary();
        (string Name, string Target)[] items = category switch
        {
            "image" => [("이미지 생성", "/studio/image"), ("캐릭터 시트", "/studio/character-sheet"), ("부분 수정", "/studio/partial-edit"), ("배경 제거", "/studio/image?tool=background-removal"), ("고화질 변환", "/studio/image?tool=upscale"), ("크기 변환", "/studio/image?tool=resize"), ("뒤로", "home"), ("닫기", "close")],
            "video" => [("영상 생성", "/studio/video"), ("고화질 변환", "/studio/image?tool=upscale&media=video"), ("프레임 보간", "/studio/frame-interpolation"), ("영상 번역", "/studio/video-translate"), ("뒤로", "home"), ("닫기", "close")],
            _ => [("이미지", "image"), ("영상", "video"), ("주짓수", "/studio/jiujitsu"), ("오디오", "/studio/audio"), ("닫기", "close")]
        };
        var scale = store.Preferences.PetScale;
        var anchor = new RectD(Left + Width / 2 - 45 * scale, -(Top + 223), 90 * scale, 108.5 * scale);
        var measuredLabel = new FormattedText(label.Text, System.Globalization.CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, new Typeface(label.FontFamily, label.FontStyle, label.FontWeight, label.FontStretch), label.FontSize, label.Foreground, VisualTreeHelper.GetDpi(this).PixelsPerDip).WidthIncludingTrailingWhitespace;
        var layout = new PetMenuLayout(anchor, new RectD(bounds.X, -bounds.Bottom, bounds.Width, bounds.Height), items.Length, category == "home", Math.Max(20, measuredLabel));
        Panel(summary, layout.Summary.X, -layout.Summary.MaxY, layout.Summary.Width);
        for (var i = 0; i < items.Length && i < layout.Buttons.Count; i++)
        {
            var item = items[i]; var box = layout.Buttons[i]; var x = box.X; var y = -box.MaxY;
            var button = Ui.Action(item.Name.Replace(" ", "\n"), () => { if (item.Target == "close") CloseMenu(); else if (item.Target.StartsWith('/')) { CloseMenu(); ToolRequested?.Invoke(item.Target); } else ShowMenu(item.Target); });
            button.Width = button.Height = 56; button.FontSize = 10.5; button.Padding = new Thickness(2); button.Margin = new Thickness(0); button.ToolTip = item.Name;
            var template = new ControlTemplate(typeof(Button)); var border = new FrameworkElementFactory(typeof(Border)); border.SetValue(Border.CornerRadiusProperty, new CornerRadius(28)); border.SetValue(Border.BackgroundProperty, Ui.Surface); border.SetValue(Border.BorderBrushProperty, Brushes.Gray); border.SetValue(Border.BorderThicknessProperty, new Thickness(1)); var content = new FrameworkElementFactory(typeof(ContentPresenter)); content.SetValue(FrameworkElement.HorizontalAlignmentProperty, HorizontalAlignment.Center); content.SetValue(FrameworkElement.VerticalAlignmentProperty, VerticalAlignment.Center); border.AppendChild(content); template.VisualTree = border; button.Template = template;
            Panel(button, x, y, 56, false);
        }
    }
    private void Panel(UIElement content, double x, double y, double width, bool card = true)
    {
        var panel = new Window { Title = "지크 원형 메뉴", Width = width, SizeToContent = SizeToContent.Height, Left = x, Top = y, WindowStyle = WindowStyle.None, AllowsTransparency = true, Background = Brushes.Transparent, Topmost = true, ShowInTaskbar = false, Owner = this };
        panel.Content = card ? Ui.Card(content) : content; panel.PreviewKeyDown += (_, e) => { if (e.Key == Key.Escape) CloseMenu(); }; menuWindows.Add(panel); panel.Show();
    }
    public void ShowMotionTests()
    {
        if (!store.DebugEnabled) return;
        if (motionTests is not null) { motionTests.Activate(); return; }
        var controls = new WrapPanel(); var window = Ui.Window("지크 모션 테스트", controls, 560, 350);
        motionTests = window;
        motionStatus = Ui.Text("모션 확인 중", 12); motionStatus.Width = 480; controls.Children.Add(motionStatus);
        string[] directions = ["동", "북동", "북", "북서", "서", "남서", "남", "남동"];
        for (var i = 0; i < 8; i++) { var d = i; controls.Children.Add(Ui.Action(directions[d] + " · 2초", () => Test("walk", 2, d))); }
        foreach (var (title, state, seconds) in new[] { ("대기", "idle", 2d), ("잡힘 왼쪽", "drag", 2d), ("잡힘 오른쪽", "drag", 2d), ("작업 중 · 6초", "working", 6d), ("작업 완료", "complete", Sprites.Get("complete").Duration), ("작업 실패", "cry", Sprites.Get("cry").Duration), ("손 흔들기", "wave", Sprites.Get("wave").Duration) }) controls.Children.Add(Ui.Action(title, () => { mirrored = title.Contains("왼쪽"); Test(state, seconds); }));
        controls.Children.Add(Ui.Action("중지", StopTest));
        window.PreviewKeyDown += (_, e) =>
        {
            if (e.Key == Key.Escape) { StopTest(); e.Handled = true; return; }
            if (Keyboard.Modifiers != ModifierKeys.Control) return;
            if (e.Key is >= Key.D1 and <= Key.D8) { Test("walk", 2, e.Key - Key.D1); e.Handled = true; }
            else if (e.Key is Key.L or Key.R) { mirrored = e.Key == Key.L; Test("drag", 2); e.Handled = true; }
            else if (e.Key == Key.W) { Test("working", 6); e.Handled = true; }
            else if (e.Key == Key.C) { Test("complete", Sprites.Get("complete").Duration); e.Handled = true; }
            else if (e.Key == Key.F) { Test("cry", Sprites.Get("cry").Duration); e.Handled = true; }
        };
        window.Closed += (_, _) => { motionTests = null; motionStatus = null; StopTest(); }; window.Show();
    }
    private void Test(string state, double seconds, int? d = null)
    {
        if (!store.DebugEnabled) return;
        store.Preferences.PetVisible = true; Show(); RestoreIfLost();
        if (d is not null) { var bounds = ScreenBounds(); Left = Math.Clamp(Left, bounds.Left + 60, Math.Max(bounds.Left + 60, bounds.Right - Width - 60)); Top = Math.Clamp(Top, bounds.Top + 60, Math.Max(bounds.Top + 60, bounds.Bottom - Height - 60)); }
        testMotion = state; testDirection = d; testUntil = CompanionStore.Uptime + seconds; testOrigin = new(Left, Top); destination = null;
        lastTestDistance = null;
        if (d is { } value) { direction = value; testMotion = WalkingMotion; }
        motionStarted = CompanionStore.Uptime; timer.Start(); store.NotifyVisualState();
    }
    public void StopTest() { var changed = testMotion is not null; if (testDirection is not null) lastTestDistance = (new Point(Left, Top) - testOrigin).Length; testMotion = null; testDirection = null; destination = null; nextWalk = CompanionStore.Uptime + 3; if (changed) store.NotifyVisualState(); }
    public void Shutdown() { shuttingDown = true; store.Changed -= Refresh; motionTests?.Close(); timer.Stop(); CloseMenu(); audio.Dispose(); Microsoft.Win32.SystemEvents.DisplaySettingsChanged -= DisplayChanged; Close(); }
    [StructLayout(LayoutKind.Sequential)] private struct CursorPosition { public int X, Y; }
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out CursorPosition point);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] private static extern long GetWindowLongPtr(IntPtr hwnd, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] private static extern long SetWindowLongPtr(IntPtr hwnd, int index, long value);
}
