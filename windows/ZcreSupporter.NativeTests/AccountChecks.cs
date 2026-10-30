using System.IO;
using System.Windows;
using System.Text.Json;
using ZcreSupporter;

internal static class AccountChecks
{
    internal static int Identity(string directory)
    {
        var expected = Environment.GetEnvironmentVariable("ZCRE_EXPECTED_ACCOUNT_EMAIL");
        if (string.IsNullOrWhiteSpace(expected) || !Path.IsPathFullyQualified(directory) || !Directory.Exists(Path.Combine(directory, "WebView2"))) throw new ArgumentException("An existing profile and expected account environment value are required.");
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        app.Startup += async (_, _) =>
        {
            try
            {
                LocalData.Initialize(["--data-dir", directory]);
                using var session = new WebSession();
                var deadline = DateTimeOffset.UtcNow.AddSeconds(35); await session.StartAsync().WaitAsync(TimeSpan.FromSeconds(20));
                var script = "(()=>{const c=window.Clerk;if(!c?.loaded)return 'loading';const email=c.user?.primaryEmailAddress?.emailAddress;if(typeof email!=='string')return 'signed-out';return email.toLowerCase()===" + JsonSerializer.Serialize(expected.Trim().ToLowerInvariant()) + "?'matched':'different';})()";
                while (DateTimeOffset.UtcNow < deadline)
                {
                    if (session.Loaded)
                    {
                        var state = JsonSerializer.Deserialize<string>(await session.View.ExecuteScriptAsync(script));
                        if (state == "matched") { Console.WriteLine("PASS preserved app-owned session matches the designated account; identity value omitted; no app settings or history written"); app.Shutdown(0); return; }
                        if (state is "different" or "signed-out") { Console.WriteLine("UNVERIFIED designated account in preserved profile: " + state + "; identity values omitted; profile retained"); app.Shutdown(2); return; }
                    }
                    await Task.Delay(200);
                }
                Console.WriteLine("UNVERIFIED designated account: trusted SDK state did not become ready; profile retained"); app.Shutdown(2);
            }
            catch (Exception error) { Console.WriteLine("FAIL account identity check: " + error.GetType().Name); app.Shutdown(1); }
        };
        return app.Run();
    }
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
