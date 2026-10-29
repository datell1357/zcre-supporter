using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using ZcreSupporter;
using Microsoft.Web.WebView2.Core;

internal static class RecoveryChecks
{
    internal static int Run(string directory)
    {
        if (!Path.IsPathFullyQualified(directory) || Directory.Exists(directory)) throw new ArgumentException();
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        app.Resources["BackgroundBrush"] = new SolidColorBrush(Color.FromRgb(17, 18, 20));
        app.Startup += async (_, _) =>
        {
            DashboardWindow? dashboard = null;
            try
            {
                LocalData.Initialize(["--data-dir", directory]);
                // Given an absent fixed-runtime directory, the real SDK fails without opening a web page.
                var attempts = 0;
                using (var session = new WebSession(async () => { attempts++; await Task.Yield(); return await CoreWebView2Environment.CreateAsync(Path.Combine(directory, "missing-runtime"), LocalData.PathFor("WebView2")); }))
                {
                    var first = session.StartAsync();
                    if (!ReferenceEquals(first, session.StartAsync())) throw new InvalidOperationException("Concurrent initialization was not shared.");
                    await ExpectFailure(first);
                    // When retrying a completed failure, then a new SDK attempt must run.
                    var second = session.StartAsync();
                    if (ReferenceEquals(first, second)) throw new InvalidOperationException("Initialization retry reused the original faulted Task.");
                    await ExpectFailure(second);
                    if (attempts != 2) throw new InvalidOperationException("Expected exactly two actual SDK initialization attempts.");
                    Console.WriteLine("PASS actual WebView2 initialization failure can retry; concurrent calls share one pending attempt");
                }
                // Given a real preference replacement failure; keep every fixture and pending file intact.
                Directory.CreateDirectory(LocalData.PathFor("preferences.json"));
                using var store = new CompanionStore(); using var status = new ServiceStatus();
                await store.StartAsync(true); dashboard = new(store, status); dashboard.ShowSettings();
                var settings = app.Windows.Cast<Window>().Single(w => w.Title == "ZCRE 서포터 · 설정");
                store.SavePreferences();
                // Then the actual open settings panel reports failure rather than implying persistence.
                if (!store.PreferencesSaveFailed || !Texts(settings).Any(t => t.Visibility == Visibility.Visible && t.Foreground == Brushes.Orange && t.Text.Length > 0)) throw new InvalidOperationException("Preference failure was not visible in the existing settings window.");
                LocalData.Initialize(["--data-dir", Path.Combine(directory, "recovered")]);
                store.Preferences.PetScale = 1.2; store.SavePreferences();
                if (store.PreferencesSaveFailed || LocalData.LoadPreferences().PetScale != 1.2 || Texts(settings).Any(t => t.Foreground == Brushes.Orange && t.Visibility == Visibility.Visible)) throw new InvalidOperationException("Successful save did not clear the visible error and persist preferences.");
                Console.WriteLine("PASS actual failed preference write is visible; a subsequent successful save persists and clears the error");
                app.Shutdown(0);
            }
            catch (Exception error) { Console.WriteLine("FAIL native recovery: " + error.GetType().Name + ": " + error.Message); app.Shutdown(1); }
            finally { dashboard?.Shutdown(); }
        };
        return app.Run();
    }
    private static async Task ExpectFailure(Task task)
    {
        try { await task.WaitAsync(TimeSpan.FromSeconds(20)); }
        catch (Exception error) when (error is WebView2RuntimeNotFoundException or System.Runtime.InteropServices.COMException or IOException or UnauthorizedAccessException or ArgumentException) { Console.WriteLine("Expected SDK failure: " + error.GetType().Name); return; }
        throw new InvalidOperationException("The unusable SDK profile unexpectedly initialized.");
    }
    private static IEnumerable<TextBlock> Texts(DependencyObject root)
    {
        if (root is TextBlock text) yield return text;
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++)
            foreach (var item in Texts(VisualTreeHelper.GetChild(root, i))) yield return item;
    }
}
