using System.Runtime.InteropServices;
using Microsoft.Windows.AppNotifications;
using Microsoft.Windows.AppNotifications.Builder;

namespace ZcreSupporter;

internal sealed class WindowsNotificationService : IDisposable
{
    private const string ApplicationUserModelId = "ZCRE.Supporter.Windows";
    private const string DisplayName = "ZCRE 서포터";
    private const int MaxScopeLength = 96;
    private AppNotificationManager? manager;
    private Action<string>? activated;
    private bool registered;

    public void Register(Action<string> onActivated)
    {
        ArgumentNullException.ThrowIfNull(onActivated);
        if (registered) return;
        var manager = GetManager();
        activated = onActivated;
        manager.NotificationInvoked += NotificationInvoked;
        try
        {
            manager.Register(DisplayName, IconUri());
            registered = true;
        }
        catch
        {
            manager.NotificationInvoked -= NotificationInvoked;
            activated = null;
            throw;
        }
    }

    public bool Notify(Alert alert, bool sound, string scope)
    {
        ArgumentNullException.ThrowIfNull(alert);
        var manager = this.manager;
        if (!registered || manager is null || !ValidScope(scope)) return false;
        try
        {
            var notification = BuildNotification(alert, sound, scope);
            manager.Show(notification);
            return notification.Id != 0;
        }
        catch (COMException)
        {
            return false;
        }
        catch (InvalidOperationException)
        {
            return false;
        }
        catch (ArgumentException)
        {
            return false;
        }
    }

    internal static AppNotification BuildNotification(Alert alert, bool sound, string scope)
    {
        var builder = new AppNotificationBuilder()
            .AddArgument("action", "alerts")
            .AddArgument("scope", scope)
            .AddText(NotificationText.Limit(alert.Title, 63))
            .AddText(NotificationText.Limit(alert.Body, 255));
        if (!sound) builder.MuteAudio();
        return builder.BuildNotification();
    }

    public void Dispose()
    {
        var manager = this.manager;
        if (!registered || manager is null) return;
        manager.NotificationInvoked -= NotificationInvoked;
        try { manager.Unregister(); }
        catch (Exception error) when (error is COMException or InvalidOperationException)
        {
            System.Diagnostics.Trace.WriteLine("Notification unregister failed: " + error.GetType().Name);
        }
        finally { registered = false; activated = null; }
    }

    private AppNotificationManager GetManager()
    {
        if (manager is not null) return manager;
        var result = SetCurrentProcessExplicitAppUserModelID(ApplicationUserModelId);
        if (result < 0) Marshal.ThrowExceptionForHR(result);
        return manager = AppNotificationManager.Default;
    }

    private static Uri IconUri() => new(Path.Combine(AppContext.BaseDirectory, "Resources", "Zic", "still.png"), UriKind.Absolute);
    private void NotificationInvoked(AppNotificationManager sender, AppNotificationActivatedEventArgs args) => activated?.Invoke(args.Argument);
    private static bool ValidScope(string scope) => scope.Length is > 0 and <= MaxScopeLength && scope.All(c => c is >= 'a' and <= 'z' or >= 'A' and <= 'Z' or >= '0' and <= '9' or '-' or '_' or '.');

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
}
