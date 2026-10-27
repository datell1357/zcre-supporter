using System.Net.NetworkInformation;

namespace ZcreSupporter;

internal sealed class CompanionStore : IDisposable
{
    public Preferences Preferences { get; } = LocalData.LoadPreferences();
    public WebSession Session { get; } = new();
    public Snapshot? Snapshot { get; private set; }
    public History History { get; private set; } = new();
    public bool IsDemo { get; private set; }
    public bool IsRefreshing { get; private set; }
    public bool IsSleeping { get; private set; }
    public bool IsOffline { get; private set; }
    public bool DebugEnabled { get; private set; }
    public bool FocusActive => Preferences.IsFocusActive(DateTime.Now);
    public string Connection { get; private set; } = "연결 대기";
    public string NotificationStatus { get; private set; } = "Windows 알림 허용 여부는 아직 확인하지 않았어요.";
    public string? Bubble { get; private set; }
    public DateTimeOffset? Celebration { get; private set; }
    public DateTimeOffset? Failure { get; private set; }
    public string CreditText => Snapshot is null ? "—" : Balance.Format(Snapshot.Balance.Available);
    public int ActiveCount => Snapshot?.ActiveJobs.Count ?? 0;
    private readonly Monitor monitor = new();
    private readonly AccountSchedule schedule = new();
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(1) };
    private CancellationTokenSource cancellation = new();
    private int generation, failures;
    private bool forceBalance, allowed = true, focusWasActive;
    private DateTimeOffset bubbleUntil;
    private string savedHistory = "";
    public event Action? Changed;
    public event Action<Alert>? AlertRaised;
    public event Action? ResetAlerts;
    public static double Uptime => Environment.TickCount64 / 1000d;

    public CompanionStore()
    {
        Session.Ready += () => { if (!IsDemo) { schedule.Resume(Uptime, Random.Shared.NextDouble()); timer.Start(); } };
        Session.AccountChanged += () => { if (!IsDemo) { Cancel(); Snapshot = null; monitor.Reset(); History = new(); Connection = "계정 확인 중"; ResetAlerts?.Invoke(); schedule.Resume(Uptime, Random.Shared.NextDouble()); Changed?.Invoke(); } };
        NetworkChange.NetworkAvailabilityChanged += NetworkChanged;
        timer.Tick += async (_, _) =>
        {
            if (Bubble is not null && DateTimeOffset.UtcNow >= bubbleUntil) { Bubble = null; Changed?.Invoke(); }
            if (focusWasActive != FocusActive) { focusWasActive = FocusActive; if (FocusActive) { Celebration = Failure = null; Bubble = null; ResetAlerts?.Invoke(); } Changed?.Invoke(); }
            if (!IsDemo && !IsSleeping && !IsOffline && allowed && !IsRefreshing && Uptime >= schedule.Next && DateTimeOffset.UtcNow >= Session.RetryNotBefore) await RefreshAsync();
        };
    }
    public async Task StartAsync(bool demo)
    {
        timer.Start();
        if (demo) EnterDemo();
        else { Connection = "연결 확인 중"; Changed?.Invoke(); try { await Session.StartAsync(); } catch { Connection = "웹 세션을 시작하지 못했어요 · WebView2 런타임을 확인해 주세요"; Changed?.Invoke(); } }
    }
    private void NetworkChanged(object? sender, NetworkAvailabilityEventArgs e) => Application.Current.Dispatcher.BeginInvoke(() =>
    {
        IsOffline = !e.IsAvailable;
        if (IsOffline) { Cancel(); Connection = "오프라인 · 마지막 확인값"; }
        else schedule.Resume(Uptime, Random.Shared.NextDouble());
        Changed?.Invoke();
    });
    private void Cancel() { generation++; cancellation.Cancel(); cancellation.Dispose(); cancellation = new(); IsRefreshing = false; }
    public void Sleep() { IsSleeping = true; Cancel(); _ = Session.AbortAsync(); Changed?.Invoke(); }
    public void Wake() { IsSleeping = false; schedule.Resume(Uptime, Random.Shared.NextDouble()); Changed?.Invoke(); }
    public async Task ConnectAsync()
    {
        if (IsDemo) LeaveDemo();
        allowed = true; Connection = "연결 확인 중"; Changed?.Invoke();
        try { await Session.ReconnectAsync(Snapshot is null); } catch { Connection = "계정 창을 열지 못했어요"; Changed?.Invoke(); }
    }
    public void RequestRefresh(bool balance = false)
    {
        if (IsDemo) return;
        forceBalance |= balance;
        // Presentation/manual calls share the same five-second and Retry-After schedule.
        if (!IsRefreshing && !IsSleeping && !IsOffline && allowed && Uptime >= schedule.Next && DateTimeOffset.UtcNow >= Session.RetryNotBefore) _ = RefreshAsync();
    }
    private async Task RefreshAsync()
    {
        if (IsRefreshing || !Session.Loaded) { schedule.Resume(Uptime + 4, 1); return; }
        IsRefreshing = true; var thisGeneration = generation; var started = Uptime; schedule.Started(started);
        var force = forceBalance; forceBalance = false;
        try
        {
            var candidate = await Session.SnapshotAsync(monitor.ActiveIds, Snapshot, force, cancellation.Token);
            if (generation != thisGeneration || !Session.Accept(candidate.Revision, candidate.Snapshot)) return;
            Apply(candidate.Snapshot); failures = 0;
            Connection = candidate.Snapshot.BalanceIsStale ? "크레딧 갱신 지연 · 작업 상태 최신" : "연결됨";
            Session.CompleteConnection();
        }
        catch (OperationCanceledException) { }
        catch (Exception error)
        {
            if (generation != thisGeneration) return;
            failures++;
            var known = error as SnapshotException;
            if (known?.Kind is "authentication" or "accountChanged" or "unsupportedWorkspace") { Snapshot = null; monitor.Reset(); History = new(); ResetAlerts?.Invoke(); }
            Connection = known?.UserMessage ?? "갱신 지연 · 마지막 확인값";
        }
        finally
        {
            if (generation == thisGeneration) { IsRefreshing = false; schedule.Finished(started, Uptime, failures, Snapshot is null, Random.Shared.NextDouble()); Changed?.Invoke(); }
        }
    }
    private void Apply(Snapshot next)
    {
        var hash = Json.Hash(next.WorkspaceKey);
        if (History.WorkspaceHash != hash) History = IsDemo ? new() { WorkspaceHash = hash } : History.Load(LocalData.PathFor("RecentAlerts.json"), hash);
        var events = monitor.Ingest(next, Preferences.LowCreditThreshold);
        Snapshot = next;
        foreach (var e in events) Handle(e);
        History.Merge(next.Jobs, IsDemo); SaveHistory(); Changed?.Invoke();
    }
    private void Handle(MonitorEvent e)
    {
        var decision = AlertPolicy.Record(e, Preferences, History, IsDemo, DateTimeOffset.Now);
        if (decision is { Present: true })
        {
            if (e.Kind == "completed") { Failure = null; Celebration = DateTimeOffset.UtcNow; }
            else if (e.Kind == "failed") { Celebration = null; Failure = DateTimeOffset.UtcNow; }
            Say(decision.Bubble); AlertRaised?.Invoke(decision.Alert);
        }
    }
    public void EnterDemo()
    {
        Cancel(); _ = Session.AbortAsync(); IsDemo = true; Snapshot = null; monitor.Reset(); History = new(); Connection = "미리보기 · 가상 데이터";
        Apply(Demo.Snapshot()); Say("안녕! 저는 지크 토끼예요");
    }
    public void LeaveDemo()
    {
        Cancel(); IsDemo = false; Snapshot = null; monitor.Reset(); History = new(); Celebration = Failure = null; Bubble = null; Connection = "연결 대기"; schedule.Resume(Uptime, Random.Shared.NextDouble()); _ = Session.StartAsync(); Changed?.Invoke();
    }
    public void SimulateCompletion() { if (IsDemo) Apply(Demo.Snapshot(1)); }
    public bool EnableDebug(string code) { DebugEnabled = code.Trim() == "zcrenext"; Changed?.Invoke(); return DebugEnabled; }
    public void DisableDebug() { DebugEnabled = false; Changed?.Invoke(); }
    public void NotifyVisualState() => Changed?.Invoke();
    public void Say(string text) { if (FocusActive) return; Bubble = text; bubbleUntil = DateTimeOffset.UtcNow.AddSeconds(8); Changed?.Invoke(); }
    public void TestNotification()
    {
        if (FocusActive) { NotificationStatus = "집중 모드 중에는 테스트 알림도 쉬어요."; Changed?.Invoke(); return; }
        var alert = new Alert(Guid.NewGuid().ToString(), "completed", "알림 전달 테스트", "ZCRE 서포터의 로컬 테스트예요. 작업·크레딧은 사용하지 않았어요.", DateTimeOffset.Now, false, "notification", null);
        History.Alerts.Insert(0, alert); History.Trim(); SaveHistory();
        Preferences.NotificationsReviewed = true; SavePreferences(); AlertRaised?.Invoke(alert); Say("테스트 알림을 요청했어요. Windows 표시 여부를 확인해 주세요.");
    }
    public void SetNotificationStatus(bool accepted) { NotificationStatus = accepted ? "Windows에 전달을 요청했어요. 실제 표시는 알림 설정·집중 지원에 따라 달라져요." : "Windows에 전달하지 못했어요. 알림 설정을 확인해 주세요."; Changed?.Invoke(); }
    public void ClearHistory() { History.Clear(DateTimeOffset.UtcNow); SaveHistory(); Changed?.Invoke(); }
    public void MarkRead(int count) { History.MarkRead(count); SaveHistory(); }
    public Job? JobFor(Alert alert) => Snapshot?.Jobs.FirstOrDefault(j => j.HistoryKey == alert.JobKey);
    private void SaveHistory()
    {
        if (IsDemo || Snapshot is null) return;
        var json = JsonSerializer.Serialize(History, Json.Options);
        if (json != savedHistory && LocalData.Save("RecentAlerts.json", History)) savedHistory = json;
    }
    public void SavePreferences()
    {
        LocalData.Save("preferences.json", Preferences);
        if (FocusActive) { Celebration = Failure = null; Bubble = null; ResetAlerts?.Invoke(); }
        Changed?.Invoke();
    }
    public async Task DisconnectAsync()
    {
        Cancel(); allowed = false; Snapshot = null; monitor.Reset(); History = new(); Bubble = null; Celebration = Failure = null; Connection = "연결 대기"; ResetAlerts?.Invoke();
        LocalData.Save("RecentAlerts.json", History);
        savedHistory = ""; Changed?.Invoke();
        await Session.DisconnectAsync(); Changed?.Invoke();
    }
    public object Diagnostics() => new { formatVersion = 1, appVersion = "0.2.20-windows.1", windows = Environment.OSVersion.VersionString, architecture = System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture.ToString(), generatedAt = DateTimeOffset.UtcNow, connection = Snapshot is null ? "unverified" : "connected", IsRefreshing, IsDemo, activeJobCount = ActiveCount, unreadAlertCount = History.Alerts.Count(a => !a.IsRead), Preferences.PetVisible, Preferences.PetScale, displayCount = System.Windows.Forms.Screen.AllScreens.Length };
    public void Dispose() { timer.Stop(); Cancel(); NetworkChange.NetworkAvailabilityChanged -= NetworkChanged; Session.Dispose(); }
}
