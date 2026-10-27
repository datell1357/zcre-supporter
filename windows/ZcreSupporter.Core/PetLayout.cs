namespace ZcreSupporter.Core;

public readonly record struct RectD(double X, double Y, double Width, double Height)
{
    public double MaxX => X + Width;
    public double MaxY => Y + Height;
    public double MidX => X + Width / 2;
    public double MidY => Y + Height / 2;
    public RectD Inflate(double value) => new(X - value, Y - value, Width + 2 * value, Height + 2 * value);
    public bool Contains(RectD other) => other.X >= X && other.Y >= Y && other.MaxX <= MaxX && other.MaxY <= MaxY;
    public bool Intersects(RectD other) => other.X < MaxX && other.MaxX > X && other.Y < MaxY && other.MaxY > Y;
    public RectD Union(RectD other) => new(Math.Min(X, other.X), Math.Min(Y, other.Y), Math.Max(MaxX, other.MaxX) - Math.Min(X, other.X), Math.Max(MaxY, other.MaxY) - Math.Min(Y, other.Y));
}

// Same Cartesian (+Y up) geometry as ZCRECore/PetQuickMenuLayout.swift.
public sealed class PetMenuLayout
{
    public RectD Summary { get; }
    public IReadOnlyList<RectD> Buttons { get; }
    public IReadOnlyList<RectD> Protected { get; }
    public double Radius { get; }
    public PetMenuLayout(RectD anchor, RectD screen, int count, bool home, double labelWidth = 110)
    {
        var bounds = screen.Inflate(-8); var body = anchor.Inflate(4); var label = new RectD(anchor.MidX - labelWidth / 2, anchor.Y - 30, labelWidth, 24); var protectedFrame = body.Union(label); Protected = [body, label];
        const double edge = 56, spacing = 6;
        RectD Box(double angle, double radius) { var a = angle * Math.PI / 180; return new(anchor.MidX + Math.Cos(a) * radius - edge / 2, anchor.MidY + Math.Sin(a) * radius - edge / 2, edge, edge); }
        var angles = home ? count == 5 ? new double[] { 150, 30, 330, 210, 270 } : [180, 0, 270] : Enumerable.Range(0, count).Select(i => 135 + i * 270d / Math.Max(1, count - 1)).ToArray();
        var radius = Math.Max(80, anchor.Width / 2 + edge / 2 + spacing);
        while (true)
        {
            var frames = angles.Select(a => Box(a, radius)).ToArray();
            if (frames.All(f => !Protected.Any(p => p.Inflate(2).Intersects(f))) && frames.Select((f, i) => !frames.Skip(i + 1).Any(other => f.Inflate(spacing / 2).Intersects(other))).All(v => v)) break;
            radius += 2;
        }
        Radius = radius; var wanted = angles.Select(a => Box(a, radius)).ToArray();
        RectD Bounded(RectD rect) => rect with { X = Math.Min(Math.Max(rect.X, bounds.X), bounds.MaxX - rect.Width), Y = Math.Min(Math.Max(rect.Y, bounds.Y), bounds.MaxY - rect.Height) };
        var top = Math.Max(anchor.MaxY + 10, wanted.Select(f => f.MaxY).DefaultIfEmpty(anchor.MaxY).Max() + 12);
        var summaries = new[] { new RectD(anchor.MidX - 116, top, 232, 104), new RectD(anchor.MidX - 116, protectedFrame.Y - 120, 232, 104), new RectD(protectedFrame.MaxX + 16, anchor.MidY - 52, 232, 104), new RectD(protectedFrame.X - 248, anchor.MidY - 52, 232, 104) }.Select(Bounded);
        Summary = summaries.FirstOrDefault(r => bounds.Contains(r) && !r.Intersects(protectedFrame));
        if (Summary.Width == 0) Summary = new(bounds.X, bounds.Y, 232, 104);
        var occupied = new List<RectD> { body, label, Summary.Inflate(spacing) }; var placed = new List<RectD>();
        foreach (var preferred in wanted)
        {
            var candidates = new List<RectD> { preferred };
            foreach (var distance in new[] { radius, radius + 90, radius + 180, radius + 270 }) candidates.AddRange(Enumerable.Range(0, 24).Select(i => Box(i * 15, distance)).OrderBy(r => Math.Pow(r.MidX - preferred.MidX, 2) + Math.Pow(r.MidY - preferred.MidY, 2)));
            for (var y = bounds.Y; y <= bounds.MaxY - edge; y += edge + spacing) for (var x = bounds.X; x <= bounds.MaxX - edge; x += edge + spacing) candidates.Add(new(x, y, edge, edge));
            var selected = candidates.FirstOrDefault(r => bounds.Contains(r) && !occupied.Any(o => o.Intersects(r)));
            if (selected.Width > 0) { placed.Add(selected); occupied.Add(selected.Inflate(spacing)); }
        }
        Buttons = placed;
    }
}

public sealed class IdleWaveSchedule
{
    public double? DueAt { get; private set; }
    public double? Delay(double now, bool allowed, bool idle, double random)
    {
        if (!allowed) { DueAt = null; return null; }
        if (DueAt is null) Finished(now, random);
        return idle ? Math.Max(0, DueAt!.Value - now) : null;
    }
    public void Finished(double now, double random) => DueAt = now + 45 + 45 * (double.IsFinite(random) ? Math.Clamp(random, 0, 1) : .5);
}

public static class PetFacing
{
    public static bool Resolve(string motion, bool dragging, bool previous, bool workMirrored, int direction)
    {
        if (dragging || motion == "drag") return previous;
        if (motion == "working") return workMirrored;
        return motion.StartsWith("walk", StringComparison.Ordinal) && direction is 3 or 4 or 5;
    }
}
