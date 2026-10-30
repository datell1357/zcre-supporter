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
                using var session = new WebSession();
                await session.StartAsync();
                var deadline = DateTimeOffset.UtcNow.AddSeconds(35);
                while ((!session.Loaded || await session.View.ExecuteScriptAsync("Boolean(window.Clerk?.loaded)") != "true") && DateTimeOffset.UtcNow < deadline) await Task.Delay(200);
                using var readCancellation = new CancellationTokenSource(TimeSpan.FromSeconds(25));
                var candidate = await session.SnapshotAsync([], null, false, readCancellation.Token);
                if (!session.Accept(candidate.Revision, candidate.Snapshot)) throw new InvalidOperationException("Existing session changed during the read-only snapshot check.");
                var snapshot = candidate.Snapshot;
                Console.WriteLine("PASS preserved app-owned login session supplies validated credits and job snapshot (values and identifiers omitted)");
                var succeeded = snapshot.Jobs.FirstOrDefault(j => j.State == ZcreSupporter.Core.JobStatus.Succeeded);
                if (succeeded is null) Console.WriteLine("UNVERIFIED existing result metadata: no completed job in the returned snapshot");
                else
                {
                    using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(20));
                    var outputs = await session.OutputsAsync(succeeded, snapshot.WorkspaceKey, cancellation.Token);
                    if (outputs.Count == 0) throw new InvalidOperationException("Existing completed job returned no result metadata.");
                    Console.WriteLine("PASS existing completed result metadata returned validated HTTPS media; URLs and job content omitted; no media saved or generation requested");
                }
                Console.WriteLine("PASS account inspection used the session adapter only; no app preferences or alert history written");
                app.Shutdown(0);
            }
            catch (Exception error) { Console.WriteLine("FAIL account read check: " + error.GetType().Name + (error is InvalidOperationException ? ": " + error.Message : "")); app.Shutdown(1); }
        };
        return app.Run();
    }
}
