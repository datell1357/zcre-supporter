using System.IO;
using System.Security.Cryptography;
using System.Text.Json;
using System.Windows;
using Microsoft.Web.WebView2.Wpf;
using ZcreSupporter;
using ZcreSupporter.Core;

internal static class MediaChecks
{
    internal static int Run(string[] args)
    {
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        app.Startup += async (_, _) =>
        {
            try
            {
                if (args[0] == "--media") await DocumentAsync(args[1], new Uri("https://media-test.invalid/clip.mp4?a=1&b=2"), false);
                else if (args[0] == "--saved-media") await DocumentAsync(Path.GetDirectoryName(args[1])!, new Uri("https://media-test.invalid/saved-result.mp4"), true, args[1]);
                else await ExistingAsync(args[1], args[2]);
                app.Shutdown(0);
            }
            catch (Exception error)
            {
                // Do not emit URLs, account data or exception messages from the authenticated path.
                Console.WriteLine("FAIL native media check: " + error.GetType().Name);
                Console.WriteLine(error.StackTrace);
                app.Shutdown(1);
            }
        };
        return app.Run();
    }

    private static async Task ExistingAsync(string profile, string destination)
    {
        if (!Path.IsPathFullyQualified(profile) || !Path.IsPathFullyQualified(destination) || File.Exists(destination)) throw new ArgumentException();
        LocalData.Initialize(["--data-dir", profile]);
        using var store = new CompanionStore();
        await store.StartAsync(false);
        var deadline = DateTime.UtcNow.AddSeconds(75);
        while (store.Snapshot is null && DateTime.UtcNow < deadline) await Task.Delay(250);
        var snapshot = store.Snapshot ?? throw new TimeoutException();
        var job = snapshot.Jobs.First(j => j.State == JobStatus.Succeeded && j.MediaType == "video");
        var outputs = await store.Session.OutputsAsync(job, snapshot.WorkspaceKey, CancellationToken.None);
        var output = outputs.First(o => o.Kind == "video");
        await MediaPreview.DownloadAsync(output.Download!, destination, CancellationToken.None);
        using var file = File.OpenRead(destination);
        var bytes = file.Length;
        if (bytes == 0) throw new InvalidDataException();
        var sha256 = Convert.ToHexString(SHA256.HashData(file)).ToLowerInvariant();
        Console.WriteLine(JsonSerializer.Serialize(new { saved = true, path = destination, bytes, sha256 }));
        await DocumentAsync(Path.GetDirectoryName(destination)!, output.Preview!, true);
        Console.WriteLine("PASS existing authenticated result downloaded and decoded; no generation submitted");
    }

