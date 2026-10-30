using ZcreSupporter.Core;

internal static class LayoutAuditChecks
{
    internal static void Run(Action<string, bool> check)
    {
        foreach (var dpi in new[] { 1d, 1.25, 1.5, 2 })
        foreach (var petScale in new[] { .7, 1, 1.5 })
        {
            var screen = new RectD(0, 0, 1024 / dpi, 728 / dpi);
            var w = 90 * petScale; var h = 108.5 * petScale;
            foreach (var anchor in new[] { new RectD(12, 36, w, h), new(screen.MaxX - w - 12, 36, w, h), new(12, screen.MaxY - h - 12, w, h), new(screen.MaxX - w - 12, screen.MaxY - h - 12, w, h) })
            foreach (var (count, home) in new[] { (6, true), (6, false), (8, false) })
            {
                var layout = new PetMenuLayout(anchor, screen, count, home, 220);
                var name = $"menu/effective-dpi-{dpi}/pet-{petScale}/{anchor.X}/{anchor.Y}/{count}/{home}";
                check(name + "/all actions", layout.Buttons.Count == count);
                check(name + "/inside work area", screen.Contains(layout.Summary) && layout.Buttons.All(screen.Contains));
                check(name + "/separation", layout.Buttons.Select((b, i) => !layout.Buttons.Skip(i + 1).Any(b.Intersects) && !b.Intersects(layout.Summary) && !layout.Protected.Any(p => p.Intersects(b))).All(v => v));
            }
        }
    }
}
