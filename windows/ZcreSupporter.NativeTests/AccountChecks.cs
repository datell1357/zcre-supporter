using System.IO;
using System.Windows;
using ZcreSupporter;

internal static class AccountChecks
{
    internal static int Run(string directory)
    {
        if (!Path.IsPathFullyQualified(directory) || !Directory.Exists(Path.Combine(directory, "WebView2"))) throw new ArgumentException("An existing app-owned profile is required; no account setup or reset is performed.");
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        app.Startup += async (_, _) =>
        {
            try
            {
                LocalData.Initialize(["--data-dir", directory]);
                using var store = new CompanionStore();
                await store.StartAsync(false);
                var deadline = DateTimeOffset.UtcNow.AddSeconds(35);
                while (store.Snapshot is null && DateTimeOffset.UtcNow < deadline) await Task.Delay(200);
                if (store.Snapshot is not { } snapshot) throw new InvalidOperationException("Existing session did not provide a verified snapshot; pageLoaded=" + store.Session.Loaded + "; state=" + store.Connection);
                Console.WriteLine("PASS preserved app-owned login session supplies validated credits and job snapshot (values and identifiers omitted)");
                var succeeded = snapshot.Jobs.FirstOrDefault(j => j.State == ZcreSupporter.Core.JobStatus.Succeeded);
                if (succeeded is null) Console.WriteLine("UNVERIFIED existing result metadata: no completed job in the returned snapshot");
                else
                {
                    using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(20));
                    var outputs = await store.Session.OutputsAsync(succeeded, snapshot.WorkspaceKey, cancellation.Token);
                    if (outputs.Count == 0) throw new InvalidOperationException("Existing completed job returned no result metadata.");
                    Console.WriteLine("PASS existing completed result metadata returned validated HTTPS media; URLs and job content omitted; no media saved or generation requested");
                }
                app.Shutdown(0);
            }
            catch (Exception error) { Console.WriteLine("FAIL account read check: " + error.GetType().Name + (error is InvalidOperationException ? ": " + error.Message : "")); app.Shutdown(1); }
        };
        return app.Run();
    }
}
