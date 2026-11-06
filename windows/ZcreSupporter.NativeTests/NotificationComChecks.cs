using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.Json;
using Microsoft.Win32;
using ZcreSupporter.Core;

internal static class NotificationComChecks
{
    internal static int Run(string profile, string executable, bool cold = true)
    {
        try
        {
            if (!Path.IsPathFullyQualified(profile) || !Directory.Exists(profile) || !Path.IsPathFullyQualified(executable) || !File.Exists(executable)) throw new ArgumentException("Existing absolute test profile and executable required.");
            var existing = Process.GetProcessesByName("ZcreSupporter");
            if (cold ? existing.Length != 0 : existing.Length != 1 || !string.Equals(existing[0].MainModule?.FileName, executable, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("COM test app process state differs from the requested cold/warm state.");
            using var settings = Registry.CurrentUser.OpenSubKey(@"Software\ZCRE\Supporter\Notifications");
            using var launchProfile = JsonDocument.Parse(settings?.GetValue("LaunchProfile") as string ?? throw new InvalidOperationException("Missing launch profile."));
            if (!string.Equals(launchProfile.RootElement.GetProperty("dataDirectory").GetString(), profile, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("The registered profile is not the supplied isolated test profile.");
            using var appId = Registry.CurrentUser.OpenSubKey(@"Software\Classes\AppUserModelId\ZCRE.Supporter.Windows");
            var classId = Guid.Parse(appId?.GetValue("CustomActivator") as string ?? throw new InvalidOperationException("Missing SDK activator."));
            using var server = Registry.CurrentUser.OpenSubKey(@"Software\Classes\CLSID\" + classId.ToString("B") + @"\LocalServer32");
            if (server?.GetValue("") as string != "\"" + executable + "\" ----AppNotificationActivated:") throw new InvalidOperationException("The registered executable differs from the approved fixed path.");
            var iid = typeof(INotificationActivationCallback).GUID;
            Marshal.ThrowExceptionForHR(CoCreateInstance(ref classId, IntPtr.Zero, 4, ref iid, out var pointer));
            try
            {
                var callback = (INotificationActivationCallback)Marshal.GetObjectForIUnknown(pointer);
                try { callback.Activate("ZCRE.Supporter.Windows", "action=alerts;scope=" + NotificationActivation.ScopeFor(profile, null), IntPtr.Zero, 0); }
                finally { Marshal.ReleaseComObject(callback); }
            }
            finally { Marshal.Release(pointer); }
            var processes = Process.GetProcessesByName("ZcreSupporter");
            if (processes.Length != 1 || !string.Equals(processes[0].MainModule?.FileName, executable, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("COM did not start exactly the registered fixed executable.");
            if (!cold && existing[0].Id != processes[0].Id) throw new InvalidOperationException("Warm activation changed the primary process.");
            Console.WriteLine("PASS Windows COM " + (cold ? "started the registered fixed executable" : "reused the same primary process") + " and accepted INotificationActivationCallback.Activate; PID=" + processes[0].Id);
            Console.WriteLine("This is a direct COM integration check, not an actual notification-card click; verify SDK callback/details separately in the app.");
            return 0;
        }
        catch (Exception error) { Console.WriteLine("FAIL registered notification COM activation: " + error.GetType().Name + " HRESULT=0x" + error.HResult.ToString("X8") + ": " + error.Message); return 1; }
    }

    [ComImport, Guid("53E31837-6600-4A81-9395-75CFFE746F94"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface INotificationActivationCallback
    {
        void Activate([MarshalAs(UnmanagedType.LPWStr)] string appUserModelId, [MarshalAs(UnmanagedType.LPWStr)] string invokedArgs, IntPtr data, uint count);
    }
    [DllImport("ole32.dll", ExactSpelling = true)]
    private static extern int CoCreateInstance(ref Guid classId, IntPtr outer, uint context, ref Guid interfaceId, out IntPtr result);
}