    private static async Task DocumentAsync(string directory, Uri preview, bool decode, string? savedFile = null)
    {
        Directory.CreateDirectory(directory);
        using var player = new WebView2 { Height = 340 };
        var window = new Window { Title = "ZCRE 미디어 통합 검증", Width = 820, Height = 450, Content = player };
        window.Show();
        var streams = new List<Stream>();
        try
        {
            var environment = await Microsoft.Web.WebView2.Core.CoreWebView2Environment.CreateAsync(null, Path.Combine(directory, "NativeMediaWebView2"));
            var options = environment.CreateCoreWebView2ControllerOptions(); options.IsInPrivateModeEnabled = true; options.ProfileName = "MediaPrivate";
            await player.EnsureCoreWebView2Async(environment, options);
            if (savedFile is not null)
            {
                player.CoreWebView2.AddWebResourceRequestedFilter(preview.AbsoluteUri, Microsoft.Web.WebView2.Core.CoreWebView2WebResourceContext.Media);
                player.CoreWebView2.WebResourceRequested += (_, e) =>
                {
                    if (e.Request.Uri != preview.AbsoluteUri) return;
                    var stream = File.OpenRead(savedFile); streams.Add(stream);
                    e.Response = environment.CreateWebResourceResponse(stream, 200, "OK", "Content-Type: video/mp4\r\nAccept-Ranges: none");
                };
            }
            player.CoreWebView2.Settings.AreDevToolsEnabled = false;
            player.CoreWebView2.PermissionRequested += (_, e) => e.State = Microsoft.Web.WebView2.Core.CoreWebView2PermissionState.Deny;
            player.CoreWebView2.NavigationStarting += (_, e) => Console.WriteLine("navigation about_blank=" + (e.Uri == "about:blank") + " data_html=" + e.Uri.StartsWith("data:text/html", StringComparison.OrdinalIgnoreCase));
            var navigation = new TaskCompletionSource<bool>();
            player.CoreWebView2.NavigationCompleted += (_, e) => { Console.WriteLine("navigation success=" + e.IsSuccess + " status=" + e.WebErrorStatus); navigation.TrySetResult(e.IsSuccess); };
            var states = new List<string>();
            using var cancellation = new CancellationTokenSource();
            MediaPreview.Observe(player, cancellation.Token, states.Add);
            MediaPreview.Navigate(player, "video", preview);
            if (!await navigation.Task.WaitAsync(TimeSpan.FromSeconds(15))) throw new InvalidOperationException();
            var src = JsonSerializer.Deserialize<string>(await player.ExecuteScriptAsync("document.querySelector('video').getAttribute('src')"));
            if (src != preview.AbsoluteUri) { Console.WriteLine("FAIL actual WebView2 parsed media src differs from requested URI"); throw new InvalidDataException(); }
            var csp = JsonSerializer.Deserialize<string>(await player.ExecuteScriptAsync("document.querySelector('meta[http-equiv=\"Content-Security-Policy\"]').getAttribute('content')"));
            if (csp is null || !csp.Contains("default-src 'none'") || !csp.Contains("script-src 'nonce-")) throw new InvalidDataException();
            Console.WriteLine("PASS actual WebView2 DOM preserves escaped URL and restrictive CSP");
            if (!decode) { await BoundariesAsync(player, cancellation, states); return; }
            var deadline = DateTime.UtcNow.AddSeconds(45);
            while (!states.Contains("loaded") && !states.Contains("error") && DateTime.UtcNow < deadline) await Task.Delay(200);
            if (!states.Contains("loaded"))
            {
                Console.WriteLine("media error code=" + await player.ExecuteScriptAsync("document.querySelector('video').error?.code??0"));
                throw new InvalidDataException();
            }
            // Muted playback checks decoder/frame progression without changing system volume or recording audio.
            await player.ExecuteScriptAsync("(()=>{const m=document.querySelector('video');m.muted=true;m.play().catch(()=>window.chrome.webview.postMessage({mediaState:'playDenied'}));})()");
            await Task.Delay(1500);
            using var decoded = JsonDocument.Parse(await player.ExecuteScriptAsync("(()=>{const m=document.querySelector('video');return {time:m.currentTime,width:m.videoWidth,height:m.videoHeight,ready:m.readyState,paused:m.paused}})()"));
            var root = decoded.RootElement;
            if (!states.Contains("playing") || root.GetProperty("time").GetDouble() <= 0 || root.GetProperty("width").GetInt32() <= 0 || root.GetProperty("paused").GetBoolean()) throw new InvalidDataException();
            Console.WriteLine(JsonSerializer.Serialize(new { decoded = true, muted_playback = true, current_time = root.GetProperty("time").GetDouble(), width = root.GetProperty("width").GetInt32(), height = root.GetProperty("height").GetInt32(), states = states.Distinct().ToArray() }));
            await player.ExecuteScriptAsync("document.querySelector('video').pause()");
            await BoundariesAsync(player, cancellation, states);
        }
        finally { window.Content = null; player.Dispose(); window.Close(); foreach (var stream in streams) stream.Dispose(); }
    }

    private static async Task BoundariesAsync(WebView2 player, CancellationTokenSource cancellation, List<string> states)
    {
        foreach (var target in new[] { "https://media-test.invalid/other", "data:text/html,<body>not the app document</body>" })
        {
            var done = new TaskCompletionSource<bool>();
            void Completed(object? sender, Microsoft.Web.WebView2.Core.CoreWebView2NavigationCompletedEventArgs e) => done.TrySetResult(!e.IsSuccess && e.WebErrorStatus == Microsoft.Web.WebView2.Core.CoreWebView2WebErrorStatus.OperationCanceled);
            player.CoreWebView2.NavigationCompleted += Completed;
            player.CoreWebView2.Navigate(target);
            if (!await done.Task.WaitAsync(TimeSpan.FromSeconds(10))) throw new InvalidOperationException();
            player.CoreWebView2.NavigationCompleted -= Completed;
        }
        Console.WriteLine("PASS subsequent HTTPS and arbitrary data document navigation cancelled");
        cancellation.Cancel();
        var count = states.Count;
        await player.ExecuteScriptAsync("window.chrome.webview.postMessage({mediaState:'playing'})");
        await Task.Delay(250);
        if (count != states.Count) throw new InvalidOperationException();
        Console.WriteLine("PASS late media message ignored after result lifetime cancellation");
    }
}
