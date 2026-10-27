using System.Runtime.InteropServices;

namespace ZcreSupporter;

internal sealed class PetAudio : IDisposable
{
    private readonly MediaPlayer grab = new(), typing = new();
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromMilliseconds(500) };
    private string motion = "idle";
    private bool audible, typingActive;
    private double volume, began, next;
    public PetAudio() { timer.Tick += (_, _) => Tick(); }
    public void Update(string state, bool enabled, double level)
    {
        var enteringDrag = state == "drag" && motion != "drag";
        var enteringWork = state == "working" && (motion != "working" || !audible);
        motion = state; audible = enabled && level > 0; volume = Math.Clamp(level, 0, 1);
        grab.Volume = typing.Volume = volume;
        if (!audible) { Stop(); return; }
        if (state != "drag") grab.Close();
        if (enteringDrag) { grab.Open(new Uri(LocalData.Asset("Sounds/grab.wav"))); grab.Play(); }
        if (state == "working") { if (enteringWork) next = 0; timer.Start(); Tick(); }
        else { timer.Stop(); typing.Close(); typingActive = false; }
    }
    private void Tick()
    {
        if (!audible || motion != "working") return;
        var now = CompanionStore.Uptime;
        if (typingActive && (now - began >= 1 || OtherAudio.IsActive())) { typing.Close(); typingActive = false; next = Math.Max(next, now + 2); }
        else if (!typingActive && now >= next)
        {
            if (OtherAudio.IsActive()) next = now + 2;
            else { typing.Open(new Uri(LocalData.Asset("Sounds/typing.wav"))); typing.Volume = volume; typing.Play(); typingActive = true; began = now; next = now + 6; }
        }
    }
    public void Stop() { timer.Stop(); grab.Close(); typing.Close(); typingActive = false; audible = false; }
    public void Dispose() => Stop();
}

// Read-only Core Audio session enumeration: no capture buffers and no device-volume changes.
internal static class OtherAudio
{
    public static bool IsActive()
    {
        object? enumeratorObject = null;
        try
        {
            enumeratorObject = Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E"))!);
            var enumerator = (IDeviceEnumerator)enumeratorObject!;
            for (var flow = 0; flow <= 1; flow++)
            {
                IDeviceCollection? devices = null;
                try
                {
                    if (enumerator.EnumAudioEndpoints(flow, 1, out devices) != 0) continue;
                    devices.GetCount(out var count);
                    for (uint d = 0; d < count; d++)
                    {
                        IDevice? device = null; object? managerObject = null; ISessionEnumerator? sessions = null;
                        try
                        {
                            devices.Item(d, out device); var iid = new Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F");
                            if (device.Activate(ref iid, 23, IntPtr.Zero, out managerObject) != 0) continue;
                            var manager = (ISessionManager)managerObject; manager.GetSessionEnumerator(out sessions); sessions.GetCount(out var length);
                            for (var i = 0; i < length; i++)
                            {
                                ISessionControl? control = null;
                                try
                                {
                                    sessions.GetSession(i, out control); control.GetProcessId(out var pid); control.GetState(out var state);
                                    if (pid == Environment.ProcessId || state != 1) continue;
                                    if (flow == 1) return true; // An active microphone/communications session also gets priority.
                                    if (control is IAudioMeter meter && meter.GetPeakValue(out var peak) == 0 && peak > .0005f) return true;
                                }
                                finally { Release(control); }
                            }
                        }
                        finally { Release(sessions); Release(managerObject); Release(device); }
                    }
                }
                finally { Release(devices); }
            }
            return false;
        }
        catch { return true; } // If activity cannot be inspected, keep typing quiet.
        finally { Release(enumeratorObject); }
    }
    private static void Release(object? value) { if (value is not null && Marshal.IsComObject(value)) Marshal.ReleaseComObject(value); }
    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IDeviceEnumerator { [PreserveSig] int EnumAudioEndpoints(int flow, int mask, out IDeviceCollection devices); }
    [ComImport, Guid("0BD7A1BE-7A1A-44DB-8397-C0A9DFAE2734"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
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
