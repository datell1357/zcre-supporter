using System.Net.Http;
using System.Text.Encodings.Web;
using Microsoft.Web.WebView2.Wpf;

namespace ZcreSupporter;

internal static class MediaPreview
{
    internal static void Observe(WebView2 player, CancellationToken cancellation, Action<string> changed)
    {
        player.CoreWebView2.WebMessageReceived += (_, e) =>
        {
            if (cancellation.IsCancellationRequested || e.Source != "about:blank") return;
            try
            {
                using var document = JsonDocument.Parse(e.WebMessageAsJson);
                var message = document.RootElement;
                if (message.ValueKind != JsonValueKind.Object || !message.TryGetProperty("mediaState", out var value) || value.ValueKind != JsonValueKind.String) return;
                if (value.GetString() is "loaded" or "playing" or "paused" or "ended" or "playDenied" or "error") changed(value.GetString()!);
            }
            catch (JsonException) { }
        };
    }

    internal static void Navigate(WebView2 player, string kind, Uri preview)
    {
        var html = Html(kind, preview);
        var initialDocument = true;
        player.CoreWebView2.NavigationStarting += (_, e) =>
        {
            var allowed = initialDocument && !e.IsUserInitiated && IsGeneratedDocument(e.Uri, html);
            initialDocument = false;
            e.Cancel = !allowed;
        };
        player.NavigateToString(html);
    }
    private static bool IsGeneratedDocument(string uri, string html)
    {
        if (uri == "about:blank") return true;
        var comma = uri.IndexOf(',');
        if (comma < 0) return false;
        var header = uri[..comma];
        try
        {
            return header.ToLowerInvariant() switch
            {
                "data:text/html" or "data:text/html;charset=utf-8" => Uri.UnescapeDataString(uri[(comma + 1)..]) == html,
                "data:text/html;base64" or "data:text/html;charset=utf-8;base64" => System.Text.Encoding.UTF8.GetString(Convert.FromBase64String(uri[(comma + 1)..])) == html,
                _ => false
            };
        }
        catch (FormatException) { return false; }
    }
    internal static string Html(string kind, Uri preview)
    {
        var url = HtmlEncoder.Default.Encode(preview.AbsoluteUri); var media = kind switch { "image" => $"<img src=\"{url}\" style=\"max-width:100%;max-height:320px\">", "video" => $"<video src=\"{url}\" controls style=\"max-width:100%;max-height:320px\"></video>", "audio" => $"<audio src=\"{url}\" controls></audio>", _ => "미리보기를 지원하지 않는 형식입니다." };
        var nonce = Guid.NewGuid().ToString("N");
        var monitorMedia = "const m=document.querySelector('img,video,audio');const send=mediaState=>window.chrome.webview.postMessage({mediaState});if(m){for(const name of ['load','loadeddata','canplay'])m.addEventListener(name,()=>send('loaded'));for(const name of ['playing','pause','ended','error'])m.addEventListener(name,()=>send(name==='pause'?'paused':name));if(m.tagName==='IMG'&&m.complete&&m.naturalWidth>0)send('loaded');}";
        return "<!doctype html><meta name=\"referrer\" content=\"no-referrer\"><meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; img-src https:; media-src https:; style-src 'unsafe-inline'; script-src 'nonce-" + nonce + "'\"><body style=\"background:#1c1e22;color:white;display:grid;place-items:center;margin:0\">" + media + "<script nonce=\"" + nonce + "\">" + monitorMedia + "</script>";
    }
    internal static async Task DownloadAsync(Uri uri, string destination, CancellationToken token)
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
}
