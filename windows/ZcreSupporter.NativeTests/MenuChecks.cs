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
                var image = Descendants(pet).OfType<Image>().Single(); var transform = image.RenderTransform;
                await Task.Delay(250);
                if (!ReferenceEquals(transform, image.RenderTransform)) throw new InvalidOperationException("Pet rebuilt its transform graph on subsequent animation frames.");
                Console.WriteLine("PASS actual animated pet reuses its transform graph across frames");
                pet.ShowMenu("home"); await Task.Delay(250);
                var windows = app.Windows.Cast<Window>().Where(w => w.Title == "지크 원형 메뉴").ToArray();
                if (windows.Length != 7 || windows.Any(w => !w.IsVisible)) throw new InvalidOperationException("Expected summary and six visible menu actions, including canvas; actual windows=" + windows.Length);
                var texts = windows.SelectMany(Descendants).OfType<TextBlock>().ToArray();
                var credit = texts.Single(t => t.Text.StartsWith("사용 가능 "));
                var counts = texts.Single(t => t.Text.StartsWith("이미지 "));
                var beforeCredit = credit.Text; var beforeCounts = counts.Text;
                if (!beforeCredit.Contains("1,160") || !beforeCounts.EndsWith("합계 2")) throw new InvalidOperationException();
                store.SimulateCompletion(); await Task.Delay(250);
                if (!credit.Text.Contains("1,240") || !counts.Text.EndsWith("합계 1") || windows.Any(w => !w.IsVisible) || app.Windows.Cast<Window>().Count(w => w.Title == "지크 원형 메뉴") != 7) throw new InvalidOperationException();
                var outside = new Window { Title = "Isolated menu dismissal test", Width = 200, Height = 120 };
                outside.Show(); outside.Activate(); await app.Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle);
                if (app.Windows.Cast<Window>().Any(w => w.Title == "지크 원형 메뉴")) throw new InvalidOperationException("Radial menu did not close after outside activation.");
                outside.Close(); pet.ShowMenu("home");
                var canvas = app.Windows.Cast<Window>().Where(w => w.Title == "지크 원형 메뉴").SelectMany(Descendants).OfType<Button>().Single(b => Equals(b.Content, "캔버스"));
                string? requested = null; pet.ToolRequested += path => requested = path;
                canvas.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                if (requested != "/studio/canvas" || app.Windows.Cast<Window>().Any(w => w.Title == "지크 원형 메뉴")) throw new InvalidOperationException("Canvas action did not close the menu and request its official route.");
                Console.WriteLine("PASS six WPF radial-menu actions and summary; original TextBlocks update in place; outside activation dismisses; canvas requests official route without generation");
                Console.WriteLine("Synthetic demo before: " + beforeCredit + " / " + beforeCounts);
                Console.WriteLine("Synthetic demo after: " + credit.Text + " / " + counts.Text);
                app.Shutdown(0);
            }
            catch (Exception error) { Console.WriteLine("FAIL native radial menu: " + error.GetType().Name + ": " + error.Message); app.Shutdown(1); }
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
