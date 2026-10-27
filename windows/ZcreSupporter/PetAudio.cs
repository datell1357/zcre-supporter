using System.Runtime.InteropServices;

namespace ZcreSupporter;

internal sealed class PetAudio : IDisposable
{
    private readonly MediaPlayer grab = new(), typing = new();
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromMilliseconds(500) };
    private readonly PetSoundSchedule schedule = new();
    internal event Action<SoundCommand>? CommandApplied;
    public PetAudio() { timer.Tick += (_, _) => Apply(schedule.Tick(CompanionStore.Uptime, OtherAudio.IsActive)); }
    public void Update(string state, bool enabled, double level)
    {
        var revision = schedule.Revision;
        var commands = schedule.Update(CompanionStore.Uptime, state, enabled, level, OtherAudio.IsActive);
        if (revision == schedule.Revision) return;
        grab.Volume = typing.Volume = schedule.Volume;
        Apply(commands);
        if (schedule.NeedsTimer) timer.Start(); else timer.Stop();
    }
    private void Apply(IReadOnlyList<SoundCommand> commands)
    {
        foreach (var command in commands)
        {
            switch (command)
            {
                case SoundCommand.PlayGrab: grab.Open(new Uri(LocalData.Asset("Sounds/grab.wav"))); grab.Volume = schedule.Volume; grab.Play(); break;
                case SoundCommand.StopGrab: grab.Close(); break;
                case SoundCommand.PlayTyping: typing.Open(new Uri(LocalData.Asset("Sounds/typing.wav"))); typing.Volume = schedule.Volume; typing.Play(); break;
                case SoundCommand.StopTyping: typing.Close(); break;
            }
            CommandApplied?.Invoke(command);
        }
    }
    public void Stop() { timer.Stop(); grab.Close(); typing.Close(); schedule.Reset(); }
    public void Dispose() => Stop();
}

// Read-only Core Audio session enumeration: no capture buffers and no device-volume changes.
internal static class OtherAudio
{
    internal readonly record struct ProbeResult(bool Available, bool Active, string? ErrorKind = null);
    public static bool IsActive() { var result = Inspect(); return !result.Available || result.Active; }
    public static ProbeResult Inspect()
    {
        object? enumeratorObject = null;
        var stage = "device-enumerator";
        try
        {
            enumeratorObject = Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E"))!);
            var enumerator = (IDeviceEnumerator)enumeratorObject!;
            for (var flow = 0; flow <= 1; flow++)
            {
                IDeviceCollection? devices = null;
                try
                {
                    stage = "device-collection"; if (enumerator.EnumAudioEndpoints(flow, 1, out devices) != 0) continue;
                    devices.GetCount(out var count);
                    for (uint d = 0; d < count; d++)
                    {
                        IDevice? device = null; object? managerObject = null; ISessionEnumerator? sessions = null;
                        try
                        {
                            stage = "device"; devices.Item(d, out device); var iid = new Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F");
                            stage = "session-manager-activation";
                            if (device.Activate(ref iid, 23, IntPtr.Zero, out managerObject) != 0) continue;
                            stage = "session-manager-cast"; var manager = (ISessionManager)managerObject; stage = "session-enumerator"; manager.GetSessionEnumerator(out sessions); sessions.GetCount(out var length);
                            for (var i = 0; i < length; i++)
                            {
                                ISessionControl? control = null;
                                try
                                {
                                    stage = "session-control"; sessions.GetSession(i, out control); stage = "session-process"; control.GetProcessId(out var pid); control.GetState(out var state);
                                    if (pid == Environment.ProcessId || state != 1) continue;
                                    if (flow == 1) return new(true, true); // An active microphone/communications session also gets priority.
                                    if (control is IAudioMeter meter && meter.GetPeakValue(out var peak) == 0 && peak > .0005f) return new(true, true);
                                }
                                finally { Release(control); }
                            }
                        }
                        finally { Release(sessions); Release(managerObject); Release(device); }
                    }
                }
                finally { Release(devices); }
            }
            return new(true, false);
        }
        catch (Exception error) { return new(false, true, error.GetType().Name + ":" + stage); } // If activity cannot be inspected, keep typing quiet.
        finally { Release(enumeratorObject); }
    }
    private static void Release(object? value) { if (value is not null && Marshal.IsComObject(value)) Marshal.ReleaseComObject(value); }
    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IDeviceEnumerator { [PreserveSig] int EnumAudioEndpoints(int flow, int mask, out IDeviceCollection devices); }
    [ComImport, Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IDeviceCollection { [PreserveSig] int GetCount(out uint count); [PreserveSig] int Item(uint index, out IDevice device); }
    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IDevice { [PreserveSig] int Activate(ref Guid iid, int context, IntPtr parameters, [MarshalAs(UnmanagedType.IUnknown)] out object value); }
    [ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface ISessionManager
    {
        [PreserveSig] int GetAudioSessionControl(ref Guid id, uint flags, out IntPtr control);
        [PreserveSig] int GetSimpleAudioVolume(ref Guid id, uint flags, out IntPtr volume);
        [PreserveSig] int GetSessionEnumerator(out ISessionEnumerator sessions);
    }
    [ComImport, Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface ISessionEnumerator { [PreserveSig] int GetCount(out int count); [PreserveSig] int GetSession(int index, out ISessionControl control); }
    [ComImport, Guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface ISessionControl
    {
        [PreserveSig] int GetState(out int state);
        [PreserveSig] int GetDisplayName([MarshalAs(UnmanagedType.LPWStr)] out string name);
        [PreserveSig] int SetDisplayName(string name, ref Guid context);
        [PreserveSig] int GetIconPath([MarshalAs(UnmanagedType.LPWStr)] out string path);
        [PreserveSig] int SetIconPath(string path, ref Guid context);
        [PreserveSig] int GetGroupingParam(out Guid id);
        [PreserveSig] int SetGroupingParam(ref Guid id, ref Guid context);
        [PreserveSig] int RegisterAudioSessionNotification(IntPtr client);
        [PreserveSig] int UnregisterAudioSessionNotification(IntPtr client);
        [PreserveSig] int GetSessionIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string id);
        [PreserveSig] int GetSessionInstanceIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string id);
        [PreserveSig] int GetProcessId(out uint id);
    }
    [ComImport, Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAudioMeter { [PreserveSig] int GetPeakValue(out float peak); }
}
