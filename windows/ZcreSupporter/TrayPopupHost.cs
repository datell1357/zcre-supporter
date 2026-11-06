using System.Runtime.InteropServices;
using System.Windows.Interop;
using Microsoft.Win32;
using System.Windows.Media.Animation;

namespace ZcreSupporter;

internal sealed class TrayPopupHost : IDisposable
{
    private readonly Window window;
    private HwndSource? source;
    private bool placing;
    private readonly TranslateTransform entrance = new();
    private readonly DispatcherTimer entranceTimer = new(DispatcherPriority.Normal) { Interval = TimeSpan.FromMilliseconds(200) };
    private UIElement? entranceContent;
    public Func<TrayAnchor> Anchor { get; set; } = CursorAnchor;

    public TrayPopupHost(Window window)
    {
        this.window = window;
        entranceTimer.Tick += FinishEntrance;
        window.WindowStyle = WindowStyle.None; window.ResizeMode = ResizeMode.NoResize;
        window.ShowInTaskbar = false; window.Topmost = true; window.WindowStartupLocation = WindowStartupLocation.Manual;
        window.Deactivated += Hide;
        window.IsVisibleChanged += VisibilityChanged;
        window.SourceInitialized += Initialized;
        SystemEvents.DisplaySettingsChanged += DisplayChanged;
    }

    public void Present()
    {
        var wasVisible = window.IsVisible;
        StopEntrance();
        var anchor = Anchor(); var bounds = TrayPopupPlacement.Place(anchor);
        // Select the destination monitor before Show; SetWindowPos handles its physical origin.
        window.WindowState = WindowState.Normal;
        window.Width = bounds.Width / anchor.Scale; window.Height = bounds.Height / anchor.Scale;
        new WindowInteropHelper(window).EnsureHandle();
        Place(); window.Show(); Place(); window.Activate();
        if (!wasVisible && SystemParameters.ClientAreaAnimation && window.Content is UIElement content)
        {
            // Slide inside the final HWND so no animation frame crosses a taskbar or monitor edge.
            entranceContent = content; content.RenderTransform = entrance;
            var offset = EntranceOffset(TrayPopupPlacement.Edge(anchor), true);
            DoubleAnimation Motion(double from, double to) => new(from, to, TimeSpan.FromMilliseconds(160)) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut }, FillBehavior = FillBehavior.Stop };
            entrance.BeginAnimation(TranslateTransform.XProperty, Motion(offset.X, 0));
            entrance.BeginAnimation(TranslateTransform.YProperty, Motion(offset.Y, 0));
            content.BeginAnimation(UIElement.OpacityProperty, Motion(0, 1));
            entranceTimer.Start();
        }
    }

    internal static Vector EntranceOffset(TaskbarEdge edge, bool enabled) => !enabled ? new() : edge switch
    {
        TaskbarEdge.Bottom => new(0, 16), TaskbarEdge.Top => new(0, -16),
        TaskbarEdge.Left => new(-16, 0), TaskbarEdge.Right => new(16, 0),
        _ => throw new ArgumentOutOfRangeException(nameof(edge))
    };
    private void StopEntrance()
    {
        entranceTimer.Stop();
        entrance.BeginAnimation(TranslateTransform.XProperty, null); entrance.BeginAnimation(TranslateTransform.YProperty, null);
        entranceContent?.BeginAnimation(UIElement.OpacityProperty, null); entranceContent = null;
    }
    private void FinishEntrance(object? sender, EventArgs e) => StopEntrance();
    private void VisibilityChanged(object sender, DependencyPropertyChangedEventArgs e) { if (!window.IsVisible) StopEntrance(); }

    private void Place()
    {
        if (placing) return;
        placing = true;
        try
        {
            var anchor = Anchor(); var bounds = TrayPopupPlacement.Place(anchor);
            window.Width = bounds.Width / anchor.Scale; window.Height = bounds.Height / anchor.Scale;
            if (!SetWindowPos(new WindowInteropHelper(window).Handle, new IntPtr(-1), (int)Math.Round(bounds.X), (int)Math.Round(bounds.Y),
                (int)Math.Round(bounds.Width), (int)Math.Round(bounds.Height), 0x10)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        }
        finally { placing = false; }
    }

    private void Initialized(object? sender, EventArgs e) { source = HwndSource.FromHwnd(new WindowInteropHelper(window).Handle); source?.AddHook(Message); }
    private IntPtr Message(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (message == 0x02E0 && window.IsVisible) window.Dispatcher.BeginInvoke(Place);
        return IntPtr.Zero;
    }
    private void Hide(object? sender, EventArgs e) => window.Hide();
    private void DisplayChanged(object? sender, EventArgs e) => window.Dispatcher.BeginInvoke(() => { if (window.IsVisible) Place(); });
    public void Dispose()
    {
        StopEntrance(); entranceTimer.Tick -= FinishEntrance; window.IsVisibleChanged -= VisibilityChanged;
        window.Deactivated -= Hide; window.SourceInitialized -= Initialized;
        SystemEvents.DisplaySettingsChanged -= DisplayChanged;
        if (source is { IsDisposed: false }) source.RemoveHook(Message);
        source = null;
    }

    internal static TrayAnchor CursorAnchor()
    {
        if (!GetCursorPos(out var point)) point = new();
        return ForIcon(new RectD(point.X, point.Y, 1, 1));
    }
    internal static void PlaceWindow(Window target, RectD bounds)
    {
        if (!SetWindowPos(new WindowInteropHelper(target).Handle, IntPtr.Zero, (int)Math.Round(bounds.X), (int)Math.Round(bounds.Y),
            (int)Math.Round(bounds.Width), (int)Math.Round(bounds.Height), 0x14)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    }
    internal static void FitToWorkArea(Window target)
    {
        if (!GetWindowRect(new WindowInteropHelper(target).Handle, out var rect)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        PlaceWindow(target, ForIcon(rect.ToRect()).WorkArea);
    }
    internal static TrayAnchor ForIcon(RectD icon)
    {
        var point = new NativePoint { X = (int)icon.MidX, Y = (int)icon.MidY };
        var monitor = MonitorFromPoint(point, 2);
        var info = new MonitorInfo { Size = Marshal.SizeOf<MonitorInfo>() };
        if (!GetMonitorInfo(monitor, ref info)) throw new InvalidOperationException("Monitor work area is unavailable.");
        var scale = GetDpiForMonitor(monitor, 0, out var dpiX, out _) == 0 ? dpiX / 96d : 1;
        return new(info.Monitor.ToRect(), info.Work.ToRect(), icon, scale);
    }

    [StructLayout(LayoutKind.Sequential)] private struct NativePoint { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] private struct NativeRect
    {
        public int Left, Top, Right, Bottom;
        public readonly RectD ToRect() => new(Left, Top, Right - Left, Bottom - Top);
    }
    [StructLayout(LayoutKind.Sequential)] private struct MonitorInfo { public int Size; public NativeRect Monitor, Work; public uint Flags; }
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out NativePoint point);
    [DllImport("user32.dll")] private static extern IntPtr MonitorFromPoint(NativePoint point, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
    [DllImport("shcore.dll")] private static extern int GetDpiForMonitor(IntPtr monitor, int type, out uint x, out uint y);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool GetWindowRect(IntPtr hwnd, out NativeRect rect);
}
