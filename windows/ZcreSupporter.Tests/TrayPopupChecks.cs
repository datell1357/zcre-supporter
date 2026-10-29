using ZcreSupporter.Core;

internal static class TrayPopupChecks
{
    internal static void Run(Action<string, bool> check)
    {
        foreach (var scale in new[] { 1d, 1.25, 1.5, 2 })
        foreach (var monitor in new[] { new RectD(0, 0, 1920, 1080), new RectD(-2560, -360, 2560, 1440), new RectD(1920, 0, 800, 600) })
        foreach (var edge in Enum.GetValues<TaskbarEdge>())
        {
            // Given a physical monitor, taskbar strip and tray icon at its far corner.
            var strip = 40 * scale;
            var work = edge switch
            {
                TaskbarEdge.Bottom => monitor with { Height = monitor.Height - strip },
                TaskbarEdge.Top => monitor with { Y = monitor.Y + strip, Height = monitor.Height - strip },
                TaskbarEdge.Left => monitor with { X = monitor.X + strip, Width = monitor.Width - strip },
                TaskbarEdge.Right => monitor with { Width = monitor.Width - strip },
                _ => throw new ArgumentOutOfRangeException()
            };
            var icon = edge switch
            {
                TaskbarEdge.Bottom => new RectD(monitor.MaxX - 60 * scale, work.MaxY + 4 * scale, 24 * scale, 24 * scale),
                TaskbarEdge.Top => new RectD(monitor.MaxX - 60 * scale, monitor.Y + 4 * scale, 24 * scale, 24 * scale),
                TaskbarEdge.Left => new RectD(monitor.X + 4 * scale, monitor.MaxY - 60 * scale, 24 * scale, 24 * scale),
                TaskbarEdge.Right => new RectD(work.MaxX + 4 * scale, monitor.MaxY - 60 * scale, 24 * scale, 24 * scale),
                _ => throw new ArgumentOutOfRangeException()
            };
            var anchor = new TrayAnchor(monitor, work, icon, scale);
            // When the dashboard is placed, then it remains wholly in this monitor's work area.
            var popup = TrayPopupPlacement.Place(anchor);
            var name = $"tray/{scale}/{monitor.X}/{monitor.Width}/{edge}";
            check(name + "/edge", TrayPopupPlacement.Edge(anchor) == edge);
            check(name + "/contained", work.Contains(popup));
            check(name + "/size", popup.Width <= 980 * scale && popup.Height <= 600 * scale);
            check(name + "/taskbar gap", edge switch
            {
                TaskbarEdge.Bottom => popup.MaxY <= work.MaxY - 8 * scale,
                TaskbarEdge.Top => popup.Y >= work.Y + 8 * scale,
                TaskbarEdge.Left => popup.X >= work.X + 8 * scale,
                TaskbarEdge.Right => popup.MaxX <= work.MaxX - 8 * scale,
                _ => false
            });
            var hidden = anchor with { WorkArea = monitor };
            check(name + "/auto-hide edge", TrayPopupPlacement.Edge(hidden) == edge);
        }
        // Given six home actions, when laid out, then every action survives at the original compact scale.
        var home = new PetMenuLayout(new(600, 400, 90, 110), new(0, 0, 1440, 900), 6, true);
        check("six-action home fits compact arc", home.Buttons.Count == 6 && home.Buttons.All(b => b.Width == 50) && home.Radius is >= 90 and <= 128);
        var previous = new PetMenuLayout(new(600, 400, 90, 110), new(0, 0, 1440, 900), 5, true);
        check("six-action home keeps summary height", Math.Abs(home.Summary.Y - previous.Summary.Y) <= 2 && home.Buttons[4].MidY < 455);
        var ordered = new[] { 0, 3, 4, 5, 2, 1 }.Select(i => home.Buttons[i]).ToArray();
        var expectedGap = 2 * home.Radius * Math.Sin(24 * Math.PI / 180);
        check("six-action home preserves equal arc gaps", ordered.Zip(ordered.Skip(1)).All(pair => Math.Abs(Math.Sqrt(Math.Pow(pair.First.MidX - pair.Second.MidX, 2) + Math.Pow(pair.First.MidY - pair.Second.MidY, 2)) - expectedGap) < .01));
    }
}
