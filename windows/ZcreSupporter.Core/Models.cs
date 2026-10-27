using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace ZcreSupporter.Core;

public static class Json
{
    public static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web) { WriteIndented = true };
    public static string Hash(string value) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value))).ToLowerInvariant();
}

public enum JobStatus { Queued, Running, Succeeded, Failed, Cancelled, Unknown }

public sealed record Job(string Id, string Model, string MediaType, string Status, DateTimeOffset CreatedAt)
{
    public JobStatus State => Normalize(Status);
    public bool Active => State is JobStatus.Queued or JobStatus.Running;
    public bool Terminal => State is JobStatus.Succeeded or JobStatus.Failed or JobStatus.Cancelled;
    public string StateLabel => State switch { JobStatus.Queued => "대기 중", JobStatus.Running => "만드는 중", JobStatus.Succeeded => "완료", JobStatus.Failed => "실패", JobStatus.Cancelled => "취소됨", _ => "상태 확인 중" };
    public string DisplayName => Model switch { "seedance-2.5" => "Seedance 2.5", "gpt-image-2" => "GPT Image 2", "topaz-upscale-video-precision" => "Topaz 영상 업스케일", "bytedance-upscale-video" => "영상 업스케일", _ => Model.Replace('-', ' ') };
    public string WorkName => DisplayName.Contains("업스케일") ? DisplayName : DisplayName + " " + (MediaType switch { "video" => "영상", "audio" => "오디오", _ => "이미지" });
    public string StartLabel => CreatedAt.ToLocalTime().ToString("HH:mm");
    public string HistoryKey => Json.Hash(Id + ":" + State.ToString().ToLowerInvariant());
    public static JobStatus Normalize(string status) => status.ToLowerInvariant() switch
    {
        "pending" or "queued" or "accepted" or "submitted" or "waiting" or "received" or "validated" or "queued_internal" => JobStatus.Queued,
        "running" or "processing" or "in_progress" or "generating" or "submitting_provider" or "submitted_provider" or "running_provider" or "asset_ingesting" => JobStatus.Running,
        "succeeded" or "completed" or "complete" or "success" => JobStatus.Succeeded,
        "failed" or "error" or "timeout" or "timed_out" => JobStatus.Failed,
        "cancelled" or "canceled" => JobStatus.Cancelled,
        _ => JobStatus.Unknown
    };
}

public sealed record Balance(string Total, string Reserved, string Available)
{
    public decimal AvailableValue => decimal.Parse(Available, CultureInfo.InvariantCulture);
    public static string Format(string value) => decimal.Parse(value, CultureInfo.InvariantCulture).ToString("#,0.##", CultureInfo.GetCultureInfo("ko-KR"));
    public void Validate()
    {
        foreach (var value in new[] { Total, Reserved, Available })
            if (!Regex.IsMatch(value, @"^-?[0-9]+(?:\.[0-9]+)?$") || !decimal.TryParse(value, NumberStyles.AllowDecimalPoint | NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out _)) throw new SnapshotException("invalidResponse");
        if (decimal.Parse(Reserved, CultureInfo.InvariantCulture) < 0) throw new SnapshotException("invalidResponse");
    }
}

public sealed record Concurrency(int ImagesActive, int ImagesLimit, int VideosActive, int VideosLimit, int TotalActive, int TotalLimit);

public sealed record Snapshot(string WorkspaceKey, string WorkspaceName, Balance Balance, List<Job> Jobs, double BalanceFetchedAt, bool BalanceIsStale, bool HistoryTruncated, Concurrency? Concurrency)
{
    public DateTimeOffset FetchedAt { get; init; } = DateTimeOffset.UtcNow;
    public IReadOnlyList<Job> ActiveJobs => Jobs.Where(j => j.Active).ToArray();
    public static Snapshot Decode(string json, DateTimeOffset now)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object) throw new SnapshotException("invalidResponse");
            if (root.TryGetProperty("error", out var error) && error.ValueKind != JsonValueKind.Null)
            {
                if (error.ValueKind != JsonValueKind.String) throw new SnapshotException("invalidResponse");
                throw new SnapshotException(error.GetString() ?? "invalidResponse", root.TryGetProperty("status", out var code) && code.ValueKind == JsonValueKind.Number && code.TryGetInt32(out var n) ? n : 0);
            }
            var next = JsonSerializer.Deserialize<Snapshot>(json, Json.Options) ?? throw new SnapshotException("invalidResponse");
            if (string.IsNullOrWhiteSpace(next.WorkspaceKey) || next.Balance is null || next.Jobs is null) throw new SnapshotException("invalidResponse");
            var fetched = root.TryGetProperty("balanceFetchedAt", out _) ? next.BalanceFetchedAt : now.ToUnixTimeMilliseconds();
            if (!double.IsFinite(fetched) || fetched <= 0) throw new SnapshotException("invalidResponse");
            next.Balance.Validate();
            if (next.Jobs.Any(j => j is null || string.IsNullOrEmpty(j.Id) || string.IsNullOrEmpty(j.Model) || j.Status is null || j.MediaType is null || j.CreatedAt == default)) throw new SnapshotException("invalidResponse");
            var jobs = next.Jobs.DistinctBy(j => j.Id).OrderByDescending(j => j.CreatedAt).ToList();
            var limits = next.Concurrency;
            if (limits is not null)
                limits = limits.ImagesLimit > 0 && limits.VideosLimit > 0 && limits.TotalLimit > 0
                    ? limits with { ImagesActive = jobs.Count(j => j.Active && j.MediaType == "image"), VideosActive = jobs.Count(j => j.Active && j.MediaType == "video"), TotalActive = jobs.Count(j => j.Active) } : null;
            return next with { WorkspaceName = next.WorkspaceName ?? "개인 워크스페이스", Jobs = jobs, FetchedAt = now, BalanceFetchedAt = fetched, Concurrency = limits };
        }
        catch (Exception error) when (error is JsonException or FormatException or OverflowException or ArgumentException or InvalidOperationException or KeyNotFoundException) { throw new SnapshotException("invalidResponse"); }
    }
}

