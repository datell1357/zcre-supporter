using System.Windows.Automation;

namespace ZcreSupporter;

internal static class Ui
{
    public static Brush Surface { get; } = new SolidColorBrush(Color.FromRgb(28, 30, 34));
    public static Brush Muted { get; } = new SolidColorBrush(Color.FromRgb(154, 159, 169));
    public static Brush Accent { get; } = new SolidColorBrush(Color.FromRgb(201, 233, 193));
    public static TextBlock Text(string? value, double size = 13, bool bold = false) => new() { Text = value ?? "", FontSize = size, FontWeight = bold ? FontWeights.SemiBold : FontWeights.Normal, Margin = new Thickness(0, 0, 0, 7), Foreground = Brushes.White };
    public static Button Action(string title, Action action)
    {
        var button = new Button { Content = title }; AutomationProperties.SetName(button, title); button.Click += (_, _) => action(); return button;
    }
    public static Border Card(UIElement child) => new() { Child = child, Background = Surface, BorderBrush = new SolidColorBrush(Color.FromRgb(48, 52, 60)), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(12), Padding = new Thickness(16), Margin = new Thickness(0, 0, 0, 12) };
    public static Window Window(string title, UIElement child, double width = 600, double height = 650) => new() { Title = "ZCRE 서포터 · " + title, Content = new Border { Padding = new Thickness(24), Child = child }, Width = width, Height = height, WindowStartupLocation = WindowStartupLocation.CenterScreen };
    public static StackPanel Section(string title) { var panel = new StackPanel(); panel.Children.Add(Text(title, 16, true)); return panel; }
    public static WrapPanel Actions(params Button[] buttons) { var row = new WrapPanel(); foreach (var button in buttons) row.Children.Add(button); return row; }
}
