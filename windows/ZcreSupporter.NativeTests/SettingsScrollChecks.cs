using System.Windows;
using System.Windows.Automation.Peers;
using System.Windows.Automation.Provider;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Threading;

internal static class SettingsScrollChecks
{
    internal static async Task Run(ScrollViewer scroll)
    {
        async Task Top() { scroll.ScrollToTop(); await Idle(); }
        Task Idle() => scroll.Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle).Task;
        await Top();
        scroll.RaiseEvent(new MouseWheelEventArgs(Mouse.PrimaryDevice, Environment.TickCount, -120) { RoutedEvent = Mouse.MouseWheelEvent });
        await Idle();
        if (scroll.VerticalOffset <= 0) throw new InvalidOperationException("Themed settings wheel input did not scroll content.");
        await Top();
        scroll.RaiseEvent(new KeyEventArgs(Keyboard.PrimaryDevice, PresentationSource.FromVisual(scroll), Environment.TickCount, Key.PageDown) { RoutedEvent = Keyboard.KeyDownEvent });
        await Idle();
        if (scroll.VerticalOffset <= 0) throw new InvalidOperationException("Themed settings PageDown input did not scroll content.");
        await Top();
        var bar = (ScrollBar)scroll.Template.FindName("PART_VerticalScrollBar", scroll);
        var track = (Track)bar.Template.FindName("PART_Track", bar);
        ((RoutedCommand)track.IncreaseRepeatButton.Command).Execute(track.IncreaseRepeatButton.CommandParameter, track.IncreaseRepeatButton);
        await Idle();
        if (scroll.VerticalOffset <= 0) throw new InvalidOperationException("Themed track paging did not scroll content.");
        await Top();
        track.Thumb.RaiseEvent(new DragStartedEventArgs(0, 0));
        track.Thumb.RaiseEvent(new DragDeltaEventArgs(0, 40));
        track.Thumb.RaiseEvent(new DragCompletedEventArgs(0, 40, false));
        await Idle();
        if (scroll.VerticalOffset <= 0) throw new InvalidOperationException("Themed thumb drag events did not scroll content.");
        var peer = UIElementAutomationPeer.CreatePeerForElement(scroll);
        if (peer?.GetPattern(PatternInterface.Scroll) is not IScrollProvider { VerticallyScrollable: true }) throw new InvalidOperationException("Themed settings lost the accessibility scroll pattern.");
        Console.WriteLine("PASS actual WPF themed settings wheel, PageDown, track paging, thumb drag events and accessibility scroll pattern");
    }
}
