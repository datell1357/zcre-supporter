using System.Runtime.InteropServices;
using System.Windows.Media.Imaging;

namespace ZcreSupporter;

internal sealed class TrayIcon : System.Windows.Forms.NativeWindow, IDisposable
{
    private const uint CallbackMessage = 0x8001;
    private readonly uint taskbarCreated = RegisterWindowMessage("TaskbarCreated");
    private readonly System.Drawing.Icon[] running;
    private readonly System.Drawing.Icon still;
    private readonly System.Windows.Forms.ContextMenuStrip menu = new();
    private readonly CompanionStore store;
    private readonly DispatcherTimer animation = new() { Interval = TimeSpan.FromMilliseconds(48) };
    private int frame;
    private NotifyData data;
    public event Action? Open;
    public event Action? OpenSettings;
    public event Action? OpenAlerts;
    public event Action? Exit;
    public Func<bool>? IsDebugWorking;
    public TrayIcon(CompanionStore store)
    {
        this.store = store;
        CreateHandle(new System.Windows.Forms.CreateParams { Caption = "ZCRE Supporter tray message host" });
        still = Icon(Sprites.Get("still").Frames[0]); var clip = Sprites.Get("run"); running = Enumerable.Range(0, 12).Select(i => Icon(clip.Frames[i * clip.Frames.Length / 12])).ToArray();
        data = new() { Size = (uint)Marshal.SizeOf<NotifyData>(), Window = Handle, Id = 1, Flags = 1 | 2 | 4, Callback = CallbackMessage, Icon = still.Handle, Tip = "ZCRE 서포터", Info = "", Title = "" };
        ShellNotifyIcon(0, ref data);
        animation.Tick += (_, _) => { if (!store.IsSleeping && SystemParameters.ClientAreaAnimation && (store.ActiveCount > 0 || IsDebugWorking?.Invoke() == true)) data.Icon = running[frame++ % running.Length].Handle; else data.Icon = still.Handle; Update(); };
        store.Changed += Refresh; Refresh();
    }
    private static System.Drawing.Icon Icon(BitmapSource frame)
    {
        var visual = new DrawingVisual(); using (var context = visual.RenderOpen()) { var ratio = Math.Min(26d / frame.PixelWidth, 26d / frame.PixelHeight); context.DrawImage(frame, new Rect((32 - frame.PixelWidth * ratio) / 2, (32 - frame.PixelHeight * ratio) / 2, frame.PixelWidth * ratio, frame.PixelHeight * ratio)); }
        var bitmap = new RenderTargetBitmap(32, 32, 96, 96, PixelFormats.Pbgra32); bitmap.Render(visual); var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap)); using var stream = new MemoryStream(); encoder.Save(stream); stream.Position = 0; using var image = new System.Drawing.Bitmap(stream); var handle = image.GetHicon(); try { return (System.Drawing.Icon)System.Drawing.Icon.FromHandle(handle).Clone(); } finally { DestroyIcon(handle); }
    }
    private void Refresh()
    {
        var tooltip = "ZCRE 서포터" + (store.Preferences.ShowTrayCredits ? " · " + store.CreditText + " Credit" : "") + " · 작업 " + store.ActiveCount;
        data.Tip = tooltip.Length <= 127 ? tooltip : tooltip[..127]; Update();
        if (!store.IsSleeping && (store.ActiveCount > 0 || IsDebugWorking?.Invoke() == true)) animation.Start(); else { animation.Stop(); data.Icon = still.Handle; Update(); }
    }
    private void Update() { data.Flags = 2 | 4; ShellNotifyIcon(1, ref data); }
    public bool Notify(Alert alert, bool sound)
    {
        data.Flags = 16; data.Info = alert.Body.Length > 255 ? alert.Body[..255] : alert.Body; data.Title = alert.Title.Length > 63 ? alert.Title[..63] : alert.Title; data.InfoFlags = 1u | (sound ? 0u : 0x10u); data.Timeout = 8000; var accepted = ShellNotifyIcon(1, ref data); Update(); return accepted;
    }
    public void ClearNotification() { data.Flags = 16; data.Info = ""; data.Title = ""; ShellNotifyIcon(1, ref data); Update(); }
    protected override void WndProc(ref System.Windows.Forms.Message message)
    {
        if ((uint)message.Msg == taskbarCreated) { data.Flags = 1 | 2 | 4; ShellNotifyIcon(0, ref data); }
        if ((uint)message.Msg == CallbackMessage)
        {
            switch ((int)message.LParam)
            {
                case 0x202: Application.Current.Dispatcher.BeginInvoke(() => Open?.Invoke()); break;
                case 0x205:
                    menu.Items.Clear();
                    menu.Items.Add("현황판", null, (_, _) => Open?.Invoke()); menu.Items.Add("설정", null, (_, _) => OpenSettings?.Invoke());
                    menu.Items.Add(store.Preferences.PetVisible ? "지크 숨기기" : "지크 보이기", null, (_, _) => { store.Preferences.PetVisible = !store.Preferences.PetVisible; store.SavePreferences(); });
                    menu.Items.Add("최근 알림", null, (_, _) => OpenAlerts?.Invoke()); menu.Items.Add("종료", null, (_, _) => Exit?.Invoke()); menu.Show(System.Windows.Forms.Cursor.Position); break;
                case 0x405: Application.Current.Dispatcher.BeginInvoke(() => OpenAlerts?.Invoke()); break;
            }
        }
        base.WndProc(ref message);
    }
    public void Dispose() { animation.Stop(); store.Changed -= Refresh; ShellNotifyIcon(2, ref data); DestroyHandle(); menu.Dispose(); still.Dispose(); foreach (var icon in running) icon.Dispose(); }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NotifyData
    {
        public uint Size; public IntPtr Window; public uint Id, Flags, Callback; public IntPtr Icon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Tip;
        public uint State, StateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string Info;
        public uint Timeout;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string Title;
        public uint InfoFlags; public Guid Guid; public IntPtr BalloonIcon;
    }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, EntryPoint = "Shell_NotifyIconW")] private static extern bool ShellNotifyIcon(uint action, ref NotifyData data);
    [DllImport("user32.dll")] private static extern bool DestroyIcon(IntPtr handle);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern uint RegisterWindowMessage(string name);
}
