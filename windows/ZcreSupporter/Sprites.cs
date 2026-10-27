using System.Windows.Media.Imaging;

namespace ZcreSupporter;

internal sealed class SpriteClip
{
    public required BitmapSource[] Frames { get; init; }
    public required JsonElement Metadata { get; init; }
    public double Delay => Metadata.GetProperty("delay_ms").GetDouble();
    public double BodyHeight => Metadata.GetProperty("body_h").GetDouble();
    public bool Loop => Metadata.GetProperty("loop").GetBoolean();
    public double Duration => Frames.Length * Delay / 1000;
    public Point GrabAnchor(int frame)
    {
        if (Metadata.TryGetProperty("grab_anchors", out var points) && points.GetArrayLength() == Frames.Length) return new(points[frame][0].GetDouble(), points[frame][1].GetDouble());
        if (Metadata.TryGetProperty("grab_anchor", out var p)) return new(p[0].GetDouble(), p[1].GetDouble());
        return new(Frames[0].PixelWidth / 2d, Frames[0].PixelHeight - BodyHeight * .46);
    }
    public double GrabScale(int frame) => Metadata.TryGetProperty("grab_scales", out var values) && values.GetArrayLength() == Frames.Length ? values[frame].GetDouble() : 1;
    public double GrabRotation => Metadata.TryGetProperty("grab_rotation_degrees", out var value) ? value.GetDouble() : 0;
    public BitmapSource Frame(double elapsed, bool animate = true) => Frames[SpriteTiming.Frame(elapsed, Frames.Length, Delay, Loop, animate)];
}

internal static class Sprites
{
    private static readonly Dictionary<string, SpriteClip> clips = [];
    public static readonly string[] Names = ["still", "idle", "walk", "walk-side", "walk-front", "walk-back", "walk-back-diagonal", "drag", "working", "complete", "cry", "wave", "run"];
    public static SpriteClip Get(string name)
    {
        if (clips.TryGetValue(name, out var found)) return found;
        using var document = JsonDocument.Parse(File.ReadAllText(LocalData.Asset("Zic/" + name + ".json")));
        var metadata = document.RootElement.Clone(); var count = metadata.GetProperty("frames").GetInt32(); var width = metadata.GetProperty("w").GetInt32(); var height = metadata.GetProperty("h").GetInt32();
        var sheet = new BitmapImage(); sheet.BeginInit(); sheet.CacheOption = BitmapCacheOption.OnLoad; sheet.UriSource = new Uri(LocalData.Asset("Zic/" + name + ".png")); sheet.EndInit(); sheet.Freeze();
        if (count is < 1 or > 256 || width < 1 || height < 1 || sheet.PixelWidth != width * count || sheet.PixelHeight != height || metadata.GetProperty("body_h").GetDouble() <= 0 || metadata.GetProperty("delay_ms").GetDouble() <= 0) throw new InvalidDataException("Invalid bundled sprite " + name);
        var frames = Enumerable.Range(0, count).Select(i => { var frame = new CroppedBitmap(sheet, new Int32Rect(i * width, 0, width, height)); frame.Freeze(); return (BitmapSource)frame; }).ToArray();
        var clip = new SpriteClip { Frames = frames, Metadata = metadata }; clips[name] = clip; return clip;
    }
}
