using System.Diagnostics;
using System.Net.Http;
using System.Text.Encodings.Web;
using Microsoft.Web.WebView2.Wpf;
using Microsoft.Win32;

namespace ZcreSupporter;

internal sealed class DashboardWindow : Window
{
    private readonly CompanionStore store;
    private readonly ServiceStatus status;
    private readonly StackPanel jobs = new(), balance = new(), alerts = new(), services = new();
    private readonly TextBlock connection = Ui.Text("연결 대기", 12), timestamps = Ui.Text("작업·크레딧 확인 대기", 11);
    private readonly TextBlock statusTime = Ui.Text("집계 대기", 11);
    private readonly Border notificationNotice;
    private Window? settings, detail;
    private string renderedMain = "", renderedDetail = "";
    private bool shuttingDown;
    public event Action? ResetPetRequested;
    public event Action? MotionTestsRequested;
    public DashboardWindow(CompanionStore store, ServiceStatus status)
    {
        this.store = store; this.status = status;
        Title = "ZCRE 서포터"; Width = 1120; Height = 760; MinWidth = 900; MinHeight = 560; WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = (Brush)Application.Current.FindResource("BackgroundBrush"); Foreground = Brushes.White; FontFamily = new FontFamily("Malgun Gothic"); FontSize = 13;
        var root = new DockPanel { Margin = new Thickness(24), Background = Background };
        var header = new DockPanel { Margin = new Thickness(0, 0, 0, 18) };
        var title = new StackPanel(); title.Children.Add(Ui.Text("ZCRE 서포터", 26, true)); title.Children.Add(connection); header.Children.Add(title);
        var actions = Ui.Actions(Ui.Action("ZCRE 계정 연결", () => _ = store.ConnectAsync()), Ui.Action("새로고침", () => { store.RequestRefresh(true); _ = status.RefreshAsync(); }), Ui.Action("설정", ShowSettings)); actions.HorizontalAlignment = HorizontalAlignment.Right; header.Children.Add(actions);
        DockPanel.SetDock(header, Dock.Top); root.Children.Add(header); DockPanel.SetDock(timestamps, Dock.Bottom); root.Children.Add(timestamps); timestamps.Foreground = Ui.Muted;
        var notice = new StackPanel(); notice.Children.Add(Ui.Text("Windows 알림도 확인해 주세요", 14, true)); notice.Children.Add(Ui.Text("앱 내 기록은 계속 남아요. Windows 배너·소리는 시스템 알림 설정과 집중 지원에 따라 표시되지 않을 수 있어요.", 11));
        notice.Children.Add(Ui.Actions(Ui.Action("테스트 알림 보내기", store.TestNotification), Ui.Action("Windows 알림 설정", () => OpenWeb("ms-settings:notifications")), Ui.Action("나중에 확인", () => { store.Preferences.NotificationsReviewed = true; store.SavePreferences(); })));
        notificationNotice = Ui.Card(notice); DockPanel.SetDock(notificationNotice, Dock.Top); root.Children.Add(notificationNotice);
        var columns = new Grid(); columns.ColumnDefinitions.Add(new() { Width = new GridLength(1.15, GridUnitType.Star) }); columns.ColumnDefinitions.Add(new() { Width = new GridLength(1, GridUnitType.Star) }); columns.ColumnDefinitions.Add(new() { Width = new GridLength(1, GridUnitType.Star) });
        var left = Ui.Section("진행 작업"); left.Children.Add(jobs);
        var middle = Ui.Section("크레딧"); middle.Children.Add(balance); middle.Children.Add(Ui.Text("최근 알림", 16, true)); middle.Children.Add(alerts); middle.Children.Add(Ui.Action("알림 전체 보기", ShowDetails));
        var right = Ui.Section("서비스 상태"); right.Children.Add(statusTime); right.Children.Add(services); right.Children.Add(Ui.Action("ZCRE 상태 페이지 ↗", () => OpenWeb("https://www.zcre.co.kr/status")));
        foreach (var (panel, index) in new[] { (left, 0), (middle, 1), (right, 2) }) { var scroll = new ScrollViewer { Content = panel, Margin = new Thickness(index == 0 ? 0 : 16, 0, 0, 0) }; Grid.SetColumn(scroll, index); columns.Children.Add(scroll); }
        root.Children.Add(columns); Content = root;
        PreviewKeyDown += (_, e) =>
        {
            if (System.Windows.Input.Keyboard.Modifiers != System.Windows.Input.ModifierKeys.Control) return;
            if (e.Key == System.Windows.Input.Key.OemComma) { ShowSettings(); e.Handled = true; }
            else if (e.Key == System.Windows.Input.Key.R) { store.RequestRefresh(true); e.Handled = true; }
            else if (e.Key == System.Windows.Input.Key.H) { ShowDetails(); e.Handled = true; }
            else if (e.Key == System.Windows.Input.Key.D) { if (store.IsDemo) store.SimulateCompletion(); else store.EnterDemo(); e.Handled = true; }
            else if (e.Key == System.Windows.Input.Key.Q) { ((App)Application.Current).Quit(); e.Handled = true; }
        };
        store.Changed += Refresh; status.Changed += RefreshStatus;
        IsVisibleChanged += (_, _) => { status.SetVisible(IsVisible); if (IsVisible) { store.MarkRead(10); store.RequestRefresh(); Refresh(); } };
        Closing += (_, e) => { if (!shuttingDown) { e.Cancel = true; Hide(); } };
        Refresh(); RefreshStatus();
    }
    public void Present() { Show(); WindowState = WindowState.Normal; Activate(); }
    private void Refresh()
    {
        connection.Text = store.IsDemo ? "미리보기 · 가상 데이터 · 크레딧을 사용하지 않아요" : store.Connection;
        connection.Foreground = store.Snapshot is null ? Ui.Muted : Ui.Accent;
        notificationNotice.Visibility = !store.IsDemo && !store.Preferences.NotificationsReviewed ? Visibility.Visible : Visibility.Collapsed;
        var snapshot = store.Snapshot;
        var revision = JsonSerializer.Serialize(new { key = snapshot?.WorkspaceKey, snapshot?.Balance, snapshot?.BalanceIsStale, snapshot?.Jobs, snapshot?.Concurrency, store.History.Alerts, store.History.ClearedThrough, store.IsDemo }, Json.Options);
        if (revision != renderedMain)
        {
        renderedMain = revision;
        jobs.Children.Clear(); balance.Children.Clear(); alerts.Children.Clear();
        if (snapshot is null)
        {
            jobs.Children.Add(Ui.Card(Ui.Text("계정을 연결하면 진행 중인 작업을 여기에 표시해요.")));
            jobs.Children.Add(Ui.Action("연결 전에 미리 둘러보기", store.EnterDemo));
            balance.Children.Add(Ui.Card(Ui.Text("— Credit", 28, true)));
        }
        else
        {
            var credit = new StackPanel(); credit.Children.Add(Ui.Text(store.CreditText + " Credit", 28, true)); credit.Children.Add(Ui.Text("사용 가능", 11)); credit.Children.Add(Ui.Text("예약 " + Balance.Format(snapshot.Balance.Reserved) + " · 총 " + Balance.Format(snapshot.Balance.Total), 12));
            if (snapshot.BalanceIsStale) credit.Children.Add(Ui.Text("크레딧 갱신 지연 · 마지막 확인값", 11)); balance.Children.Add(Ui.Card(credit));
            var counts = Ui.Text("이미지 " + snapshot.ActiveJobs.Count(j => j.MediaType == "image") + (snapshot.Concurrency is { } c ? "/" + c.ImagesLimit : "") + " · 영상 " + snapshot.ActiveJobs.Count(j => j.MediaType == "video") + (snapshot.Concurrency is { } v ? "/" + v.VideosLimit : "") + " · 합계 " + store.ActiveCount, 12); jobs.Children.Add(counts);
            foreach (var job in snapshot.ActiveJobs) jobs.Children.Add(JobCard(job));
            if (store.ActiveCount == 0) jobs.Children.Add(Ui.Card(Ui.Text("진행 중인 작업이 없어요. 새 아이디어를 기다리고 있어요.")));
            jobs.Children.Add(Ui.Action("작업 기록 · 결과 보기", ShowDetails));
            if (store.IsDemo) jobs.Children.Add(Ui.Actions(Ui.Action("미리보기 완료 전환", store.SimulateCompletion), Ui.Action("미리보기 종료", store.LeaveDemo)));
        }
        foreach (var alert in store.History.Alerts.Take(10)) alerts.Children.Add(AlertCard(alert));
        if (store.History.Alerts.Count == 0) alerts.Children.Add(Ui.Text(store.History.ClearedThrough is null ? "연결 후 최근 완료·실패 기록을 보여드려요." : "알림 기록을 지웠어요. 새로운 알림을 기다려요.", 12));
        }
        if (snapshot is not null) timestamps.Text = "작업 " + snapshot.FetchedAt.ToLocalTime().ToString("HH:mm:ss") + " 확인 · 크레딧 " + DateTimeOffset.FromUnixTimeMilliseconds((long)snapshot.BalanceFetchedAt).ToLocalTime().ToString("HH:mm:ss") + " 확인 · 작업 5초 / 크레딧 60초 · " + (snapshot.HistoryTruncated ? "최초 기록 최대 1,000개" : "읽기 전용 감시");
        else timestamps.Text = "로그인은 앱 전용 웹 세션에만 보관돼요. 생성·결제 요청을 보내지 않아요.";
        if (detail is { IsVisible: true }) RefreshDetails();
    }
    private UIElement JobCard(Job job)
    {
        var panel = new StackPanel(); panel.Children.Add(Ui.Text(job.WorkName, 14, true)); panel.Children.Add(Ui.Text(job.StateLabel + " · " + job.StartLabel + " 시작", 12));
        if (job.State == JobStatus.Succeeded) panel.Children.Add(Ui.Action("결과 보기", () => ShowResults(job)));
        return Ui.Card(panel);
    }
    private UIElement AlertCard(Alert alert)
    {
        var panel = new StackPanel(); panel.Children.Add(Ui.Text(alert.Title, 12, true)); panel.Children.Add(Ui.Text(alert.Body + (alert.Source == "workHistory" ? " · 기존 기록" : ""), 11));
        if (store.JobFor(alert) is { State: JobStatus.Succeeded } job) panel.Children.Add(Ui.Action("결과 보기", () => ShowResults(job)));
        return Ui.Card(panel);
    }
    private void RefreshStatus()
    {
        services.Children.Clear(); statusTime.Text = status.TimeLabel;
        foreach (var row in status.Rows)
        {
            var panel = new StackPanel(); panel.Children.Add(Ui.Text(row.Label, 13, true)); var health = Ui.Text("● " + ServiceStatus.HealthLabel(row.Health), 12); health.Foreground = row.Health == "operational" ? Ui.Accent : row.Health == "checking" ? Ui.Muted : Brushes.Orange; panel.Children.Add(health); panel.Children.Add(Ui.Text(row.Detail, 10)); services.Children.Add(Ui.Card(panel));
        }
        if (status.Rows.Count == 0) services.Children.Add(Ui.Text("서비스 상태를 확인하고 있어요. 조회할 수 없으면 정상으로 표시하지 않아요.", 12));
    }
    public void ShowDetails()
    {
        if (detail is not null) { detail.Activate(); return; }
        store.MarkRead(30);
        renderedDetail = ""; detail = Ui.Window("상세 현황", new StackPanel(), 650, 750); RefreshDetails(); detail.Closed += (_, _) => detail = null; detail.Show();
    }
    private void RefreshDetails()
    {
        if (detail is null) return;
        store.MarkRead(30);
        var revision = JsonSerializer.Serialize(new { store.Snapshot?.WorkspaceKey, store.Snapshot?.Jobs, store.History.Alerts, store.History.ClearedThrough }, Json.Options);
        if (revision == renderedDetail) return;
        renderedDetail = revision;
        var panel = new StackPanel(); panel.Children.Add(Ui.Text("작업 기록과 알림", 24, true));
        panel.Children.Add(Ui.Action("알림 전체 지우기", () => { if (MessageBox.Show("이 앱에 보관된 최근 알림 기록만 비웁니다. 서버 작업은 유지됩니다.\n대상: " + LocalData.PathFor("RecentAlerts.json"), "알림 기록 지우기", MessageBoxButton.OKCancel) == MessageBoxResult.OK) { store.ClearHistory(); detail?.Close(); ShowDetails(); } }));
        foreach (var job in store.Snapshot?.Jobs ?? []) panel.Children.Add(JobCard(job));
        panel.Children.Add(Ui.Text("전체 알림 · 최대 30개", 18, true)); foreach (var alert in store.History.Alerts) panel.Children.Add(AlertCard(alert));
        if (store.History.Alerts.Count == 0) panel.Children.Add(Ui.Text("아직 보관된 알림이 없어요."));
        detail.Content = new Border { Padding = new Thickness(24), Child = new ScrollViewer { Content = panel } };
    }
    public void ShowSettings()
    {
        if (settings is not null) { settings.Activate(); return; }
        var panel = new StackPanel(); panel.Children.Add(Ui.Text("지크 설정", 24, true)); panel.Children.Add(Ui.Text("편안한 작업 리듬에 맞춰 주세요.", 12));
        var synchronizers = new List<Action>(); var synchronizing = false;
        void Toggle(string title, Func<bool> get, Action<bool> set) { var checkbox = new CheckBox { Content = title, IsChecked = get() }; checkbox.Checked += (_, _) => { if (!synchronizing) { set(true); store.SavePreferences(); } }; checkbox.Unchecked += (_, _) => { if (!synchronizing) { set(false); store.SavePreferences(); } }; synchronizers.Add(() => checkbox.IsChecked = get()); panel.Children.Add(checkbox); }
        void Heading(string title) => panel.Children.Add(Ui.Text("\n" + title, 17, true));
        var p = store.Preferences;
        Heading("바탕화면"); Toggle("바탕화면에 지크 보이기", () => p.PetVisible, v => p.PetVisible = v); Toggle("산책 활성화", () => p.Roaming, v => p.Roaming = v); Toggle("트레이 툴팁에 크레딧 표시", () => p.ShowTrayCredits, v => p.ShowTrayCredits = v);
        panel.Children.Add(Ui.Text("Windows 트레이는 아이콘 옆 숫자를 지원하지 않아 툴팁과 현황판에 표시해요.", 11));
        panel.Children.Add(Ui.Text("지크 크기 · 70~150%")); var scale = new Slider { Minimum = .7, Maximum = 1.5, TickFrequency = .1, IsSnapToTickEnabled = true, Value = p.PetScale }; scale.ValueChanged += (_, _) => { p.PetScale = scale.Value; store.SavePreferences(); }; panel.Children.Add(scale); panel.Children.Add(Ui.Action("지크를 화면 아래로 데려오기", () => ResetPetRequested?.Invoke()));
        Heading("지크 효과음"); Toggle("지크 효과음 사용", () => p.PetSounds, v => p.PetSounds = v); panel.Children.Add(Ui.Text("음량 · 0~100%")); var volume = new Slider { Minimum = 0, Maximum = 1, Value = p.PetSoundVolume }; volume.ValueChanged += (_, _) => { p.PetSoundVolume = volume.Value; store.SavePreferences(); }; panel.Children.Add(volume); panel.Children.Add(Ui.Text("다른 앱의 소리·통화 중에는 타자음이 쉬어요. 장치 음량과 오디오 내용은 건드리지 않아요.", 11));
        Heading("알림"); Toggle("지크 숨김 시 바탕화면 배너", () => p.BannerAlerts, v => p.BannerAlerts = v); Toggle("작업 완료", () => p.CompletionAlerts, v => p.CompletionAlerts = v); Toggle("작업 실패", () => p.FailureAlerts, v => p.FailureAlerts = v); Toggle("크레딧 부족", () => p.LowCreditAlerts, v => p.LowCreditAlerts = v); Toggle("시스템 알림 소리", () => p.NotificationSound, v => p.NotificationSound = v);
        var threshold = new TextBox { Text = p.LowCreditThreshold.ToString(), ToolTip = "크레딧 알림 임계값" }; threshold.LostFocus += (_, _) => { if (decimal.TryParse(threshold.Text, out var value) && value >= 0) { p.LowCreditThreshold = value; store.SavePreferences(); } else threshold.Text = p.LowCreditThreshold.ToString(); }; panel.Children.Add(Ui.Text("크레딧 임계값 이하에서 알림")); panel.Children.Add(threshold);
        panel.Children.Add(Ui.Action("Windows 알림 설정 열기", () => OpenWeb("ms-settings:notifications")));
        var notificationStatus = Ui.Text(store.NotificationStatus, 11); panel.Children.Add(notificationStatus); synchronizers.Add(() => notificationStatus.Text = store.NotificationStatus); panel.Children.Add(Ui.Action("로컬 테스트 알림 보내기", store.TestNotification));
        Heading("작업 종류별 알림"); Toggle("이미지 작업", () => p.ImageJobAlerts, v => p.ImageJobAlerts = v); Toggle("영상 작업", () => p.VideoJobAlerts, v => p.VideoJobAlerts = v); Toggle("업스케일 작업", () => p.UpscaleJobAlerts, v => p.UpscaleJobAlerts = v); Toggle("오디오 작업", () => p.AudioJobAlerts, v => p.AudioJobAlerts = v); Toggle("기타 작업", () => p.OtherJobAlerts, v => p.OtherJobAlerts = v);
        Heading("집중 모드"); Toggle("지금 집중하기", () => p.FocusNow, v => p.FocusNow = v); Toggle("매일 정해진 시간에 집중", () => p.FocusSchedule, v => p.FocusSchedule = v);
        var start = new TextBox { Text = Time(p.FocusStartMinute), ToolTip = "집중 시작 HH:mm" }; var end = new TextBox { Text = Time(p.FocusEndMinute), ToolTip = "집중 종료 HH:mm" };
        start.LostFocus += (_, _) => { p.FocusStartMinute = ParseTime(start.Text, p.FocusStartMinute); start.Text = Time(p.FocusStartMinute); store.SavePreferences(); }; end.LostFocus += (_, _) => { p.FocusEndMinute = ParseTime(end.Text, p.FocusEndMinute); end.Text = Time(p.FocusEndMinute); store.SavePreferences(); };
        panel.Children.Add(Ui.Text("시작 / 종료 · 현지 시각 HH:mm")); panel.Children.Add(start); panel.Children.Add(end); panel.Children.Add(Ui.Text("자정을 넘는 일정도 지원해요. 시작·종료가 같으면 하루 종일 조용히 기록해요.", 11));
        Heading("계정"); panel.Children.Add(Ui.Actions(Ui.Action("계정 열기", () => _ = store.ConnectAsync()), Ui.Action(store.IsDemo ? "미리보기 종료" : "미리보기 체험", () => { if (store.IsDemo) store.LeaveDemo(); else store.EnterDemo(); }), Ui.Action("연결 해제", async () => { if (MessageBox.Show("앱의 로그인 웹 데이터와 로컬 알림을 비웁니다.\n대상: " + LocalData.PathFor("WebView2") + "\n" + LocalData.PathFor("RecentAlerts.json"), "연결 해제", MessageBoxButton.OKCancel) == MessageBoxResult.OK) await store.DisconnectAsync(); })));
        Heading("앱"); var startup = new CheckBox { Content = "Windows 로그인 시 자동 실행", IsChecked = LocalData.StartupEnabled };
        startup.Click += (_, _) => { try { if (MessageBox.Show("시작 프로그램 값을 변경합니다.\nHKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run\\ZcreSupporter\n실행파일: " + Environment.ProcessPath, "자동 실행 설정", MessageBoxButton.OKCancel) == MessageBoxResult.OK) LocalData.SetStartup(startup.IsChecked == true); startup.IsChecked = LocalData.StartupEnabled; } catch { startup.IsChecked = false; MessageBox.Show("시작 프로그램 설정을 변경하지 못했어요."); } }; panel.Children.Add(startup);
        panel.Children.Add(Ui.Action("진단 정보 내보내기…", ExportDiagnostics));
        Heading("디버그 모드"); var code = new PasswordBox { Margin = new Thickness(0, 8, 0, 8), ToolTip = "디버그 모드 활성화 코드" }; panel.Children.Add(code);
        var debugStatus = Ui.Text(store.DebugEnabled ? "현재 실행에서 활성화됨" : "앱 종료 시 자동으로 꺼져요", 11); panel.Children.Add(debugStatus);
        var motionButton = Ui.Action("모션 테스트 열기", () => MotionTestsRequested?.Invoke()); motionButton.Visibility = store.DebugEnabled ? Visibility.Visible : Visibility.Collapsed;
        panel.Children.Add(Ui.Actions(Ui.Action("디버그 활성화", () => { debugStatus.Text = store.EnableDebug(code.Password) ? "활성화됨" : "코드가 일치하지 않아요"; motionButton.Visibility = store.DebugEnabled ? Visibility.Visible : Visibility.Collapsed; code.Clear(); }), motionButton, Ui.Action("디버그 끄기", () => { store.DisableDebug(); debugStatus.Text = "비활성화됨"; motionButton.Visibility = Visibility.Collapsed; })));
        panel.Children.Add(Ui.Text("\n0.2.20 Windows · 검증 중인 개발 빌드", 11));
        settings = Ui.Window("설정", new ScrollViewer { Content = panel }, 620, 790);
        settings.PreviewKeyDown += (_, e) =>
        {
            if (System.Windows.Input.Keyboard.Modifiers == System.Windows.Input.ModifierKeys.Control && e.Key == System.Windows.Input.Key.M && store.DebugEnabled) { MotionTestsRequested?.Invoke(); e.Handled = true; return; }
            if (System.Windows.Input.Keyboard.Modifiers == System.Windows.Input.ModifierKeys.Alt && e.SystemKey == System.Windows.Input.Key.D)
            { debugStatus.Text = store.EnableDebug(code.Password) ? "활성화됨" : "코드가 일치하지 않아요"; motionButton.Visibility = store.DebugEnabled ? Visibility.Visible : Visibility.Collapsed; code.Clear(); e.Handled = true; }
        };
        void SynchronizeSettings() { synchronizing = true; try { foreach (var sync in synchronizers) sync(); } finally { synchronizing = false; } }
        store.Changed += SynchronizeSettings;
        settings.Closed += (_, _) => { store.Changed -= SynchronizeSettings; settings = null; }; settings.Show();
    }
    private static string Time(int minute) => $"{minute / 60:00}:{minute % 60:00}";
    private static int ParseTime(string text, int fallback) => TimeSpan.TryParseExact(text, @"hh\:mm", null, out var value) && value.TotalMinutes is >= 0 and < 1440 ? (int)value.TotalMinutes : fallback;
    private void ExportDiagnostics()
    {
        var dialog = new SaveFileDialog { FileName = "ZCRE-Supporter-diagnostics.json", Filter = "JSON|*.json", OverwritePrompt = true };
        if (dialog.ShowDialog() == true) try { File.WriteAllText(dialog.FileName, JsonSerializer.Serialize(store.Diagnostics(), Json.Options)); } catch { MessageBox.Show("진단 정보를 저장하지 못했어요."); }
    }
    public static void OpenWeb(string url)
    {
        if (url != "ms-settings:notifications" && (JobOutput.SafeUrl(url) is null || new Uri(url).Host != "www.zcre.co.kr")) return;
        Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
    }
    private async void ShowResults(Job job)
    {
        var panel = new StackPanel(); var info = Ui.Text("결과를 확인하고 있어요."); panel.Children.Add(info); var window = Ui.Window(job.WorkName + " · 결과", new ScrollViewer { Content = panel }, 820, 720); window.Show();
        var cancellation = new CancellationTokenSource(); var token = cancellation.Token; var generation = store.Snapshot?.WorkspaceKey; var startedInDemo = store.IsDemo;
        var players = new List<WebView2>();
        void OnChange() { if (generation != store.Snapshot?.WorkspaceKey || store.IsDemo != startedInDemo) window.Close(); }
        store.Changed += OnChange;
        window.Closed += (_, _) => { cancellation.Cancel(); foreach (var player in players) player.Dispose(); store.Changed -= OnChange; cancellation.Dispose(); };
        async Task SaveOutput(JobOutput output)
        {
            var save = new SaveFileDialog { FileName = "ZCRE-result." + output.Extension, Filter = "미디어 파일|*." + output.Extension + "|모든 파일|*.*", OverwritePrompt = true };
            if (save.ShowDialog(window) != true) return;
            try { await DownloadAsync(output.Download!, save.FileName, token); info.Text = "선택한 위치에 저장했어요."; }
            catch (OperationCanceledException) { }
            catch { info.Text = "저장하지 못했어요. 결과를 다시 열어 링크를 갱신해 주세요."; }
        }
        try
        {
            if (store.IsDemo) { info.Text = "미리보기에는 실제 결과 파일이 없어요. 실제 작업·크레딧은 사용하지 않았습니다."; return; }
            if (generation is null) throw new SnapshotException("authentication");
            var outputs = await store.Session.OutputsAsync(job, generation, token);
            info.Text = outputs.Count == 0 ? "아직 제공된 결과가 없어요." : $"결과 {outputs.Count}개 · URL은 저장하지 않아요";
            window.PreviewKeyDown += async (_, e) => { if (outputs.Count > 0 && System.Windows.Input.Keyboard.Modifiers == System.Windows.Input.ModifierKeys.Control && e.Key == System.Windows.Input.Key.S) { e.Handled = true; await SaveOutput(outputs[0]); } };
            foreach (var output in outputs)
            {
                var player = new WebView2 { Height = 340, Margin = new Thickness(0, 8, 0, 8) }; panel.Children.Add(player); players.Add(player);
                var mediaStatus = Ui.Text("미리보기 불러오는 중…", 11); panel.Children.Add(mediaStatus);
                var mediaEnvironment = await Microsoft.Web.WebView2.Core.CoreWebView2Environment.CreateAsync(null, LocalData.PathFor("MediaWebView2"));
                var mediaOptions = mediaEnvironment.CreateCoreWebView2ControllerOptions(); mediaOptions.IsInPrivateModeEnabled = true; mediaOptions.ProfileName = "MediaPrivate";
                await player.EnsureCoreWebView2Async(mediaEnvironment, mediaOptions);
                player.CoreWebView2.Settings.AreDevToolsEnabled = false; player.CoreWebView2.PermissionRequested += (_, e) => e.State = Microsoft.Web.WebView2.Core.CoreWebView2PermissionState.Deny;
                player.CoreWebView2.NavigationStarting += (_, e) => { if (e.Uri != "about:blank") e.Cancel = true; };
                player.CoreWebView2.WebMessageReceived += (_, e) =>
                {
                    if (e.Source != "about:blank") return;
                    try
                    {
                        using var doc = JsonDocument.Parse(e.WebMessageAsJson); var message = doc.RootElement;
                        if (message.ValueKind != JsonValueKind.Object || !message.TryGetProperty("mediaState", out var state) || state.ValueKind != JsonValueKind.String) return;
                        mediaStatus.Text = state.GetString() switch { "loaded" => "미리보기 준비됨", "playing" => "재생 중", "paused" => "일시 정지", "ended" => "재생 완료", "playDenied" => "미디어 안의 재생 버튼을 눌러 주세요.", "error" => "미리보기를 불러오지 못했어요. 결과를 다시 열어 주세요.", _ => mediaStatus.Text };
                    }
                    catch (JsonException) { }
                };
                var url = HtmlEncoder.Default.Encode(output.Preview!.AbsoluteUri); var media = output.Kind switch { "image" => $"<img src=\"{url}\" style=\"max-width:100%;max-height:320px\">", "video" => $"<video src=\"{url}\" controls style=\"max-width:100%;max-height:320px\"></video>", "audio" => $"<audio src=\"{url}\" controls></audio>", _ => "미리보기를 지원하지 않는 형식입니다." };
                var nonce = Guid.NewGuid().ToString("N");
                var monitorMedia = "const m=document.querySelector('img,video,audio');const send=mediaState=>window.chrome.webview.postMessage({mediaState});if(m){for(const name of ['load','loadeddata','canplay'])m.addEventListener(name,()=>send('loaded'));for(const name of ['playing','pause','ended','error'])m.addEventListener(name,()=>send(name==='pause'?'paused':name));if(m.tagName==='IMG'&&m.complete&&m.naturalWidth>0)send('loaded');}";
                player.NavigateToString("<!doctype html><meta name=\"referrer\" content=\"no-referrer\"><meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; img-src https:; media-src https:; style-src 'unsafe-inline'; script-src 'nonce-" + nonce + "'\"><body style=\"background:#1c1e22;color:white;display:grid;place-items:center;margin:0\">" + media + "<script nonce=\"" + nonce + "\">" + monitorMedia + "</script>");
                if (output.Kind is "video" or "audio") panel.Children.Add(Ui.Action("재생 / 일시 정지", async () => await player.ExecuteScriptAsync("(()=>{const m=document.querySelector('video,audio');if(m){if(m.paused)m.play().catch(()=>window.chrome.webview.postMessage({mediaState:'playDenied'}));else m.pause();}})()")));
                panel.Children.Add(Ui.Action("결과 저장…", async () => await SaveOutput(output)));
            }
            panel.Children.Add(Ui.Action("ZCRE에서 결과 열기 ↗", () => OpenWeb(JobOutput.ResultUrl(job).AbsoluteUri)));
        }
        catch (OperationCanceledException) { }
        catch (Exception e) { info.Text = (e as SnapshotException)?.UserMessage ?? "결과를 가져오지 못했어요. 잠시 후 다시 열어 주세요."; }
    }
    private static async Task DownloadAsync(Uri uri, string destination, CancellationToken token)
    {
        using var client = new HttpClient(new HttpClientHandler { UseCookies = false, AllowAutoRedirect = false }) { Timeout = TimeSpan.FromMinutes(10) };
        var pending = Path.Combine(Path.GetDirectoryName(destination)!, ".zcre-download-" + Guid.NewGuid().ToString("N") + ".part");
        try
        {
            for (var redirect = 0; redirect <= 5; redirect++)
            {
                if (JobOutput.SafeUrl(uri.AbsoluteUri) is null) throw new InvalidDataException();
                using var response = await client.GetAsync(uri, HttpCompletionOption.ResponseHeadersRead, token);
                if ((int)response.StatusCode is >= 300 and < 400) { uri = response.Headers.Location is { } location ? new Uri(uri, location) : throw new InvalidDataException(); continue; }
                response.EnsureSuccessStatusCode();
                using (var stream = await response.Content.ReadAsStreamAsync(token))
                using (var file = new FileStream(pending, FileMode.CreateNew, FileAccess.Write, FileShare.None)) { await stream.CopyToAsync(file, token); await file.FlushAsync(token); file.Flush(true); }
                token.ThrowIfCancellationRequested(); File.Move(pending, destination, true); return;
            }
            throw new InvalidDataException("Too many redirects");
        }
        finally { if (File.Exists(pending)) File.Delete(pending); }
    }
    public void Shutdown() { shuttingDown = true; settings?.Close(); detail?.Close(); store.Changed -= Refresh; status.Changed -= RefreshStatus; Close(); }
}
