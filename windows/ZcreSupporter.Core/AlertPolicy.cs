namespace ZcreSupporter.Core;

public sealed record AlertDecision(Alert Alert, bool Present, string Bubble);

public static class AlertPolicy
{
    public static AlertDecision? Record(MonitorEvent e, Preferences preferences, History history, bool demo, DateTimeOffset now)
    {
        if (e.Job is not null && history.Alerts.Any(a => a.JobKey == e.Job.HistoryKey)) return null;
        if (e.Kind == "completed" && !preferences.CompletionAlerts || e.Kind == "failed" && !preferences.FailureAlerts || e.Kind == "lowCredits" && !preferences.LowCreditAlerts) return null;
        var present = !preferences.IsFocusActive(now.LocalDateTime) && (e.Job is null || preferences.Allows(e.Job));
        string title, body, bubble;
        if (e.Job is { } job)
        {
            var completed = e.Kind == "completed";
            title = job.WorkName + (completed ? " 완료" : " 확인 필요");
            body = job.StartLabel + (completed ? "에 시작한 작업이 완료됐어요. ZCRE에서 결과를 확인해 보세요." : "에 시작한 작업이 실패했어요. ZCRE에서 자세한 내용을 확인해 주세요.");
            bubble = job.WorkName + "\n" + job.StartLabel + (completed ? " 시작 · 작업 완료" : " 시작 · 작업 확인 필요");
        }
        else { title = "크레딧이 얼마 남지 않았어요"; body = "사용 가능한 크레딧이 " + e.Credits?.ToString("#,0.##") + " 남았어요."; bubble = title; }
        var alert = new Alert(Guid.NewGuid().ToString(), e.Kind, (demo ? "[미리보기] " : "") + title, body, now, false, "notification", e.Job?.HistoryKey);
        history.Alerts.Insert(0, alert); history.Trim(); return new(alert, present, bubble);
    }
}
