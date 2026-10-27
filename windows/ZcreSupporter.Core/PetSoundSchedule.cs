namespace ZcreSupporter.Core;

public enum SoundCommand { PlayGrab, StopGrab, PlayTyping, StopTyping }

public sealed class PetSoundSchedule
{
    private (string Motion, bool Audible, double Volume)? state;
    private bool typing;
    private double started, next;
    public int Revision { get; private set; }
    public bool NeedsTimer => state is { Motion: "working", Audible: true };
    public double Volume => state?.Volume ?? 0;
    public IReadOnlyList<SoundCommand> Update(double now, string motion, bool enabled, double volume, Func<bool> otherAudio)
    {
        var level = double.IsFinite(volume) ? Math.Clamp(volume, 0, 1) : 0;
        var value = (motion, enabled && level > 0, level);
        if (state == value) return [];
        var old = state; state = value; Revision++;
        if (!value.Item2) { typing = false; return [SoundCommand.StopGrab, SoundCommand.StopTyping]; }
        var commands = new List<SoundCommand>();
        if (motion != "drag") commands.Add(SoundCommand.StopGrab);
        else if (old?.Motion != "drag") commands.Add(SoundCommand.PlayGrab);
        if (motion == "working")
        {
            if (old is not { Motion: "working", Audible: true }) { next = now; commands.AddRange(Tick(now, otherAudio)); }
        }
        else { typing = false; commands.Add(SoundCommand.StopTyping); }
        return commands;
    }
    public IReadOnlyList<SoundCommand> Tick(double now, Func<bool> otherAudio)
    {
        if (!NeedsTimer) return [];
        if (typing)
        {
            if (now - started >= 1 || otherAudio()) { typing = false; next = Math.Max(next, now + 2); return [SoundCommand.StopTyping]; }
        }
        else if (now >= next)
        {
            if (otherAudio()) next = now + 2;
            else { typing = true; started = now; next = now + 6; return [SoundCommand.PlayTyping]; }
        }
        return [];
    }
    public void Reset() { state = null; typing = false; next = 0; Revision++; }
}
