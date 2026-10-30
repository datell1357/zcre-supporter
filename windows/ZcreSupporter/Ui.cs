namespace ZcreSupporter;

internal static class Ui
{
    public static Brush Surface { get; } = new SolidColorBrush(Color.FromRgb(28, 30, 34));
    public static Brush Muted { get; } = new SolidColorBrush(Color.FromRgb(154, 159, 169));
    public static Brush Accent { get; } = new SolidColorBrush(Color.FromRgb(201, 233, 193));
    public static TextBlock Text(string? value, double size = 13, bool bold = false) => new() { Text = value ?? "", FontSize = size, FontWeight = bold ? FontWeights.SemiBold : FontWeights.Normal, Margin = new Thickness(0, 0, 0, 7), Foreground = Brushes.White };
    public static Button Action(string title, Action action)
    {
        var button = new Button { Content = title }; button.Click += (_, _) => action(); return button;
    }
    public static Border Card(UIElement child) => new() { Child = child, Background = Surface, BorderBrush = new SolidColorBrush(Color.FromRgb(48, 52, 60)), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(12), Padding = new Thickness(16), Margin = new Thickness(0, 0, 0, 12) };
    public static Window Window(string title, UIElement child, double width = 600, double height = 650)
    {
        var anchor = TrayPopupHost.CursorAnchor(); var area = anchor.WorkArea; var margin = 8 * anchor.Scale;
        var physicalWidth = Math.Min(width * anchor.Scale, area.Width - 2 * margin);
        var physicalHeight = Math.Min(height * anchor.Scale, area.Height - 2 * margin);
        var bounds = new RectD(area.X + (area.Width - physicalWidth) / 2, area.Y + (area.Height - physicalHeight) / 2, physicalWidth, physicalHeight);
        var window = new Window { Title = "ZCRE 서포터 · " + title, Content = new Border { Padding = new Thickness(24), Child = child }, Width = physicalWidth / anchor.Scale, Height = physicalHeight / anchor.Scale, WindowStartupLocation = WindowStartupLocation.Manual };
        window.SourceInitialized += (_, _) => TrayPopupHost.PlaceWindow(window, bounds);
        window.Loaded += (_, _) => TrayPopupHost.PlaceWindow(window, bounds);
        return window;
    }
    public static void SettingsChrome(Window window)
    {
        window.Resources.MergedDictionaries.Add(new ResourceDictionary { Source = new Uri("/ZcreSupporter;component/SettingsTheme.xaml", UriKind.Relative) });
        window.WindowStyle = WindowStyle.None; window.MinWidth = 320; window.MinHeight = 240;
        System.Windows.Shell.WindowChrome.SetWindowChrome(window, new()
        {
            CaptionHeight = 52, ResizeBorderThickness = new Thickness(6), GlassFrameThickness = new Thickness(0),
            CornerRadius = new CornerRadius(14), UseAeroCaptionButtons = false, NonClientFrameEdges = System.Windows.Shell.NonClientFrameEdges.None
        });
        var content = (UIElement)window.Content; window.Content = null;
        var frame = new DockPanel();
        var header = new Grid { Height = 52, Background = Brushes.Transparent };
        header.ColumnDefinitions.Add(new ColumnDefinition()); header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var brand = Text("ZCRE", 12, true); brand.Foreground = Accent; brand.Margin = new Thickness(24, 0, 0, 0); brand.VerticalAlignment = VerticalAlignment.Center; header.Children.Add(brand);
        var close = Action("×", window.Close); close.Width = close.Height = 32; close.Padding = new Thickness(0); close.Margin = new Thickness(0, 0, 14, 0); close.FontSize = 20; close.VerticalAlignment = VerticalAlignment.Center; close.ToolTip = "설정 닫기 · Esc";
        System.Windows.Automation.AutomationProperties.SetName(close, "설정 닫기"); System.Windows.Automation.AutomationProperties.SetAutomationId(close, "SettingsClose");
        System.Windows.Shell.WindowChrome.SetIsHitTestVisibleInChrome(close, true); Grid.SetColumn(close, 1); header.Children.Add(close);
        DockPanel.SetDock(header, Dock.Top); frame.Children.Add(header); frame.Children.Add(content);
        window.Content = new Border { BorderBrush = new SolidColorBrush(Color.FromRgb(48, 52, 60)), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(14), Child = frame };
    }
    public static StackPanel Section(string title) { var panel = new StackPanel(); panel.Children.Add(Text(title, 16, true)); return panel; }
    public static WrapPanel Actions(params Button[] buttons) { var row = new WrapPanel(); foreach (var button in buttons) row.Children.Add(button); return row; }
}
