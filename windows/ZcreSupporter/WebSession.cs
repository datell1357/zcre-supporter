using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;

namespace ZcreSupporter;

internal sealed class WebSession : IDisposable
{
    public WebView2 View { get; } = new();
    private readonly Window window;
    private readonly Dictionary<string, TaskCompletionSource<string>> pending = [];
    private readonly Dictionary<string, (DateTimeOffset Until, List<JobOutput> Outputs)> outputCache = [];
    private readonly List<Window> popups = [];
    private readonly BridgeEpoch epoch = new();
    private readonly ConnectionPresentation presentation = new();
    private CoreWebView2Environment? environment;
    private Task? initialization;
    private bool disposed;
    private double balanceRefreshUntil, balanceRetryAt;
    private DateTimeOffset outputRetryAt;
    public DateTimeOffset RetryNotBefore { get; private set; }
    public bool Loaded { get; private set; }
    public event Action? Ready;
    public event Action? AccountChanged;

    public WebSession()
    {
        window = new Window { Title = "ZCRE 서포터 · 계정 연결", Width = 1060, Height = 760, MinWidth = 760, MinHeight = 560, Content = View, WindowStartupLocation = WindowStartupLocation.CenterScreen };
        window.Closing += (_, e) => { if (!disposed) { e.Cancel = true; window.Hide(); } };
    }
    public Task StartAsync() => initialization ??= InitializeAsync();
    private async Task InitializeAsync()
    {
        environment = await CoreWebView2Environment.CreateAsync(null, LocalData.PathFor("WebView2"));
        // The hidden owned window keeps the authenticated page and Clerk refresh alive.
        window.Show(); window.Hide();
        await View.EnsureCoreWebView2Async(environment);
        var core = View.CoreWebView2;
        core.Settings.AreDevToolsEnabled = false;
        core.Settings.AreDefaultContextMenusEnabled = false;
        core.Settings.IsStatusBarEnabled = false;
        core.NavigationStarting += (_, e) =>
        {
            if (!HttpsOrBlank(e.Uri)) { e.Cancel = true; return; }
            Loaded = false; ResetPending();
        };
        core.NavigationCompleted += (_, e) => { Loaded = e.IsSuccess && BridgeEpoch.TrustedOrigin(core.Source); if (Loaded) Ready?.Invoke(); };
        core.ProcessFailed += (_, _) => { Loaded = false; ResetPending(); if (!disposed) core.Reload(); };
        core.WebMessageReceived += Receive;
        core.NewWindowRequested += OpenPopup;
        core.PermissionRequested += (_, e) => e.State = CoreWebView2PermissionState.Deny;
        var observer = File.ReadAllText(LocalData.Asset("ObserveSession.js"));
        var shim = "if(window.top===window && ['https://www.zcre.co.kr','https://zcre.co.kr'].includes(location.origin)){window.webkit={messageHandlers:{zcreSessionChanged:{postMessage:event=>window.chrome.webview.postMessage({channel:'session',event})}}};" + observer + "}";
        await core.AddScriptToExecuteOnDocumentCreatedAsync(shim);
        core.Navigate("https://www.zcre.co.kr/credits");
    }
    private static bool HttpsOrBlank(string uri) => uri == "about:blank" || Uri.TryCreate(uri, UriKind.Absolute, out var value) && value.Scheme == "https";
    private async void OpenPopup(object? sender, CoreWebView2NewWindowRequestedEventArgs e)
    {
        if (!HttpsOrBlank(e.Uri)) { e.Handled = true; return; }
        using var deferral = e.GetDeferral();
        try
        {
            var browser = new WebView2();
            var popup = new Window { Title = "ZCRE 서포터 · 로그인", Width = 700, Height = 780, Content = browser, Owner = window };
            popups.Add(popup); popup.Show();
            await browser.EnsureCoreWebView2Async(environment);
            browser.CoreWebView2.NavigationStarting += (_, n) => { if (!HttpsOrBlank(n.Uri)) n.Cancel = true; };
            browser.CoreWebView2.WindowCloseRequested += (_, _) => popup.Close();
            popup.Closed += (_, _) => { popups.Remove(popup); browser.Dispose(); };
            e.NewWindow = browser.CoreWebView2; e.Handled = true;
        }
        catch { e.Handled = true; }
    }
    private void Receive(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        if (!BridgeEpoch.TrustedOrigin(e.Source)) return;
        try
        {
            var message = BridgeMessage.Decode(e.WebMessageAsJson);
            if (message is null) return;
            if (message.Channel == "session")
            {
                var kind = message.Event;
                if (kind == "changed") { ResetPending(); AccountChanged?.Invoke(); }
                else if (kind == "ready") Ready?.Invoke();
            }
            else if (message.Channel == "bridge" && pending.Remove(message.Id!, out var task)) task.TrySetResult(message.Value!);
        }
        catch (JsonException) { }
    }
    private void ResetPending()
    {
        epoch.Reset(); outputCache.Clear(); outputRetryAt = default;
        foreach (var task in pending.Values) task.TrySetCanceled();
        pending.Clear();
    }
    public async Task ShowAsync(bool needsConnection = false)
    {
        await StartAsync(); presentation.Open(needsConnection); window.Show(); window.WindowState = WindowState.Normal; window.Activate();
    }
    public void CompleteConnection() { if (presentation.VerifiedSnapshot()) window.Hide(); }
    private async Task<string> CallAsync(string resource, Dictionary<string, object?> arguments, CancellationToken cancellationToken)
    {
        await StartAsync();
        if (!Loaded) throw new SnapshotException("network");
        if (!BridgeEpoch.TrustedOrigin(View.CoreWebView2.Source)) throw new SnapshotException("authentication");
        var id = Guid.NewGuid().ToString("N");
        var task = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
        pending[id] = task;
        var declarations = string.Join("", arguments.Select(a => "const " + a.Key + "=" + JsonSerializer.Serialize(a.Value, Json.Options) + ";"));
        var script = File.ReadAllText(LocalData.Asset(resource));
        var wrapper = "(()=>{(async()=>{" + declarations + script + "})().then(value=>window.chrome.webview.postMessage({channel:'bridge',id:'" + id + "',value})).catch(()=>window.chrome.webview.postMessage({channel:'bridge',id:'" + id + "',value:JSON.stringify({error:'network'})}));})()";
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(25));
        try
        {
            await View.ExecuteScriptAsync(wrapper);
            return await task.Task.WaitAsync(timeout.Token);
        }
        catch (OperationCanceledException)
        {
            await AbortAsync();
            if (!cancellationToken.IsCancellationRequested && !disposed) View.CoreWebView2.Reload();
            throw;
        }
        finally { pending.Remove(id); }
    }
    public async Task<(Snapshot Snapshot, string Revision)> SnapshotAsync(string[] activeIds, Snapshot? previous, bool forceBalance, CancellationToken cancellationToken)
    {
        var generation = epoch.Generation;
        var revision = Guid.NewGuid().ToString("N");
        var terminal = 0;
        var json = await CallAsync("ReadSnapshot.js", new()
        {
            ["activeIDs"] = activeIds,
            ["previousJobs"] = previous?.Jobs.Where(j => !j.Terminal || ++terminal <= 50).Select(j => new { j.Id, j.Model, j.MediaType, j.Status, createdAt = j.CreatedAt.ToString("O") }).ToArray() ?? [],
            ["previousWorkspaceKey"] = previous?.WorkspaceKey ?? "", ["previousHistoryTruncated"] = previous?.HistoryTruncated ?? false,
            ["since"] = previous?.FetchedAt.ToUnixTimeMilliseconds() ?? 0,
            ["previousBalance"] = previous?.Balance, ["previousBalanceFetchedAt"] = previous?.BalanceFetchedAt ?? 0,
            ["previousBalanceIsStale"] = previous?.BalanceIsStale ?? false, ["balanceRefreshUntil"] = balanceRefreshUntil,
            ["balanceRetryAt"] = balanceRetryAt, ["forceBalance"] = forceBalance,
            ["snapshotRevision"] = revision, ["acceptedSnapshotRevision"] = epoch.AcceptedRevision
        }, cancellationToken);
        using var payload = JsonDocument.Parse(json);
        var root = payload.RootElement;
        if (root.TryGetProperty("retryAfter", out var retry) && retry.TryGetDouble(out var seconds) && double.IsFinite(seconds) && seconds > 0) RetryNotBefore = DateTimeOffset.UtcNow.AddSeconds(Math.Min(86400, seconds));
        var snapshot = Snapshot.Decode(json, DateTimeOffset.UtcNow);
        if (!epoch.Candidate(generation, revision, snapshot.WorkspaceKey)) throw new OperationCanceledException();
        balanceRefreshUntil = root.TryGetProperty("balanceRefreshUntil", out var fast) ? fast.GetDouble() : 0;
        balanceRetryAt = root.TryGetProperty("balanceRetryAt", out var at) ? at.GetDouble() : 0;
        return (snapshot, revision);
    }
    public bool Accept(string revision, Snapshot snapshot) => epoch.Accept(revision, snapshot.WorkspaceKey);
    public async Task<List<JobOutput>> OutputsAsync(Job job, string workspaceKey, CancellationToken cancellationToken)
    {
        var key = workspaceKey + ":" + job.Id;
        if (outputCache.TryGetValue(key, out var hit) && hit.Until > DateTimeOffset.UtcNow) return hit.Outputs;
        if (DateTimeOffset.UtcNow < outputRetryAt) throw new SnapshotException("http", 429);
        outputRetryAt = DateTimeOffset.UtcNow.AddSeconds(5);
        var generation = epoch.Generation;
        var json = await CallAsync("ReadOutputs.js", new() { ["requestID"] = job.Id, ["workspaceKey"] = workspaceKey }, cancellationToken);
        if (generation != epoch.Generation) throw new OperationCanceledException();
        using var doc = JsonDocument.Parse(json);
        if (doc.RootElement.TryGetProperty("error", out var error))
        {
            var retry = doc.RootElement.TryGetProperty("retryAfter", out var r) ? r.GetString() : null;
            outputRetryAt = DateTimeOffset.UtcNow.AddSeconds(Math.Clamp(AccountSchedule.RetryAfter(retry, DateTimeOffset.UtcNow), 5, 86400));
            throw new SnapshotException("http", error.ValueKind == JsonValueKind.Number ? error.GetInt32() : 0);
        }
        var outputs = OutputPayload.Decode(json);
        foreach (var expired in outputCache.Where(p => p.Value.Until <= DateTimeOffset.UtcNow).Select(p => p.Key).ToArray()) outputCache.Remove(expired);
        if (outputCache.Count >= 20) outputCache.Clear();
        var ttl = Math.Clamp(outputs.Select(o => (o.Expires ?? 30) - 5).DefaultIfEmpty(0).Min(), 0, 30);
        outputCache[key] = (DateTimeOffset.UtcNow.AddSeconds(ttl), outputs);
        return outputs;
    }
    public async Task AbortAsync()
    {
        if (View.CoreWebView2 is not null) await View.ExecuteScriptAsync("window.__zcreSupporterReadAbort?.abort();window.__zcreSupporterOutputAbort?.abort();");
    }
    public async Task DisconnectAsync()
    {
        ResetPending(); presentation.Reset(); await AbortAsync(); balanceRefreshUntil = 0; balanceRetryAt = 0; RetryNotBefore = default;
        foreach (var popup in popups.ToArray()) popup.Close();
        if (View.CoreWebView2 is not null) { View.CoreWebView2.Stop(); await View.CoreWebView2.Profile.ClearBrowsingDataAsync(CoreWebView2BrowsingDataKinds.AllProfile); View.CoreWebView2.Navigate("about:blank"); }
        Loaded = false; window.Hide();
    }
    public async Task ReconnectAsync(bool needsConnection = false) { await StartAsync(); if (View.CoreWebView2.Source == "about:blank") View.CoreWebView2.Navigate("https://www.zcre.co.kr/credits"); await ShowAsync(needsConnection); }
    public void Dispose() { disposed = true; ResetPending(); foreach (var p in popups.ToArray()) p.Close(); View.Dispose(); window.Close(); }
}
