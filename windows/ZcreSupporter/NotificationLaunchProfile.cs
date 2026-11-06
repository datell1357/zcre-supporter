using Microsoft.Win32;

namespace ZcreSupporter;

internal sealed record NotificationLaunchProfile(int Version, string DataDirectory, bool SoftwareRendering)
{
    internal const string RegistryPath = @"Software\ZCRE\Supporter\Notifications";
    private const string ValueName = "LaunchProfile";
    public static bool IsActivation(string[] args) => args.Contains("----AppNotificationActivated:", StringComparer.Ordinal);

    public static string[]? Restore()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RegistryPath);
            if (key?.GetValue(ValueName) is not string text || text.Length > 8192) return null;
            var value = JsonSerializer.Deserialize<NotificationLaunchProfile>(text, Json.Options);
            if (value is not { Version: 1 } || !Path.IsPathFullyQualified(value.DataDirectory) || !Directory.Exists(value.DataDirectory)) return null;
            var directory = Path.GetFullPath(value.DataDirectory);
            return value.SoftwareRendering ? ["--data-dir", directory, "--software-rendering"] : ["--data-dir", directory];
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.Security.SecurityException or JsonException or ArgumentException) { return null; }
    }

    public static void Save(string dataDirectory, bool softwareRendering)
    {
        var value = new NotificationLaunchProfile(1, Path.GetFullPath(dataDirectory), softwareRendering);
        using var key = Registry.CurrentUser.CreateSubKey(RegistryPath);
        key.SetValue(ValueName, JsonSerializer.Serialize(value, Json.Options), RegistryValueKind.String);
    }
}
