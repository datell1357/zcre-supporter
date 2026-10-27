using System.Globalization;

namespace ZcreSupporter.Core;

public sealed class Preferences
{
    public bool HasLaunched { get; set; }
    public bool NotificationsReviewed { get; set; }
    public bool PetVisible { get; set; } = true;
    public bool Roaming { get; set; } = true;
    public double PetScale { get; set; } = 1;
    public bool ShowTrayCredits { get; set; } = true;
    public bool BannerAlerts { get; set; } = true;
    public bool CompletionAlerts { get; set; } = true;
    public bool FailureAlerts { get; set; } = true;
    public bool LowCreditAlerts { get; set; } = true;
    public bool ImageJobAlerts { get; set; } = true;
    public bool VideoJobAlerts { get; set; } = true;
    public bool UpscaleJobAlerts { get; set; } = true;
    public bool AudioJobAlerts { get; set; } = true;
    public bool OtherJobAlerts { get; set; } = true;
    public bool FocusNow { get; set; }
    public bool FocusSchedule { get; set; }
    public int FocusStartMinute { get; set; } = 1320;
    public int FocusEndMinute { get; set; } = 480;
    public bool NotificationSound { get; set; }
    public bool PetSounds { get; set; } = true;
    public double PetSoundVolume { get; set; } = .35;
    public decimal LowCreditThreshold { get; set; } = 50;
    public double? PetX { get; set; }
    public double? PetY { get; set; }
    public bool IsFocusActive(DateTime local)
    {
        if (FocusNow) return true;
        if (!FocusSchedule) return false;
        var minute = local.Hour * 60 + local.Minute;
        return FocusStartMinute == FocusEndMinute || (FocusStartMinute < FocusEndMinute ? minute >= FocusStartMinute && minute < FocusEndMinute : minute >= FocusStartMinute || minute < FocusEndMinute);
    }
    public bool Allows(Job job) => job.Model.Contains("upscale", StringComparison.OrdinalIgnoreCase) ? UpscaleJobAlerts : job.MediaType switch { "image" => ImageJobAlerts, "video" => VideoJobAlerts, "audio" => AudioJobAlerts, _ => OtherJobAlerts };
}

public sealed class AccountSchedule
{
    public double Next { get; private set; }
    public void Resume(double now, double jitter) => Next = now + Math.Clamp(jitter, 0, 1);
    public void Started(double now) => Next = now + 5;
    public void Finished(double started, double now, int failures, bool signedOut, double jitter)
    {
        var interval = signedOut ? 15 : failures > 0 ? Math.Min(300, 15 * Math.Pow(2, Math.Min(failures, 5)) * (1 + Math.Clamp(jitter, 0, 1) * .2)) : 5;
        Next = Math.Max(now + 1, started + interval);
    }
    public static double RetryAfter(string? value, DateTimeOffset now)
    {
        if (double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out var seconds) && double.IsFinite(seconds)) return Math.Max(0, seconds);
        return DateTimeOffset.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var date) ? Math.Max(0, (date - now).TotalSeconds) : 0;
    }
}

public sealed class PublicSchedule
{
    public double LastAttempt { get; private set; } = -5;
    public double LastSuccess { get; private set; } = -60;
    public double RetryAt { get; private set; }
    public int Failures { get; private set; }
    public double Next(bool manual) => Math.Max(Math.Max(LastAttempt + 5, RetryAt), manual ? 0 : LastSuccess + 60);
    public bool Begin(double now, bool manual) { if (now < Next(manual)) return false; LastAttempt = now; return true; }
    public void Success(double now) { LastSuccess = now; RetryAt = 0; Failures = 0; }
    public void Fail(double now, double serverDelay, double jitter) { Failures = Math.Min(5, Failures + 1); RetryAt = now + Math.Max(serverDelay, Math.Min(300, 15 * Math.Pow(2, Failures) * (1 + Math.Clamp(jitter, 0, 1) * .2))); }
}

public sealed class BridgeEpoch
{
    public int Generation { get; private set; }
    public string AcceptedRevision { get; private set; } = "";
    private (int Generation, string Revision, string Workspace)? candidate;
    public void Reset() { Generation++; AcceptedRevision = ""; candidate = null; }
    public bool Candidate(int generation, string revision, string workspace)
    {
        if (generation != Generation) return false;
        candidate = (generation, revision, workspace); return true;
    }
    public bool Accept(string revision, string workspace)
    {
        if (candidate != (Generation, revision, workspace)) return false;
        AcceptedRevision = revision; candidate = null; return true;
    }
    public static bool TrustedOrigin(string source) => Uri.TryCreate(source, UriKind.Absolute, out var uri) && uri.Scheme == "https" && uri.IsDefaultPort && uri.UserInfo.Length == 0 && uri.Host is "www.zcre.co.kr" or "zcre.co.kr";
}

public sealed class ConnectionPresentation
{
    private bool hideAfterVerifiedSnapshot;
    public void Open(bool needsConnection) => hideAfterVerifiedSnapshot = needsConnection;
    public bool VerifiedSnapshot()
    {
        var hide = hideAfterVerifiedSnapshot; hideAfterVerifiedSnapshot = false; return hide;
    }
    public void Reset() => hideAfterVerifiedSnapshot = false;
}

public readonly record struct Point(double X, double Y)
{
    public static Point Step(Point start, Point end, double distance)
    {
        var length = Math.Sqrt(Math.Pow(end.X - start.X, 2) + Math.Pow(end.Y - start.Y, 2));
        return length <= distance || length == 0 ? end : new(start.X + (end.X - start.X) * distance / length, start.Y + (end.Y - start.Y) * distance / length);
    }
}

public static class SpriteTiming
{
    public static int Frame(double elapsed, int count, double delayMs, bool loop, bool animate = true)
    {
        if (!animate || elapsed <= 0 || count <= 1) return 0;
        var frame = (int)Math.Min(int.MaxValue, elapsed * 1000 / delayMs);
        return loop ? frame % count : Math.Min(count - 1, frame);
    }
}