public sealed class SnapshotException(string kind, int status = 0) : Exception(kind)
{
    public string Kind { get; } = kind;
    public int Status { get; } = status;
    public string UserMessage => Kind switch { "authentication" => "ZCRE 계정 연결이 필요해요", "accountChanged" => "계정이 바뀌어 다시 확인하고 있어요", "unsupportedWorkspace" => "크레딧 개인 워크스페이스를 선택해 주세요", "http" => $"서버 조회 지연 ({Status})", "invalidResponse" => "응답 형식을 확인할 수 없어요", _ => "연결이 지연돼 마지막 확인값을 표시해요" };
}

public sealed record JobOutput(string Id, string? MediaType, string? ContentType, string Url, string? OriginalURL, double? Expires)
{
    public static Uri? SafeUrl(string? value)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri) || uri.Scheme != "https" || uri.UserInfo.Length != 0 || uri.HostNameType != UriHostNameType.Dns || uri.IsLoopback || uri.Host.EndsWith(".local", StringComparison.OrdinalIgnoreCase) || uri.Host.EndsWith(".localhost", StringComparison.OrdinalIgnoreCase)) return null;
        return uri;
    }
    public Uri? Preview => SafeUrl(Url);
    public Uri? Download => SafeUrl(OriginalURL) ?? Preview;
    public string Kind => ContentType?.Split('/')[0] is "image" or "video" or "audio" ? ContentType.Split('/')[0] : MediaType ?? "unknown";
    public string Extension => ContentType?.Split(';')[0] switch { "image/png" => "png", "image/jpeg" => "jpg", "image/webp" => "webp", "video/mp4" => "mp4", "video/webm" => "webm", "audio/mpeg" => "mp3", "audio/wav" => "wav", "audio/mp4" => "m4a", _ => "bin" };
    public static Uri ResultUrl(Job job) => new("https://www.zcre.co.kr" + (job.MediaType == "audio" ? "/studio/audio?j=" + Uri.EscapeDataString(job.Id) : "/results/" + Uri.EscapeDataString(job.Id)));
}

public static class Demo
{
    public static Snapshot Snapshot(int step = 0) => new("demo", "미리보기 워크스페이스", new("1280", step == 0 ? "120" : "40", step == 0 ? "1160" : "1240"),
    [new("demo-video", "seedance-2.5", "video", step == 0 ? "running" : "succeeded", DateTimeOffset.Now.AddMinutes(-3)), new("demo-image", "gpt-image-2", "image", "queued", DateTimeOffset.Now.AddMinutes(-2)), new("demo-upscale", "bytedance-upscale-video", "video", "succeeded", DateTimeOffset.Now.AddMinutes(-8))], DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(), false, false, new(1, 4, step == 0 ? 1 : 0, 2, step == 0 ? 2 : 1, 4));
}

public sealed record BridgeMessage(string Channel, string? Event, string? Id, string? Value)
{
    public static BridgeMessage? Decode(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json); var r = doc.RootElement;
            if (r.ValueKind != JsonValueKind.Object || !r.TryGetProperty("channel", out var c) || c.ValueKind != JsonValueKind.String) return null;
            if (c.GetString() == "session" && r.TryGetProperty("event", out var e) && e.ValueKind == JsonValueKind.String && e.GetString() is "ready" or "changed") return new("session", e.GetString(), null, null);
            if (c.GetString() == "bridge" && r.TryGetProperty("id", out var id) && id.ValueKind == JsonValueKind.String && id.GetString() is { Length: > 0 and <= 100 } && r.TryGetProperty("value", out var value) && value.ValueKind == JsonValueKind.String) return new("bridge", null, id.GetString(), value.GetString());
        }
        catch (JsonException) { }
        return null;
    }
}

public static class OutputPayload
{
    public static List<JobOutput> Decode(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json); var r = doc.RootElement;
            if (r.ValueKind != JsonValueKind.Object || !r.TryGetProperty("outputs", out var values) || values.ValueKind != JsonValueKind.Array || values.GetArrayLength() > 64) throw new SnapshotException("invalidResponse");
            var outputs = JsonSerializer.Deserialize<List<JobOutput>>(values, Json.Options) ?? throw new SnapshotException("invalidResponse");
            if (outputs.Any(o => o is null || string.IsNullOrEmpty(o.Id) || o.Preview is null || o.Expires is { } seconds && (!double.IsFinite(seconds) || seconds < 0))) throw new SnapshotException("invalidResponse");
            return outputs;
        }
        catch (Exception e) when (e is JsonException or InvalidOperationException or KeyNotFoundException or ArgumentException) { throw new SnapshotException("invalidResponse"); }
    }
}
