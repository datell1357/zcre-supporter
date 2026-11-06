using System.IO.Pipes;
using System.Text;
using System.Diagnostics;
using System.Security.Principal;

namespace ZcreSupporter;

internal sealed class NotificationActivationChannel : IDisposable
{
    private static readonly string Name = "ZcreSupporter.NotificationActivation.v1." + Process.GetCurrentProcess().SessionId + "." + Json.Hash(WindowsIdentity.GetCurrent().User!.Value)[..16];
    private readonly CancellationTokenSource stop = new();
    private readonly Task listener;
    private readonly string channelName;
    internal string? LastFailureKind { get; private set; }
    public NotificationActivationChannel(Action<string> received, string? channelName = null)
    {
        this.channelName = channelName ?? Name;
        listener = ListenAsync(received);
    }

    private async Task ListenAsync(Action<string> received)
    {
        while (!stop.IsCancellationRequested)
        {
            try
            {
                using var pipe = new NamedPipeServerStream(channelName, PipeDirection.In, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
                await pipe.WaitForConnectionAsync(stop.Token);
                using var deadline = CancellationTokenSource.CreateLinkedTokenSource(stop.Token);
                deadline.CancelAfter(TimeSpan.FromSeconds(3));
                var header = new byte[4]; await pipe.ReadExactlyAsync(header, deadline.Token);
                var length = BitConverter.ToInt32(header);
                if (length is <= 0 or > NotificationActivation.MaximumArgumentLength) continue;
                var bytes = new byte[length]; await pipe.ReadExactlyAsync(bytes, deadline.Token);
                received(Encoding.UTF8.GetString(bytes));
            }
            catch (OperationCanceledException) when (stop.IsCancellationRequested) { break; }
            catch (OperationCanceledException) { LastFailureKind = "Timeout"; }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
                if (LastFailureKind != error.GetType().Name) Trace.WriteLine("Notification activation channel: " + error.GetType().Name);
                LastFailureKind = error.GetType().Name;
                try { await Task.Delay(100, stop.Token); } catch (OperationCanceledException) { break; }
            }
        }
    }

    public static async Task<bool> SendAsync(string argument, string? channelName = null)
    {
        var bytes = Encoding.UTF8.GetBytes(argument);
        if (bytes.Length is 0 or > NotificationActivation.MaximumArgumentLength) return false;
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(3));
        using var pipe = new NamedPipeClientStream(".", channelName ?? Name, PipeDirection.Out, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
        try
        {
            await pipe.ConnectAsync(deadline.Token);
            await pipe.WriteAsync(BitConverter.GetBytes(bytes.Length), deadline.Token);
            await pipe.WriteAsync(bytes, deadline.Token); await pipe.FlushAsync(deadline.Token);
            return true;
        }
        catch (Exception error) when (error is IOException or OperationCanceledException or UnauthorizedAccessException) { return false; }
    }

    public void Dispose() { stop.Cancel(); _ = listener.ContinueWith(_ => stop.Dispose(), TaskScheduler.Default); }
}
