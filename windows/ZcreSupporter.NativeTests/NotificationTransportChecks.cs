using System.IO;
using System.IO.Pipes;
using ZcreSupporter;
using ZcreSupporter.Core;

internal static class NotificationTransportChecks
{
    internal static int Run() => RunAsync().GetAwaiter().GetResult();
    private static async Task<int> RunAsync()
    {
        try
        {
            var argument = "action=alerts;scope=" + NotificationActivation.ScopeFor(AppContext.BaseDirectory, null);
            var name = "ZcreSupporter.NotificationTransportTest." + Guid.NewGuid().ToString("N");
            var received = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
            using var blocker = new NamedPipeServerStream(name, PipeDirection.In, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
            using var channel = new NotificationActivationChannel(value => received.TrySetResult(value), name);
            await Task.Delay(250);
            if (channel.LastFailureKind != nameof(IOException)) throw new InvalidOperationException("A busy pipe did not report its creation failure.");
            blocker.Dispose();
            if (!await NotificationActivationChannel.SendAsync(argument, name) || await received.Task.WaitAsync(TimeSpan.FromSeconds(4)) != argument)
                throw new InvalidOperationException("Listener did not recover after the pipe name became available.");
            Console.WriteLine("PASS real named pipe recovers after server creation collision and forwards the complete scope token");

            var slowName = name + ".slow";
            var afterTimeout = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
            using var timeoutChannel = new NotificationActivationChannel(value => afterTimeout.TrySetResult(value), slowName);
            using var stalled = new NamedPipeClientStream(".", slowName, PipeDirection.Out, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
            using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(2));
            await stalled.ConnectAsync(deadline.Token);
            await Task.Delay(3300);
            if (timeoutChannel.LastFailureKind != "Timeout") throw new InvalidOperationException("A stalled client did not time out.");
            if (!await NotificationActivationChannel.SendAsync(argument, slowName) || await afterTimeout.Task.WaitAsync(TimeSpan.FromSeconds(4)) != argument)
                throw new InvalidOperationException("A stalled client permanently blocked later activation.");
            Console.WriteLine("PASS stalled activation client times out and the next valid activation is still received");
            return 0;
        }
        catch (Exception error) { Console.WriteLine("FAIL notification transport: " + error.GetType().Name + ": " + error.Message); return 1; }
    }
}
