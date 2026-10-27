using System.Diagnostics;
using System.IO;
using ZcreSupporter;

internal static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        if (args.Length != 1 || !Path.IsPathFullyQualified(args[0])) throw new ArgumentException("An absolute workspace-local test-data directory is required.");
        LocalData.Initialize(["--data-dir", args[0]]);
        var timer = Stopwatch.StartNew(); var audio = OtherAudio.Inspect();
        if (!audio.Available) throw new InvalidOperationException("Core Audio probe unavailable: " + audio.ErrorKind);
        Console.WriteLine("PASS actual Core Audio session/peak API enumeration available (read only)");
        Console.WriteLine("Probe duration milliseconds: " + timer.ElapsedMilliseconds);
        File.WriteAllText(LocalData.PathFor("preferences.json"), "{\"petScale\":1e999,\"petSoundVolume\":-100,\"petX\":1e999,\"focusStartMinute\":-20,\"focusEndMinute\":2000}");
        var preferences = LocalData.LoadPreferences();
        if (preferences.PetScale != 1 || preferences.PetSoundVolume != 0 || preferences.PetX is not null || preferences.FocusStartMinute != 0 || preferences.FocusEndMinute != 1439) throw new InvalidOperationException("Invalid persisted preferences were not normalized.");
        Console.WriteLine("PASS actual local preference reader normalizes non-finite and out-of-range values");
        preferences.PetScale = 1.2;
        if (!LocalData.Save("preferences.json", preferences) || LocalData.LoadPreferences().PetScale != 1.2 || Directory.EnumerateFiles(LocalData.DirectoryPath, "*.pending-*").Any()) throw new InvalidOperationException("Atomic preference replacement failed.");
        Console.WriteLine("PASS actual atomic local preference save/read leaves no pending file");
        Console.WriteLine("Native integration checks passed: 3");
        return 0;
    }
}
