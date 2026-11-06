using System.Xml.Linq;
using ZcreSupporter;
using ZcreSupporter.Core;

internal static class NotificationPayloadChecks
{
    internal static int Run()
    {
        var title = "알림 전달 테스트";
        var body = "ZCRE 서포터의 로컬 테스트예요. 작업·크레딧은 사용하지 않았어요.";
        var scope = NotificationActivation.ScopeFor(AppContext.BaseDirectory, null);
        var alert = new Alert("test", "completed", title, body, DateTimeOffset.UtcNow, false, "notification", null);
        var notification = WindowsNotificationService.BuildNotification(alert, false, scope);
        var xml = XElement.Parse(notification.Payload);
        var launch = xml.Attribute("launch")?.Value ?? throw new InvalidOperationException("SDK payload has no activation argument.");
        if (NotificationActivation.Parse(launch, DateTimeOffset.UtcNow)?.Scope != scope)
            throw new InvalidOperationException("The parser rejected the actual SDK-built launch argument.");
        if (!xml.Descendants("text").Select(value => value.Value).SequenceEqual(new[] { title, body }))
            throw new InvalidOperationException("The real SDK builder changed test notification wording.");
        Console.WriteLine("PASS actual SDK-built launch argument parses and original title/body survive XML round-trip (no Register/Show)");
        var emoji = alert with { Title = new string('a', 62) + "🙂tail", Body = new string('a', 253) + "🙂tail" };
        var bounded = XElement.Parse(WindowsNotificationService.BuildNotification(emoji, false, scope).Payload).Descendants("text").Select(value => value.Value).ToArray();
        if (bounded[0] != new string('a', 62) || !bounded[1].EndsWith("🙂", StringComparison.Ordinal))
            throw new InvalidOperationException("The SDK payload split a UTF-16 surrogate pair.");
        Console.WriteLine("PASS actual SDK payload XML preserves complete surrogate pairs at title/body limits");
        return 0;
    }
}
