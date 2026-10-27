using System.Diagnostics;
using System.Windows;
using ZcreSupporter;
using ZcreSupporter.Core;

internal static class AudioChecks
{
    internal static int Run()
    {
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        app.Startup += async (_, _) =>
        {
            Process? source = null;
            try
            {
                var baseline = OtherAudio.Inspect();
                if (!baseline.Available) throw new InvalidOperationException("Core Audio unavailable");
                if (baseline.Active) { Console.WriteLine("PARTIAL audio coexistence: another session already active; no other app interrupted"); app.Shutdown(0); return; }
                source = Process.Start(new ProcessStartInfo(Environment.ProcessPath!, "--audio-source") { UseShellExecute = false, CreateNoWindow = true }) ?? throw new InvalidOperationException();
                var deadline = DateTime.UtcNow.AddSeconds(4);
                while (!OtherAudio.IsActive() && !source.HasExited && DateTime.UtcNow < deadline) await Task.Delay(50);
                if (!OtherAudio.Inspect().Active) throw new InvalidOperationException("Separate sound source not detected");
                using var audio = new PetAudio(); var commands = new List<SoundCommand>(); audio.CommandApplied += commands.Add;
                audio.Update("working", true, .15); await Task.Delay(750);
                if (commands.Contains(SoundCommand.PlayTyping)) throw new InvalidOperationException("Typing overlapped separate source");
                Console.WriteLine("PASS actual separate-process WAV peak detected; real PetAudio suppressed typing command");
                await source.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(8));
                await Task.Delay(300);
                if (OtherAudio.Inspect().Active) { Console.WriteLine("PARTIAL resume: another session became active; no other app interrupted"); app.Shutdown(0); return; }
                audio.Update("idle", true, .15); audio.Update("working", true, .15); await Task.Delay(250);
                if (!commands.Contains(SoundCommand.PlayTyping)) throw new InvalidOperationException("Typing did not resume");
                audio.Stop(); Console.WriteLine("PASS real PetAudio resumed typing after separate sound ended; no capture or device-volume change");
                app.Shutdown(0);
            }
            catch (Exception error) { Console.WriteLine("FAIL audio coexistence: " + error.GetType().Name); app.Shutdown(1); }
            finally { source?.Dispose(); }
        };
        return app.Run();
    }
}
