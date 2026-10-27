using System.Text.Json;

namespace ZcreSupporter.Core;

public sealed record MonitorEvent(string Kind, Job? Job, decimal? Credits = null);

public sealed class Monitor
{
    private string? workspace;
    private DateTimeOffset? baseline;
    private Dictionary<string, Job> known = [];
    private readonly Queue<string> alerted = [];
    private bool wasLow;
    public string[] ActiveIds => known.Values.Where(j => j.Active || j.State == JobStatus.Unknown).Select(j => j.Id).Order().ToArray();
    public void Reset() { workspace = null; baseline = null; known.Clear(); alerted.Clear(); wasLow = false; }
    public List<MonitorEvent> Ingest(Snapshot snapshot, decimal threshold)
    {
        if (workspace != snapshot.WorkspaceKey) { Reset(); workspace = snapshot.WorkspaceKey; }
        var events = new List<MonitorEvent>();
        var low = snapshot.BalanceIsStale ? wasLow : snapshot.Balance.AvailableValue <= threshold;
        if (baseline is not null)
        {
            foreach (var job in snapshot.Jobs.Where(j => j.State is JobStatus.Succeeded or JobStatus.Failed))
            {
                var finished = known.TryGetValue(job.Id, out var prior) ? !prior.Terminal : job.CreatedAt >= baseline;
                if (finished && !alerted.Contains(job.Id)) { events.Add(new(job.State == JobStatus.Succeeded ? "completed" : "failed", job)); alerted.Enqueue(job.Id); }
            }
            if (low && !wasLow) events.Add(new("lowCredits", null, snapshot.Balance.AvailableValue));
        }
        known = known.Where(x => !x.Value.Terminal).ToDictionary(x => x.Key, x => x.Value);
        foreach (var job in snapshot.Jobs) known[job.Id] = job;
        while (alerted.Count > 1024) alerted.Dequeue();
        wasLow = low; baseline ??= snapshot.FetchedAt;
        return events;
    }
}

public sealed record Alert(string Id, string Kind, string Title, string Body, DateTimeOffset CreatedAt, bool IsRead, string Source, string? JobKey);

public sealed class History
{
    public int Version { get; set; } = 1;
    public string WorkspaceHash { get; set; } = "";
    public List<Alert> Alerts { get; set; } = [];
    public DateTimeOffset? ClearedThrough { get; set; }
    public static History Load(string path, string workspaceHash)
    {
        try
        {
            if (new FileInfo(path).Length > 256000) return new() { WorkspaceHash = workspaceHash };
            var value = JsonSerializer.Deserialize<History>(File.ReadAllText(path), Json.Options);
            if (value is { Version: 1, Alerts: not null } && value.WorkspaceHash == workspaceHash && value.Alerts.Count <= 30 && value.Alerts.All(a => a is not null && !string.IsNullOrEmpty(a.Id) && a.Title is not null && a.Body is not null && a.CreatedAt != default && a.Kind is "completed" or "failed" or "lowCredits" && a.Source is "notification" or "workHistory")) return value;
        }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { }
        return new() { WorkspaceHash = workspaceHash };
    }
    public void Merge(IEnumerable<Job> jobs, bool demo)
    {
        var keys = Alerts.Select(a => a.JobKey).ToHashSet();
        var oldest = Alerts.Count >= 30 ? Alerts.Min(a => a.CreatedAt) : DateTimeOffset.MinValue;
        foreach (var job in jobs.Where(j => j.State is JobStatus.Succeeded or JobStatus.Failed))
        {
            if (job.CreatedAt <= ClearedThrough || job.CreatedAt < oldest || !keys.Add(job.HistoryKey)) continue;
            Alerts.Add(new(Guid.NewGuid().ToString(), job.State == JobStatus.Succeeded ? "completed" : "failed", (demo ? "[미리보기] " : "") + (job.State == JobStatus.Succeeded ? "작업 완료" : "작업 실패"), job.WorkName, job.CreatedAt, true, "workHistory", job.HistoryKey));
        }
        Trim();
    }
    public void Trim() => Alerts = Alerts.OrderByDescending(a => a.CreatedAt).Take(30).ToList();
    public void Clear(DateTimeOffset now) { Alerts.Clear(); ClearedThrough = now; }
    public void MarkRead(int count) => Alerts = Alerts.Select((a, i) => i < count ? a with { IsRead = true } : a).ToList();
}
