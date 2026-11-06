using ZcreSupporter.Core;

internal static class NotificationActivationChecks
{
    internal static void Run(Action<string, bool> check, string repository)
    {
        var now = DateTimeOffset.UtcNow;
        var scope = NotificationActivation.ScopeFor(repository, Json.Hash("account-a"));
        NotificationActivation Parse(string value) => ZcreSupporter.Core.NotificationActivation.Parse("action=alerts;scope=" + value, now)!;
        var queue = new PendingNotificationActivation(); queue.Set(Parse(scope));
        check("notification cold activation waits for verified account", !queue.TakeReady(repository, null, true, now));
        check("notification cold activation drains for matching account", queue.TakeReady(repository, Json.Hash("account-a"), false, now));
        check("notification activation opens only once", !queue.TakeReady(repository, Json.Hash("account-a"), false, now));
        queue.Set(Parse(scope)); check("notification different account rejected", !queue.TakeReady(repository, Json.Hash("account-b"), false, now));
        queue.Set(Parse(scope)); check("notification different data profile rejected", !queue.TakeReady(Path.Combine(repository, "other-profile"), Json.Hash("account-a"), false, now));
        var local = NotificationActivation.ScopeFor(repository, null);
        queue.Set(Parse(local)); check("local test notification only opens unscoped local history", queue.TakeReady(repository, null, true, now));
        queue.Set(Parse(local)); check("local test cannot open account history", !queue.TakeReady(repository, Json.Hash("account-a"), false, now));
        queue.Set(Parse(local)); check("local test cannot open unverified account archive", !queue.TakeReady(repository, null, false, now));
        queue.Set(Parse(scope)); check("notification stale queued activation expires", !queue.TakeReady(repository, Json.Hash("account-a"), false, now.AddMinutes(3)));
        check("notification argument order does not affect activation", ZcreSupporter.Core.NotificationActivation.Parse("scope=" + scope + ";action=alerts", now) is not null);
        foreach (var invalid in new[] { "", "action=other;scope=" + scope, "action=alerts;action=alerts", "action=alerts;scope=" + scope + ";scope=" + scope, "action=alerts;scope=../profile", new string('x', 193) })
            check("notification malformed activation rejected", ZcreSupporter.Core.NotificationActivation.Parse(invalid, now) is null);
        check("notification payload hides directory and account", !scope.Contains(repository, StringComparison.Ordinal) && !scope.Contains("account-a", StringComparison.Ordinal));
        var forwarded = 0; var shown = 0;
        var delivered = SecondaryInstanceActivation.RouteAsync(true, () => { forwarded++; return Task.FromResult(true); }, () => shown++).GetAwaiter().GetResult();
        check("successful secondary notification forwards exactly once without dashboard signal", delivered && forwarded == 1 && shown == 0);
        var rejected = SecondaryInstanceActivation.RouteAsync(true, () => Task.FromResult(false), () => shown++).GetAwaiter().GetResult();
        check("failed secondary notification cannot send ordinary dashboard signal", !rejected && shown == 0);
        SecondaryInstanceActivation.RouteAsync(false, () => { forwarded++; return Task.FromResult(true); }, () => shown++).GetAwaiter().GetResult();
        check("ordinary secondary launch only sends dashboard signal", forwarded == 1 && shown == 1);
        check("notification title truncation does not split emoji", NotificationText.Limit(new string('a', 62) + "🙂tail", 63) == new string('a', 62));
        check("notification body keeps a complete emoji at its boundary", NotificationText.Limit(new string('a', 253) + "🙂tail", 255).EndsWith("🙂", StringComparison.Ordinal));
        check("notification keeps the free test wording", NotificationText.Limit("알림 전달 테스트", 63) == "알림 전달 테스트" && NotificationText.Limit("ZCRE 서포터의 로컬 테스트예요. 작업·크레딧은 사용하지 않았어요.", 255) == "ZCRE 서포터의 로컬 테스트예요. 작업·크레딧은 사용하지 않았어요.");
        check("notification keeps model media and start information", NotificationText.Limit("영상 생성 시작 · Grok", 63) == "영상 생성 시작 · Grok" && NotificationText.Limit("Grok 영상 · 작업이 시작됐어요.", 255) == "Grok 영상 · 작업이 시작됐어요.");
    }
}
