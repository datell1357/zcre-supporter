namespace ZcreSupporter.Core;

public sealed record NotificationActivation(string Scope, DateTimeOffset ReceivedAt)
{
    public const int MaximumArgumentLength = 192;
    public static string ScopeFor(string dataDirectory, string? workspaceHash)
    {
        if (!Path.IsPathFullyQualified(dataDirectory)) throw new ArgumentException("An absolute profile directory is required.", nameof(dataDirectory));
        var directory = Path.GetFullPath(dataDirectory).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar).ToUpperInvariant();
        return (workspaceHash is null ? "test." : "job.") + Json.Hash("zcre-notification-v1\0" + directory + "\0" + workspaceHash);
    }

    public static NotificationActivation? Parse(string argument, DateTimeOffset now)
    {
        if (argument.Length > MaximumArgumentLength) return null;
        var parts = argument.Split(';');
        if (parts.Length != 2 || parts.Count(p => p == "action=alerts") != 1 || parts.Count(p => p.StartsWith("scope=", StringComparison.Ordinal)) != 1) return null;
        var scope = parts.Single(p => p.StartsWith("scope=", StringComparison.Ordinal))[6..];
        var prefix = scope.StartsWith("test.", StringComparison.Ordinal) ? 5 : scope.StartsWith("job.", StringComparison.Ordinal) ? 4 : 0;
        if (prefix == 0 || scope.Length != prefix + 64 || !scope.AsSpan(prefix).ToArray().All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f')) return null;
        return new(scope, now);
    }
}

public static class SecondaryInstanceActivation
{
    public static async Task<bool> RouteAsync(bool notification, Func<Task<bool>> forwardNotification, Action showDashboard)
    {
        if (notification) return await forwardNotification();
        showDashboard(); return true;
    }
}

public sealed class PendingNotificationActivation
{
    private NotificationActivation? pending;
    public void Set(NotificationActivation activation) => pending = activation;
    public void Clear() => pending = null;
    public bool TakeReady(string directory, string? verifiedWorkspaceHash, bool localHistoryOnly, DateTimeOffset now)
    {
        var value = pending;
        if (value is null) return false;
        if (now - value.ReceivedAt > TimeSpan.FromMinutes(2) || value.ReceivedAt > now) { Clear(); return false; }
        if (value.Scope.StartsWith("job.", StringComparison.Ordinal) && verifiedWorkspaceHash is null) return false;
        Clear();
        if (value.Scope.StartsWith("test.", StringComparison.Ordinal) && (verifiedWorkspaceHash is not null || !localHistoryOnly)) return false;
        return value.Scope == NotificationActivation.ScopeFor(directory, verifiedWorkspaceHash);
    }
}
