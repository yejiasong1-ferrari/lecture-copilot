using System.Diagnostics;

namespace LectureCopilot.Windows.Services;

public sealed class ForegroundWindowService
{
    private IntPtr _previous;

    public void RememberUnlessDoubao()
    {
        var hwnd = NativeMethods.GetForegroundWindow();
        if (hwnd == IntPtr.Zero || DoubaoService.IsDoubaoWindow(hwnd)) return;
        _previous = NativeMethods.GetAncestor(hwnd, NativeMethods.GaRoot);
        Logger.Write($"Remembered foreground hwnd=0x{_previous.ToInt64():X}");
    }

    public void Restore()
    {
        if (_previous == IntPtr.Zero || !NativeMethods.IsWindow(_previous)) return;
        NativeMethods.ShowWindow(_previous, NativeMethods.SwRestore);
        NativeMethods.SetForegroundWindow(_previous);
    }

    public static void OpenPath(string path)
    {
        Process.Start(new ProcessStartInfo { FileName = path, UseShellExecute = true });
    }
}
