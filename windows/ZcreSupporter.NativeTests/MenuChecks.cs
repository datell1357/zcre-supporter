using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using ZcreSupporter;

internal static class MenuChecks
{
    internal static int Run(string directory)
    {
        if (!Path.IsPathFullyQualified(directory) || Directory.Exists(directory)) throw new ArgumentException();
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        app.Startup += async (_, _) =>
        {
            PetWindow? pet = null;
            try
            {
                LocalData.Initialize(["--data-dir", directory]);
                using var store = new CompanionStore();
                await store.StartAsync(true);
                pet = new PetWindow(store); pet.Show(); await Task.Delay(250);
                pet.ShowMenu("home"); await Task.Delay(250);
                var windows = app.Windows.Cast<Window>().Where(w => w.Title == "지크 원형 메뉴").ToArray();
                if (windows.Length != 6 || windows.Any(w => !w.IsVisible)) throw new InvalidOperationException();
                var texts = windows.SelectMany(Descendants).OfType<TextBlock>().ToArray();
                var credit = texts.Single(t => t.Text.StartsWith("사용 가능 "));
                var counts = texts.Single(t => t.Text.StartsWith("이미지 "));
                var beforeCredit = credit.Text; var beforeCounts = counts.Text;
                if (!beforeCredit.Contains("1,160") || !beforeCounts.EndsWith("합계 2")) throw new InvalidOperationException();
                store.SimulateCompletion(); await Task.Delay(250);
                if (!credit.Text.Contains("1,240") || !counts.Text.EndsWith("합계 1") || windows.Any(w => !w.IsVisible) || app.Windows.Cast<Window>().Count(w => w.Title == "지크 원형 메뉴") != 6) throw new InvalidOperationException();
                Console.WriteLine("PASS actual six visible WPF radial-menu windows remain open; original TextBlocks update in place");
                Console.WriteLine("Synthetic demo before: " + beforeCredit + " / " + beforeCounts);
                Console.WriteLine("Synthetic demo after: " + credit.Text + " / " + counts.Text);
                app.Shutdown(0);
            }
            catch (Exception error) { Console.WriteLine("FAIL native radial menu: " + error.GetType().Name); app.Shutdown(1); }
            finally { pet?.Shutdown(); }
        };
        return app.Run();
    }

    private static IEnumerable<DependencyObject> Descendants(DependencyObject root)
    {
        yield return root;
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++)
            foreach (var child in Descendants(VisualTreeHelper.GetChild(root, i))) yield return child;
    }
}
