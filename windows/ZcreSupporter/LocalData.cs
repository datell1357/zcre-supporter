using Microsoft.Win32;

namespace ZcreSupporter;

internal static class LocalData
{
    public static string DirectoryPath { get; private set; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ZCRE Supporter");
    public static void Initialize(string[] args)
    {
        var i = Array.IndexOf(args, "--data-dir");
        if (i >= 0 && i + 1 < args.Length) DirectoryPath = Path.GetFullPath(args[i + 1]);
        Directory.CreateDirectory(DirectoryPath);
    }
    public static string PathFor(string file) => Path.Combine(DirectoryPath, file);
    public static Preferences LoadPreferences()
    {
        try { var p = JsonSerializer.Deserialize<Preferences>(File.ReadAllText(PathFor("preferences.json")), Json.Options) ?? new(); p.PetScale = double.IsFinite(p.PetScale) ? Math.Clamp(p.PetScale, .7, 1.5) : 1; p.PetSoundVolume = double.IsFinite(p.PetSoundVolume) ? Math.Clamp(p.PetSoundVolume, 0, 1) : .35; p.FocusStartMinute = Math.Clamp(p.FocusStartMinute, 0, 1439); p.FocusEndMinute = Math.Clamp(p.FocusEndMinute, 0, 1439); p.LowCreditThreshold = Math.Max(0, p.LowCreditThreshold); return p; }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { return new(); }
    }
    public static bool Save(string filename, object data)
    {
        try { var pending = PathFor(filename + ".pending-" + Guid.NewGuid().ToString("N")); File.WriteAllText(pending, JsonSerializer.Serialize(data, Json.Options)); File.Move(pending, PathFor(filename), true); return true; }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return false; }
    }
    public static string Asset(string relative) => Path.Combine(AppContext.BaseDirectory, "Resources", relative);
    public static bool StartupEnabled
    {
        get { using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run"); return key?.GetValue("ZcreSupporter") is string; }
    }
    public static void SetStartup(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run");
        if (enabled) key.SetValue("ZcreSupporter", "\"" + Environment.ProcessPath + "\" --background");
        else key.DeleteValue("ZcreSupporter", false);
    }
}
