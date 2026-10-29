using ZcreSupporter.Core;

internal static class ParityAuditChecks
{
    internal static void Run(Action<string, bool> check)
    {
        // Given case-insensitive media preferences, when an API job preserves mixed case,
        // then the matching filter still suppresses its live presentation.
        foreach (var media in new[] { "VIDEO", "Video", "AUDIO", "Image" })
        {
            var preferences = new Preferences { VideoJobAlerts = false, AudioJobAlerts = false, ImageJobAlerts = false };
            var job = new Job("case-fixture", "test-model", media, "succeeded", DateTimeOffset.UnixEpoch);
            var history = new History();
            var decision = AlertPolicy.Record(new("completed", job), preferences, history, false, DateTimeOffset.UnixEpoch.AddMinutes(1));
            check("mixed-case media honors the corresponding filter: " + media, decision is { Present: false } && history.Alerts.Count == 1);
        }
        // Given the alternate WAV MIME used by supported audio results, when saving,
        // then the file extension remains usable by the OS audio player.
        var wav = new JobOutput("audio-fixture", "audio", "audio/x-wav; codecs=pcm", "https://cdn.example/audio", null, 30);
        check("alternate WAV MIME preserves wav extension", wav.Extension == "wav");
    }
}
