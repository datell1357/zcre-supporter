using System.Globalization;
using System.Text.Json;
using ZcreSupporter.Core;
using Monitor = ZcreSupporter.Core.Monitor;

var passed = new List<string>();
void Check(string name, bool value) { if (!value) throw new InvalidOperationException("FAIL " + name); passed.Add(name); Console.WriteLine("PASS " + name); }
var repo = Path.GetFullPath(args.Length > 0 ? args[0] : "../..");
using (var fixture = JsonDocument.Parse(File.ReadAllText(Path.Combine(repo, "Tests", "ParityFixtures", "decoder.json"))))
{
    foreach (var item in fixture.RootElement.EnumerateArray())
    {
        var name = item.GetProperty("name").GetString(); var expected = item.GetProperty("valid").GetBoolean();
        try
        {
            var snapshot = Snapshot.Decode(item.GetProperty("payload").GetRawText(), DateTimeOffset.UtcNow);
            Check("decoder fixture " + name, expected);
            if (expected) { Check(name + " decimal", snapshot.Balance.Available == item.GetProperty("available").GetString()); Check(name + " active", snapshot.ActiveJobs.Count == item.GetProperty("activeCount").GetInt32()); if (item.TryGetProperty("imagesActive", out var images)) { Check(name + " images", snapshot.Concurrency?.ImagesActive == images.GetInt32()); Check(name + " videos", snapshot.Concurrency?.VideosActive == item.GetProperty("videosActive").GetInt32()); } }
        }
        catch (SnapshotException) { Check("decoder fixture " + name, !expected); }
    }
}
using (var fixture = JsonDocument.Parse(File.ReadAllText(Path.Combine(repo, "Tests", "ParityFixtures", "monitor.json"))))
{
    foreach (var scenario in fixture.RootElement.EnumerateArray())
    {
        var monitor = new Monitor(); var step = 0;
        foreach (var item in scenario.GetProperty("steps").EnumerateArray())
        {
            var snapshot = Snapshot.Decode(item.GetProperty("payload").GetRawText(), DateTimeOffset.FromUnixTimeSeconds(item.GetProperty("at").GetInt64()));
            var actual = monitor.Ingest(snapshot, 50).Select(e => e.Kind + ":" + (e.Job?.Id ?? e.Credits?.ToString(CultureInfo.InvariantCulture)));
            var expected = item.GetProperty("events").EnumerateArray().Select(e => e.GetString());
            Check($"fixture/{scenario.GetProperty("name").GetString()}/{step}/events", actual.SequenceEqual(expected));
            Check($"fixture/{scenario.GetProperty("name").GetString()}/{step++}/tracked", monitor.ActiveIds.SequenceEqual(item.GetProperty("tracked").EnumerateArray().Select(e => e.GetString())));
        }
    }
}
var epoch = new BridgeEpoch(); var generation = epoch.Generation;
Check("ACK candidate is not accepted", epoch.Candidate(generation, "r1", "a") && epoch.AcceptedRevision == "");
Check("ACK wrong revision rejected", !epoch.Accept("other", "a"));
Check("ACK correct revision", epoch.Accept("r1", "a") && epoch.AcceptedRevision == "r1");
epoch.Reset(); Check("late account response rejected", !epoch.Candidate(generation, "r2", "a") && epoch.AcceptedRevision == "");
Check("HTTPS trusted main origin", BridgeEpoch.TrustedOrigin("https://www.zcre.co.kr/credits"));
Check("external source rejected", !BridgeEpoch.TrustedOrigin("https://www.zcre.co.kr.evil.test/"));
Check("HTTP source rejected", !BridgeEpoch.TrustedOrigin("http://www.zcre.co.kr/"));
Check("custom port rejected", !BridgeEpoch.TrustedOrigin("https://www.zcre.co.kr:444/"));
Check("credential origin rejected", !BridgeEpoch.TrustedOrigin("https://user:password@www.zcre.co.kr/"));
foreach (var bad in new[] { "http://cdn.example/a", "https://user:pass@cdn.example/a", "https://127.0.0.1/a", "https://[::1]/a", "https://localhost/a", "https://host.local/a", "file:///a" }) Check("unsafe output rejected " + bad, JobOutput.SafeUrl(bad) is null);
Check("signed HTTPS output allowed", JobOutput.SafeUrl("https://cdn.example/result.mp4?signature=example") is not null);
var preferences = new Preferences { FocusSchedule = true };
Check("overnight focus evening", preferences.IsFocusActive(new DateTime(2026, 10, 27, 23, 0, 0)));
Check("overnight focus morning", preferences.IsFocusActive(new DateTime(2026, 10, 27, 7, 59, 0)));
Check("focus end exclusive", !preferences.IsFocusActive(new DateTime(2026, 10, 27, 8, 0, 0)));
preferences.FocusStartMinute = preferences.FocusEndMinute; Check("equal focus means all day", preferences.IsFocusActive(DateTime.Now));
preferences.UpscaleJobAlerts = false; Check("upscale filter precedes video", !preferences.Allows(new("a", "topaz-upscale-video", "video", "running", DateTimeOffset.Now)));
var schedule = new AccountSchedule(); schedule.Started(0); Check("manual minimum five seconds", schedule.Next == 5); schedule.Finished(0, 9, 0, false, 0); Check("slow requests never overlap", schedule.Next == 10);
schedule.Finished(0, 0, 10, false, 1); Check("backoff capped", schedule.Next == 300);
Check("Retry-After seconds", AccountSchedule.RetryAfter("600", DateTimeOffset.Now) == 600);
var status = new PublicSchedule(); Check("public first request", status.Begin(0, false)); status.Success(0); Check("public reopen cache", !status.Begin(10, false)); Check("public manual minimum", !status.Begin(4, true)); Check("public manual after minimum", status.Begin(5, true)); status.Fail(5, 1000, 0); Check("public retry-after retained", status.Next(true) == 1005);
var history = new History { WorkspaceHash = Json.Hash("account") }; var job = new Job("secret-id", "test", "image", "succeeded", DateTimeOffset.Now.AddMinutes(-1)); history.Merge([job], false); Check("old work history read", history.Alerts.Single().IsRead); history.Clear(DateTimeOffset.Now); history.Merge([job], false); Check("cleared old work stays cleared", history.Alerts.Count == 0);
history.Merge([job with { CreatedAt = DateTimeOffset.Now.AddMinutes(1) }], false); Check("new work imports after clear", history.Alerts.Count == 1);
Check("history raw IDs excluded", !JsonSerializer.Serialize(history, Json.Options).Contains("secret-id"));
var diagonal = ZcreSupporter.Core.Point.Step(new(0, 0), new(100, 100), 30); Check("diagonal normalized speed", Math.Abs(Math.Sqrt(diagonal.X * diagonal.X + diagonal.Y * diagonal.Y) - 30) < .001);
Check("one-shot final frame", SpriteTiming.Frame(100, 12, 41.66, false) == 11); Check("loop wraps", SpriteTiming.Frame(1, 12, 100, true) == 10);
try { Snapshot.Decode("{\"workspaceKey\":\"a\",\"balance\":{\"total\":\"NaN\",\"reserved\":\"0\",\"available\":\"0\"},\"jobs\":[]}", DateTimeOffset.Now); throw new Exception("invalid balance accepted"); } catch (SnapshotException) { Check("invalid balance fails closed", true); }
foreach (var (name, body) in new[] { ("null job", "{\"workspaceKey\":\"a\",\"balance\":{\"total\":\"1\",\"reserved\":\"0\",\"available\":\"1\"},\"jobs\":[null]}"), ("missing jobs", "{\"workspaceKey\":\"a\",\"balance\":{\"total\":\"1\",\"reserved\":\"0\",\"available\":\"1\"}}"), ("negative reserved", "{\"workspaceKey\":\"a\",\"balance\":{\"total\":\"1\",\"reserved\":\"-1\",\"available\":\"1\"},\"jobs\":[]}"), ("invalid date", "{\"workspaceKey\":\"a\",\"balance\":{\"total\":\"1\",\"reserved\":\"0\",\"available\":\"1\"},\"jobs\":[{\"id\":\"a\",\"model\":\"m\",\"mediaType\":\"image\",\"status\":\"running\",\"createdAt\":\"invalid\"}]}") })
{ try { Snapshot.Decode(body, DateTimeOffset.Now); throw new Exception("accepted " + name); } catch (SnapshotException) { Check("decoder rejects " + name, true); } }
var duplicate = Demo.Snapshot(); duplicate.Jobs.Add(duplicate.Jobs[0]); Check("duplicate job ID deduplicates", Snapshot.Decode(JsonSerializer.Serialize(duplicate, Json.Options), DateTimeOffset.Now).Jobs.Count == 3);
foreach (var bad in new[] { "[]", "null", "{}", "{\"channel\":3}", "{\"channel\":\"session\"}", "{\"channel\":\"session\",\"event\":[]}", "{\"channel\":\"bridge\",\"id\":3,\"value\":\"a\"}" }) Check("bridge envelope rejects " + bad, BridgeMessage.Decode(bad) is null);
Check("bridge session message", BridgeMessage.Decode("{\"channel\":\"session\",\"event\":\"changed\"}")?.Event == "changed");
Check("bridge result message", BridgeMessage.Decode("{\"channel\":\"bridge\",\"id\":\"request\",\"value\":\"{}\"}")?.Value == "{}");
foreach (var bad in new[] { "[]", "null", "{}", "{\"outputs\":[null]}", "{\"outputs\":[{\"id\":\"x\",\"url\":\"http://example.com/a\"}]}" }) { try { OutputPayload.Decode(bad); throw new Exception("bad outputs accepted"); } catch (SnapshotException) { Check("output payload rejects " + bad, true); } }
var testPath = Path.Combine(repo, "windows", ".local", "core-tests-" + DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()); Directory.CreateDirectory(testPath);
foreach (var malformed in new[] { "null", "[]", "{\"version\":1,\"workspaceHash\":\"hash\",\"alerts\":null}", "{\"version\":1,\"workspaceHash\":\"hash\",\"alerts\":[null]}" }) { var path = Path.Combine(testPath, Guid.NewGuid().ToString("N") + ".json"); File.WriteAllText(path, malformed); Check("corrupt history rejected " + malformed, History.Load(path, "hash").Alerts.Count == 0); }
foreach (var screen in new[] { new RectD(0, 0, 1440, 900), new RectD(-1920, -200, 1920, 1080), new RectD(0, 0, 800, 600) })
foreach (var anchor in new[] { new RectD(screen.X + 20, screen.Y + 20, 90, 110), new RectD(screen.MaxX - 110, screen.Y + 20, 90, 110), new RectD(screen.MidX - 45, screen.MidY - 55, 90, 110), new RectD(screen.X + 20, screen.MaxY - 130, 90, 110) })
foreach (var count in new[] { 5, 6, 8 })
{
    var menu = new PetMenuLayout(anchor, screen, count, count == 5); Check("menu all buttons " + screen + anchor + count, menu.Buttons.Count == count);
    Check("menu inside screen " + screen + anchor + count, menu.Buttons.All(screen.Contains));
    Check("menu protects pet and label " + screen + anchor + count, menu.Buttons.All(b => !menu.Protected.Any(p => p.Intersects(b))));
    Check("menu no overlap " + screen + anchor + count, menu.Buttons.Select((b, i) => !menu.Buttons.Skip(i + 1).Any(b.Intersects) && !menu.Summary.Intersects(b)).All(x => x));
}
var compact = new PetMenuLayout(new(600, 400, 90, 110), new(0, 0, 1440, 900), 5, true); Check("compact home menu radius", compact.Radius is >= 110 and <= 120);
var wave = new IdleWaveSchedule(); Check("idle wave earliest 45 seconds", wave.Delay(0, true, true, 0) == 45); Check("walk preserves wave deadline", wave.Delay(50, true, false, 1) is null && wave.DueAt == 45); Check("idle after walk waves immediately", wave.Delay(50, true, true, 1) == 0); Check("work clears wave deadline", wave.Delay(51, false, false, 1) is null && wave.DueAt is null);
Console.WriteLine(JsonSerializer.Serialize(new { status = "passed", count = passed.Count, tests = passed }, Json.Options));
