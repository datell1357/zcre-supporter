using System.Net;
using System.Net.Http;

namespace ZcreSupporter;

internal sealed record ServiceRow(string Name, string Label, string Health, string Detail);

internal sealed class ServiceStatus : IDisposable
{
    private static readonly Uri Endpoint = new("https://www.zcre.co.kr/api/public/service-status?window=24h");
    private readonly HttpClient client = new(new HttpClientHandler { UseCookies = false, AllowAutoRedirect = false }) { Timeout = TimeSpan.FromSeconds(10) };
    private readonly PublicSchedule schedule = new();
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(1) };
    private CancellationTokenSource? cancellation;
    private List<ServiceRow> cached = [];
    private DateTimeOffset? calculatedAt;
    private DateTimeOffset serverAtReceipt;
    private double receiptUptime;
    private bool stale = true, error = true, busy, visible, paused;
    private string? etag, modified;
    public event Action? Changed;
    public IReadOnlyList<ServiceRow> Rows => Unavailable ? cached.Select(r => r with { Health = "checking" }).ToArray() : cached;
    public bool Unavailable => error || stale || calculatedAt is null || Math.Abs((serverAtReceipt.AddSeconds(CompanionStore.Uptime - receiptUptime) - calculatedAt.Value).TotalSeconds) > 300;
    public string TimeLabel => calculatedAt is null ? "집계 대기" : "KST " + calculatedAt.Value.ToOffset(TimeSpan.FromHours(9)).ToString("MM-dd HH:mm") + (Unavailable ? " · 확인 중" : " 집계");
    public ServiceStatus() { timer.Tick += async (_, _) => { if (visible && !paused && System.Net.NetworkInformation.NetworkInterface.GetIsNetworkAvailable() && CompanionStore.Uptime >= schedule.Next(false)) await RefreshAsync(false); }; }
    public void SetVisible(bool value) { visible = value; if (value) { timer.Start(); _ = RefreshAsync(false); } else { timer.Stop(); cancellation?.Cancel(); } }
    public void Pause(bool value) { paused = value; if (value) cancellation?.Cancel(); else if (visible) _ = RefreshAsync(false); }
    public async Task RefreshAsync(bool manual = true)
    {
        if (busy || paused || !schedule.Begin(CompanionStore.Uptime, manual)) return;
        busy = true; cancellation = new(); var token = cancellation.Token;
        var retry = 0d;
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, Endpoint);
            request.Headers.Accept.ParseAdd("application/json");
            if (etag is not null) request.Headers.TryAddWithoutValidation("If-None-Match", etag);
            else if (modified is not null) request.Headers.TryAddWithoutValidation("If-Modified-Since", modified);
            using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
            var serverNow = (response.Headers.Date ?? DateTimeOffset.UtcNow) + (response.Headers.Age ?? TimeSpan.Zero);
            retry = AccountSchedule.RetryAfter(response.Headers.RetryAfter?.ToString(), serverNow);
            if (response.StatusCode == HttpStatusCode.NotModified)
            {
                if (cached.Count == 0 || etag is null && modified is null) throw new FormatException();
            }
            else
            {
                if (response.StatusCode != HttpStatusCode.OK || response.Content.Headers.ContentType?.MediaType != "application/json" || response.Content.Headers.ContentLength > 1_000_000) throw new FormatException();
                using var stream = await response.Content.ReadAsStreamAsync(token); using var data = new MemoryStream(); var buffer = new byte[16384]; int count;
                while ((count = await stream.ReadAsync(buffer, token)) > 0) { if (data.Length + count > 1_000_000) throw new FormatException(); await data.WriteAsync(buffer.AsMemory(0, count), token); }
                using var doc = JsonDocument.Parse(data.ToArray()); var root = doc.RootElement;
                if (root.GetProperty("window").GetString() != "24h" || root.GetProperty("granularity").GetString() != "1h" || root.GetProperty("measurement").GetString() != "request_created_to_completed") throw new FormatException();
                var models = root.GetProperty("models"); if (models.GetArrayLength() is < 1 or > 50) throw new FormatException();
                var rows = new List<ServiceRow>();
                foreach (var model in models.EnumerateArray())
                {
                    var name = model.GetProperty("model_name").GetString()!; var label = model.GetProperty("label").GetString()!; var health = model.GetProperty("state").GetString()!;
                    var series = model.GetProperty("series"); if (series.GetArrayLength() > 3 || string.IsNullOrWhiteSpace(name) || string.IsNullOrWhiteSpace(label) || label.Length > 60) throw new FormatException();
                    bool hasData = false; var detail = new List<string>();
                    foreach (var s in series.EnumerateArray()) { var points = s.GetProperty("points"); if (points.GetArrayLength() > 200) throw new FormatException(); var available = points.EnumerateArray().Any(p => p.GetProperty("state").GetString() == "available"); hasData |= available; var variant = s.GetProperty("variant").GetString(); detail.Add((variant switch { "standard" => "일반", "draft" => "드래프트", "final" => "본생성", _ => variant }) + ": " + (available ? HealthLabel(s.GetProperty("state").GetString()) : "확인 중")); }
                    if (health == "operational" && !hasData) health = "checking";
                    rows.Add(new(name, label, health, string.Join(" · ", detail)));
                }
                if (rows.Select(r => r.Name).Distinct().Count() != rows.Count) throw new FormatException();
                cached = rows; stale = root.GetProperty("stale").GetBoolean(); calculatedAt = root.TryGetProperty("calculated_at", out var date) && DateTimeOffset.TryParse(date.GetString(), out var at) ? at : null;
                etag = Validator(response.Headers.ETag?.ToString()); modified = Validator(response.Content.Headers.LastModified?.ToString("R"));
            }
            serverAtReceipt = serverNow; receiptUptime = CompanionStore.Uptime; error = false; schedule.Success(CompanionStore.Uptime);
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { }
        catch { error = true; schedule.Fail(CompanionStore.Uptime, retry, Random.Shared.NextDouble()); }
        finally { busy = false; cancellation.Dispose(); cancellation = null; Changed?.Invoke(); }
    }
    private static string? Validator(string? value) => value is { Length: > 0 and <= 512 } && !value.Contains('\n') && !value.Contains('\r') ? value : null;
    public static string HealthLabel(string? health) => health switch { "operational" => "정상", "delayed" => "지연", "degraded" => "오류 증가", _ => "확인 중" };
    public void Dispose() { timer.Stop(); cancellation?.Cancel(); client.Dispose(); }
}
