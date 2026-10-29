namespace ZcreSupporter.Core;

// Physical screen pixels throughout; WPF DIPs are converted only at the window boundary.
public readonly record struct TrayAnchor(RectD Monitor, RectD WorkArea, RectD Icon, double Scale);
public enum TaskbarEdge { Bottom, Top, Left, Right }

public static class TrayPopupPlacement
{
    public static TaskbarEdge Edge(TrayAnchor anchor)
    {
        var monitor = anchor.Monitor; var work = anchor.WorkArea;
        var insets = new[] { monitor.MaxY - work.MaxY, work.Y - monitor.Y, work.X - monitor.X, monitor.MaxX - work.MaxX };
        var largest = insets.Max();
        if (largest > 0) return (TaskbarEdge)Array.IndexOf(insets, largest);
        // Auto-hidden taskbars do not reserve a work-area strip. Use the icon's nearest edge.
        var icon = anchor.Icon;
        var distances = new[] { Math.Abs(monitor.MaxY - icon.MidY), Math.Abs(icon.MidY - monitor.Y), Math.Abs(icon.MidX - monitor.X), Math.Abs(monitor.MaxX - icon.MidX) };
        return (TaskbarEdge)Array.IndexOf(distances, distances.Min());
    }

    public static RectD Place(TrayAnchor anchor)
    {
        var scale = double.IsFinite(anchor.Scale) && anchor.Scale > 0 ? anchor.Scale : 1;
        var gap = 8 * scale;
        var work = anchor.WorkArea;
        var width = Math.Min(980 * scale, Math.Max(1, work.Width - gap * 2));
        var height = Math.Min(600 * scale, Math.Max(1, work.Height - gap * 2));
        var icon = anchor.Icon;
        var (x, y) = Edge(anchor) switch
        {
            TaskbarEdge.Bottom => (icon.MidX - width / 2, Math.Min(icon.Y, work.MaxY) - height - gap),
            TaskbarEdge.Top => (icon.MidX - width / 2, Math.Max(icon.MaxY, work.Y) + gap),
            TaskbarEdge.Left => (Math.Max(icon.MaxX, work.X) + gap, icon.MidY - height / 2),
            TaskbarEdge.Right => (Math.Min(icon.X, work.MaxX) - width - gap, icon.MidY - height / 2),
            _ => throw new ArgumentOutOfRangeException(nameof(anchor))
        };
        return new(Math.Clamp(x, work.X + gap, Math.Max(work.X + gap, work.MaxX - width - gap)),
            Math.Clamp(y, work.Y + gap, Math.Max(work.Y + gap, work.MaxY - height - gap)), width, height);
    }
}
