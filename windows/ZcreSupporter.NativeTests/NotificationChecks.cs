using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using ZcreSupporter;

internal static class NotificationChecks
{
    internal static int LocalState(string directory)
    {
        if (!Path.IsPathFullyQualified(directory) || Directory.Exists(directory)) throw new ArgumentException();
        LocalData.Initialize(["--data-dir", directory]);
        var accountArchive = LocalData.PathFor("RecentAlerts.json");
        const string original = "{\"workspaceHash\":\"private-test-workspace\",\"alerts\":[]}";
        File.WriteAllText(accountArchive, original);
        string alertId;
        using (var store = new CompanionStore())
        {
            store.TestNotification();
            alertId = store.History.Alerts.Single().Id;
        }
        using (var restored = new CompanionStore())
        {
            if (restored.History.Alerts.Single().Id != alertId || restored.History.WorkspaceHash.Length != 0)
                throw new InvalidOperationException("Local free test alert did not survive a cold store reload.");
            if (File.ReadAllText(accountArchive) != original)
                throw new InvalidOperationException("Local free test changed the account archive.");
            Console.WriteLine("PASS local free test alert survives cold reload and preserves the separate account archive byte for byte");
            using var diagnostics = System.Text.Json.JsonDocument.Parse(System.Text.Json.JsonSerializer.Serialize(restored.Diagnostics()));
            var expected = new[] { "formatVersion", "appVersion", "windows", "architecture", "generatedAt", "connection", "IsRefreshing", "IsDemo", "activeJobCount", "unreadAlertCount", "PetVisible", "PetScale", "displayCount", "notificationActivationTrace" };
            if (!diagnostics.RootElement.EnumerateObject().Select(property => property.Name).Order().SequenceEqual(expected.Order()))
                throw new InvalidOperationException("Diagnostics contains an unexpected field.");
            var json = diagnostics.RootElement.GetRawText();
            if (json.Contains(alertId, StringComparison.Ordinal) || json.Contains(directory, StringComparison.OrdinalIgnoreCase) || json.Contains("private-test-workspace", StringComparison.Ordinal))
                throw new InvalidOperationException("Diagnostics exposed an identifier or profile path.");
            Console.WriteLine("PASS diagnostics allowlist excludes alert identifiers, workspace identifiers and profile paths (data inspection, not GUI export)");
            restored.DisconnectAsync().GetAwaiter().GetResult();
        }
        using (var disconnected = new CompanionStore())
        {
            using var account = System.Text.Json.JsonDocument.Parse(File.ReadAllText(accountArchive));
            if (disconnected.History.Alerts.Count != 0 || account.RootElement.GetProperty("workspaceHash").GetString() != "" || account.RootElement.GetProperty("alerts").GetArrayLength() != 0)
                throw new InvalidOperationException("Disconnect left a notification archive that reappears after cold reload.");
            Console.WriteLine("PASS disconnect clears both isolated archives and local test alerts do not reappear after cold reload (no initialized browser profile)");
        }
        return 0;
    }

    private const int BalloonShow = 0x402;
    private const int BalloonHide = 0x403;
    private const int BalloonTimeout = 0x404;
    private const int BalloonUserClick = 0x405;

    internal static int Run(string directory)
    {
        if (!Path.IsPathFullyQualified(directory) || Directory.Exists(directory)) throw new ArgumentException();
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        app.Startup += async (_, _) =>
        {
            try
            {
                LocalData.Initialize(["--data-dir", directory]);
                using var store = new CompanionStore();
                using var tray = new TrayIcon(store);

                // Request A is accepted, then request B is rejected. Untagged callbacks below are deliberately treated as old events.
                store.SetNotificationStatus(true);
                Require(store, NotificationRequestState.Requested, null, "accepted request was not reported");
                store.SetNotificationStatus(false);
                Require(store, NotificationRequestState.Rejected, null, "rejected request was not reported");

                var opens = 0;
                tray.OpenAlerts += () => opens++;
                SendCallback(tray, BalloonShow);
                Require(store, NotificationRequestState.Rejected, NotificationEventState.Shown, "old NIN_BALLOONSHOW changed the latest rejected request");
                SendCallback(tray, BalloonHide);
                Require(store, NotificationRequestState.Rejected, NotificationEventState.Hidden, "old NIN_BALLOONHIDE changed the latest rejected request");
                SendCallback(tray, BalloonTimeout);
                Require(store, NotificationRequestState.Rejected, NotificationEventState.TimedOut, "old NIN_BALLOONTIMEOUT changed the latest rejected request");
                RequireStatus(store, "최근 요청 결과: Windows에 전달하지 못했어요.", "마지막 Windows 알림 이벤트: 표시 시간이 끝났어요.");

                store.SetNotificationStatus(true);
                Require(store, NotificationRequestState.Requested, NotificationEventState.TimedOut, "accepted request erased the last callback event");
                RequireStatus(store, "최근 요청 결과: Windows에 표시를 요청했어요.", "마지막 Windows 알림 이벤트: 표시 시간이 끝났어요.");
                if (opens != 0) throw new InvalidOperationException("Lifecycle callbacks opened alerts before the user-click callback.");
                SendCallback(tray, BalloonUserClick);
                SendCallback(tray, BalloonUserClick);
                Require(store, NotificationRequestState.Requested, NotificationEventState.Clicked, "NIN_BALLOONUSERCLICK was not reported");
                await app.Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle);
                if (opens != 2) throw new InvalidOperationException("Each NIN_BALLOONUSERCLICK callback must open alerts once. Actual=" + opens);

                Console.WriteLine("PASS synthetic callback routing/state ordering keeps latest request separate from old SHOW/HIDE/TIMEOUT events");
                Console.WriteLine("PASS two synthetic NIN_BALLOONUSERCLICK callbacks produced two OpenAlerts invocations, one per callback");
                Console.WriteLine("PASS callback regression is separate from actual OS delivery and banner visual QA");
                app.Shutdown(0);
            }
            catch (Exception error) { Console.WriteLine("FAIL notification lifecycle: " + error.GetType().Name + ": " + error.Message); app.Shutdown(1); }
        };
        return app.Run();
    }

    private static void SendCallback(TrayIcon tray, int callback) => SendMessage(tray.Handle, TrayIcon.CallbackMessage, IntPtr.Zero, new IntPtr(callback));
    private static void Require(CompanionStore store, NotificationRequestState? request, NotificationEventState? notificationEvent, string message)
    {
        if (store.LatestNotificationRequest != request || store.LastNotificationEvent != notificationEvent)
            throw new InvalidOperationException(message + ". Actual request=" + store.LatestNotificationRequest + ", event=" + store.LastNotificationEvent);
    }
    private static void RequireStatus(CompanionStore store, string requestText, string eventText)
    {
        if (!store.NotificationStatus.Contains(requestText, StringComparison.Ordinal) || !store.NotificationStatus.Contains(eventText, StringComparison.Ordinal) || !store.NotificationStatus.Contains("같은 요청인지 확인할 수 없어요.", StringComparison.Ordinal))
            throw new InvalidOperationException("Notification status did not label uncorrelated request/event facts. Actual=" + store.NotificationStatus);
    }

    [DllImport("user32.dll", EntryPoint = "SendMessageW")]
    private static extern IntPtr SendMessage(IntPtr handle, uint message, IntPtr wParam, IntPtr lParam);
}
