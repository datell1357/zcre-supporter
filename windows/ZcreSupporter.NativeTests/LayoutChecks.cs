using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Input;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Threading;
using System.Xml.Linq;
using ZcreSupporter;

internal sealed class LayoutChecks : Application
{
    private readonly string directory;
    private int failures;
    private LayoutChecks(string directory, string themeSource)
    {
        this.directory = directory; ShutdownMode = ShutdownMode.OnExplicitShutdown;
        XNamespace presentation = "http://schemas.microsoft.com/winfx/2006/xaml/presentation";
        var source = XDocument.Load(themeSource);
        var resources = new XElement(presentation + "ResourceDictionary", new XAttribute("xmlns", presentation.NamespaceName),
            new XAttribute(XNamespace.Xmlns + "x", "http://schemas.microsoft.com/winfx/2006/xaml"), source.Root!.Element(presentation + "Application.Resources")!.Elements());
        Resources = (ResourceDictionary)XamlReader.Parse(resources.ToString());
    }
    internal static int Execute(string directory, string themeSource)
    {
        if (!Path.IsPathFullyQualified(directory) || Directory.Exists(directory) || !Path.IsPathFullyQualified(themeSource)) throw new ArgumentException();
        return new LayoutChecks(directory, themeSource).Run();
    }
    protected override async void OnStartup(StartupEventArgs e)
    {
        LocalData.Initialize(["--data-dir", directory]);
        await Check("account window fits the actual work area without loading an authentication page", AccountBounds);
        await Check("dashboard sections remain readable and reachable from 980 to 496 DIP and back", DashboardBounds);
        await Check("compact settings retain aligned input heights and complete action labels", SettingsBounds);
        await Check("home, image and video menu windows fit and stay separated at 70, 100 and 150 percent pet size", PetBounds);
        Shutdown(failures == 0 ? 0 : 1);
    }
    private async Task Check(string name, Func<Task> action)
    {
        try { await action(); Console.WriteLine("PASS " + name); }
        catch (Exception error) { failures++; Console.WriteLine("FAIL " + name + ": " + error.GetType().Name + ": " + error.Message); }
    }
    private static Task Idle() => Application.Current.Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle).Task;
    private async Task AccountBounds()
    {
        using var session = new WebSession();
        var window = Windows.Cast<Window>().Single(w => w.Title == "ZCRE 서포터 · 계정 연결");
        window.Show(); await Idle();
        if (!GetWindowRect(new WindowInteropHelper(window).Handle, out var rect)) throw new InvalidOperationException("Account frame unavailable.");
        var area = TrayPopupHost.ForIcon(new(rect.Left, rect.Top, 1, 1)).WorkArea;
        if (!area.Contains(new(rect.Left, rect.Top, rect.Right - rect.Left, rect.Bottom - rect.Top))) throw new InvalidOperationException("Account window extends outside its work area.");
    }
    private async Task DashboardBounds()
    {
        using var store = new CompanionStore(); using var status = new ServiceStatus(); await store.StartAsync(true);
        var dashboard = new DashboardWindow(store, status);
        try
        {
            dashboard.Present();
            foreach (var (width, height) in new[] { (980d, 600d), (720, 420), (640, 400), (496, 348), (980, 600) })
            {
                dashboard.Width = width; dashboard.Height = height; await Idle();
                var grid = Descendants(dashboard).OfType<Grid>().Single(g => g.Name == "DashboardSections");
                var sections = grid.Children.Cast<FrameworkElement>().ToArray();
                if (sections.Length != 3) throw new InvalidOperationException("A dashboard section disappeared.");
                var frames = sections.Select(s => s.TransformToAncestor(dashboard).TransformBounds(new Rect(new Point(), s.RenderSize))).ToArray();
                if (width < 800)
                {
                    if (frames.Any(r => r.Width < width - 80) || frames.Zip(frames.Skip(1)).Any(p => p.First.Bottom > p.Second.Top + 1)) throw new InvalidOperationException("Compact dashboard sections are squeezed or overlap at " + width + " DIP.");
                    var body = Descendants(dashboard).OfType<ScrollViewer>().Single(s => ReferenceEquals(s.Content, grid));
                    body.ScrollToTop(); await Idle();
                    sections[0].RaiseEvent(new MouseWheelEventArgs(Mouse.PrimaryDevice, Environment.TickCount, -120) { RoutedEvent = Mouse.MouseWheelEvent });
                    await Idle();
                    if (body.VerticalOffset <= 0) throw new InvalidOperationException("Compact section content swallowed the outer wheel input.");
                    body.ScrollToEnd(); await Idle();
                    var last = Descendants(sections[2]).OfType<Button>().Last();
                    var lastFrame = last.TransformToAncestor(body).TransformBounds(new Rect(new Point(), last.RenderSize));
                    if (lastFrame.Top < 0 || lastFrame.Bottom > body.ActualHeight + 1) throw new InvalidOperationException("The last compact action is unreachable.");
                }
                else
                {
                    var headings = sections.Cast<ScrollViewer>().Select(s => ((StackPanel)s.Content).Children[0]).OfType<TextBlock>().Select(t => t.TranslatePoint(new Point(), dashboard).Y).ToArray();
                    if (frames.Any(r => Math.Abs(r.Top - frames[0].Top) > 1) || frames.Zip(frames.Skip(1)).Any(p => p.First.Right > p.Second.Left + 1) || headings.Any(y => Math.Abs(y - headings[0]) > 1)) throw new InvalidOperationException("Full-width columns overlap or lose heading alignment.");
                }
                CheckLabels(dashboard);
            }
        }
        finally { dashboard.Shutdown(); }
    }
    private async Task SettingsBounds()
    {
        using var store = new CompanionStore(); using var status = new ServiceStatus(); await store.StartAsync(true);
        var dashboard = new DashboardWindow(store, status);
        try
        {
            dashboard.ShowSettings(); var settings = Windows.Cast<Window>().Single(w => w.Title == "ZCRE 서포터 · 설정");
            settings.Width = 360; settings.Height = 480; await Idle();
            var password = Descendants(settings).OfType<PasswordBox>().Single();
            var text = Descendants(settings).OfType<TextBox>().First();
            if (password.ActualHeight < text.ActualHeight - 2) throw new InvalidOperationException("The debug input is shorter than adjacent settings inputs.");
            CheckLabels(settings);
            await SettingsScrollChecks.Run(Descendants(settings).OfType<ScrollViewer>().First());
            settings.WindowState = WindowState.Maximized; await Idle();
            if (!GetWindowRect(new WindowInteropHelper(settings).Handle, out var rect) || !TrayPopupHost.ForIcon(new(rect.Left, rect.Top, 1, 1)).WorkArea.Contains(new(rect.Left, rect.Top, rect.Right - rect.Left, rect.Bottom - rect.Top))) throw new InvalidOperationException("Maximized themed settings cover the taskbar or leave the work area.");
            settings.WindowState = WindowState.Normal; await Idle();
            if (Math.Abs(settings.ActualWidth - 360) > 2 || Math.Abs(settings.ActualHeight - 480) > 2) throw new InvalidOperationException("Maximized settings did not restore their compact dimensions.");
        }
        finally { dashboard.Shutdown(); }
    }
    private static void CheckLabels(Window window)
    {
        foreach (var button in Descendants(window).OfType<Button>().Where(b => b.IsVisible && b.ActualWidth > 0 && b.Content is string))
        {
            var text = new FormattedText((string)button.Content, CultureInfo.CurrentUICulture, button.FlowDirection,
                new Typeface(button.FontFamily, button.FontStyle, button.FontWeight, button.FontStretch), button.FontSize, button.Foreground, VisualTreeHelper.GetDpi(button).PixelsPerDip);
            if (text.WidthIncludingTrailingWhitespace + button.Padding.Left + button.Padding.Right + 2 > button.ActualWidth + 1) throw new InvalidOperationException("A settings/dashboard action label is horizontally clipped.");
        }
    }
    private async Task PetBounds()
    {
        using var store = new CompanionStore(); await store.StartAsync(true);
        var pet = new PetWindow(store); pet.Show(); await Idle();
        try
        {
            var area = SystemParameters.WorkArea;
            foreach (var scale in new[] { .7, 1, 1.5 })
            foreach (var position in new[] { new Point(area.Left + 20, area.Top + 20), new Point(area.Right - pet.Width - 20, area.Bottom - pet.Height - 20) })
            foreach (var (category, count) in new[] { ("home", 6), ("image", 8), ("video", 6) })
            {
                store.Preferences.PetScale = scale; store.SavePreferences(); pet.Left = position.X; pet.Top = position.Y;
                pet.ShowMenu(category); await Idle();
                var menus = Windows.Cast<Window>().Where(w => w.Title == "지크 원형 메뉴").ToArray();
                var frames = menus.Select(w => new Rect(w.Left, w.Top, w.ActualWidth, w.ActualHeight)).ToArray();
                if (menus.Length != count + 1 || frames.Any(r => !area.Contains(r)) || frames.Select((r, i) => frames.Skip(i + 1).Any(r.IntersectsWith)).Any(v => v)) throw new InvalidOperationException("Actual " + category + " menu bounds overlap or leave the work area at scale " + scale + ".");
                pet.CloseMenu();
            }
        }
        finally { pet.Shutdown(); }
    }
    private static IEnumerable<DependencyObject> Descendants(DependencyObject root)
    {
        yield return root;
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++)
            foreach (var child in Descendants(VisualTreeHelper.GetChild(root, i))) yield return child;
    }
    [StructLayout(LayoutKind.Sequential)] private struct NativeRect { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hwnd, out NativeRect rect);
}
