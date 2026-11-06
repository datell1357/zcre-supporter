using System.Net.NetworkInformation;

namespace ZcreSupporter;

internal enum NotificationRequestState { Requested, Rejected }
internal enum NotificationEventState { Shown, Hidden, TimedOut, Clicked }

internal sealed class CompanionStore : IDisposable
{
    public Preferences Preferences { get; } = LocalData.LoadPreferences();
    public WebSession Session { get; } = new();
    public Snapshot? Snapshot { get; private set; }
    public History History { get; private set; } = ZcreSupporter.Core.History.Load(LocalData.PathFor("LocalTestAlerts.json"), "");
    public bool IsDemo { get; private set; }
    public bool IsRefreshing { get; private set; }
    public bool IsSleeping { get; private set; }
    public bool IsOffline { get; private set; }
    public bool DebugEnabled { get; private set; }
    public bool PreferencesSaveFailed { get; private set; }
    public bool FocusActive => Preferences.IsFocusActive(DateTime.Now);
    public string Connection { get; private set; } = "연결 대기";
    public string NotificationStatus { get; private set; } = "최근 요청 결과: 아직 확인하지 않았어요. 마지막 Windows 알림 이벤트: 아직 확인하지 않았어요. 두 정보가 같은 요청인지 확인할 수 없어요.";
    internal NotificationRequestState? LatestNotificationRequest { get; private set; }
    internal NotificationEventState? LastNotificationEvent { get; private set; }
    private readonly List<string> notificationActivationTrace = [];
    internal void RecordNotificationActivation(string stage)
    {
        if (notificationActivationTrace.Count == 8) notificationActivationTrace.RemoveAt(0);
        notificationActivationTrace.Add(stage);
    }
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
        Session.AccountChanged += () => { if (!IsDemo) { Cancel(); Snapshot = null; monitor.Reset(); History = History.Load(LocalData.PathFor("LocalTestAlerts.json"), ""); Connection = "계정 확인 중"; ResetAlerts?.Invoke(); schedule.Resume(Uptime, Random.Shared.NextDouble()); Changed?.Invoke(); } };
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
            if (known?.Kind is "authentication" or "accountChanged" or "unsupportedWorkspace") { Snapshot = null; monitor.Reset(); History = History.Load(LocalData.PathFor("LocalTestAlerts.json"), ""); ResetAlerts?.Invoke(); }
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
        Cancel(); IsDemo = false; Snapshot = null; monitor.Reset(); History = History.Load(LocalData.PathFor("LocalTestAlerts.json"), ""); Celebration = Failure = null; Bubble = null; Connection = "연결 대기"; schedule.Resume(Uptime, Random.Shared.NextDouble()); _ = StartAsync(false); Changed?.Invoke();
    }
    public void SimulateCompletion() { if (IsDemo) Apply(Demo.Snapshot(1)); }
    public bool EnableDebug(string code) { DebugEnabled = code.Trim() == "zcrenext"; Changed?.Invoke(); return DebugEnabled; }
    public void DisableDebug() { DebugEnabled = false; Changed?.Invoke(); }
    public void NotifyVisualState() => Changed?.Invoke();
    public void Say(string text) { if (FocusActive) return; Bubble = text; bubbleUntil = DateTimeOffset.UtcNow.AddSeconds(8); Changed?.Invoke(); }
    public void TestNotification()
    {
        if (FocusActive) { NotificationStatus = "최근 요청 결과: 집중 모드라 테스트 요청을 건너뛰었어요. " + NotificationEventText() + " 두 정보가 같은 요청인지 확인할 수 없어요."; Changed?.Invoke(); return; }
        var alert = new Alert(Guid.NewGuid().ToString(), "completed", "알림 전달 테스트", "ZCRE 서포터의 로컬 테스트예요. 작업·크레딧은 사용하지 않았어요.", DateTimeOffset.Now, false, "notification", null);
        History.Alerts.Insert(0, alert); History.Trim(); SaveHistory();
        Preferences.NotificationsReviewed = true; SavePreferences(); AlertRaised?.Invoke(alert); Say("테스트 알림을 요청했어요. Windows 표시 여부를 확인해 주세요.");
    }
    internal void ObserveNotificationCallback(NotificationEventState state)
    {
        LastNotificationEvent = state; RefreshNotificationStatus();
    }
    public void SetNotificationStatus(bool accepted)
    {
        LatestNotificationRequest = accepted ? NotificationRequestState.Requested : NotificationRequestState.Rejected;
        RefreshNotificationStatus();
    }
    private void RefreshNotificationStatus()
    {
        var request = LatestNotificationRequest switch
        {
            NotificationRequestState.Requested => "최근 요청 결과: Windows에 표시를 요청했어요.",
            NotificationRequestState.Rejected => "최근 요청 결과: Windows에 전달하지 못했어요.",
            _ => "최근 요청 결과: 아직 확인하지 않았어요."
        };
        NotificationStatus = request + " " + NotificationEventText() + " 두 정보가 같은 요청인지 확인할 수 없어요.";
        Changed?.Invoke();
    }
    private string NotificationEventText() => LastNotificationEvent switch
    {
        NotificationEventState.Shown => "마지막 Windows 알림 이벤트: 표시됐어요.",
        NotificationEventState.Hidden => "마지막 Windows 알림 이벤트: 숨겨졌어요.",
        NotificationEventState.TimedOut => "마지막 Windows 알림 이벤트: 표시 시간이 끝났어요.",
        NotificationEventState.Clicked => "마지막 Windows 알림 이벤트: 사용자가 눌렀어요.",
        _ => "마지막 Windows 알림 이벤트: 아직 확인하지 않았어요."
    };
    public void ClearHistory() { History.Clear(DateTimeOffset.UtcNow); SaveHistory(); Changed?.Invoke(); }
    public void MarkRead(int count) { History.MarkRead(count); SaveHistory(); }
    public Job? JobFor(Alert alert) => Snapshot?.Jobs.FirstOrDefault(j => j.HistoryKey == alert.JobKey);
    private void SaveHistory()
    {
        if (IsDemo || (Snapshot is null && (History.WorkspaceHash.Length != 0 || (History.Alerts.Count == 0 && History.ClearedThrough is null)))) return;
        var filename = Snapshot is null ? "LocalTestAlerts.json" : "RecentAlerts.json";
        var revision = filename + "\0" + JsonSerializer.Serialize(History, Json.Options);
        if (revision != savedHistory && LocalData.Save(filename, History)) savedHistory = revision;
    }
    public void SavePreferences()
    {
        PreferencesSaveFailed = !LocalData.Save("preferences.json", Preferences);
        if (FocusActive) { Celebration = Failure = null; Bubble = null; ResetAlerts?.Invoke(); }
        Changed?.Invoke();
    }
    public async Task DisconnectAsync()
    {
        Cancel(); allowed = false; Snapshot = null; monitor.Reset(); History = new(); Bubble = null; Celebration = Failure = null; Connection = "연결 대기"; ResetAlerts?.Invoke();
        LocalData.Save("RecentAlerts.json", History);
        LocalData.Save("LocalTestAlerts.json", History);
        savedHistory = ""; Changed?.Invoke();
        await Session.DisconnectAsync(); Changed?.Invoke();
    }
    public object Diagnostics() => new { formatVersion = 1, appVersion = "0.2.20-windows.1", windows = Environment.OSVersion.VersionString, architecture = System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture.ToString(), generatedAt = DateTimeOffset.UtcNow, connection = Snapshot is null ? "unverified" : "connected", IsRefreshing, IsDemo, activeJobCount = ActiveCount, unreadAlertCount = History.Alerts.Count(a => !a.IsRead), Preferences.PetVisible, Preferences.PetScale, displayCount = System.Windows.Forms.Screen.AllScreens.Length, notificationActivationTrace };
    public void Dispose() { timer.Stop(); Cancel(); NetworkChange.NetworkAvailabilityChanged -= NetworkChanged; Session.Dispose(); }
}
