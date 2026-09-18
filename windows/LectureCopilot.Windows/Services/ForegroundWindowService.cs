using System.Diagnostics;
using System.Text;

namespace LectureCopilot.Windows.Services;

public sealed class ForegroundWindowService
{
    private IntPtr _previous;

    public void RememberUnlessDoubao()
    {
        var hwnd = NativeMethods.GetForegroundWindow();
        if (hwnd == IntPtr.Zero || DoubaoService.IsDoubaoWindow(hwnd)) return;
        var candidate = NativeMethods.GetAncestor(hwnd, NativeMethods.GaRoot);
        NativeMethods.GetWindowThreadProcessId(candidate, out var pid);
        if (pid == (uint)Environment.ProcessId) return;
        _previous = candidate;
        Logger.Write($"Remembered classroom window hwnd=0x{_previous.ToInt64():X} {Describe(_previous)}");
    }

    public void Restore()
    {
        if (_previous == IntPtr.Zero || !NativeMethods.IsWindow(_previous)) return;
        Logger.Write($"Restoring classroom window {Describe(_previous)}");
        // SW_RESTORE also turns a maximized browser into a normal sized window.
        if (NativeMethods.IsIconic(_previous)) NativeMethods.ShowWindow(_previous, NativeMethods.SwRestore);
        NativeMethods.AllowSetForegroundWindow(NativeMethods.AsfwAny);
        var currentThread = NativeMethods.GetCurrentThreadId();
        var foregroundThread = (uint)NativeMethods.GetWindowThreadProcessId(NativeMethods.GetForegroundWindow(), out _);
        var classroomThread = (uint)NativeMethods.GetWindowThreadProcessId(_previous, out _);
        var attachedForeground = foregroundThread != 0 && foregroundThread != currentThread
            && NativeMethods.AttachThreadInput(currentThread, foregroundThread, true);
        var attachedClassroom = classroomThread != 0 && classroomThread != currentThread
            && classroomThread != foregroundThread && NativeMethods.AttachThreadInput(currentThread, classroomThread, true);
        NativeMethods.BringWindowToTop(_previous);
        NativeMethods.SetForegroundWindow(_previous);
        if (NativeMethods.GetAncestor(NativeMethods.GetForegroundWindow(), NativeMethods.GaRoot) != _previous)
        {
            NativeMethods.SwitchToThisWindow(_previous, true);
            NativeMethods.SetForegroundWindow(_previous);
        }
        if (attachedClassroom) NativeMethods.AttachThreadInput(currentThread, classroomThread, false);
        if (attachedForeground) NativeMethods.AttachThreadInput(currentThread, foregroundThread, false);
        var active = NativeMethods.GetAncestor(NativeMethods.GetForegroundWindow(), NativeMethods.GaRoot);
        Logger.Write($"Classroom restore {(active == _previous ? "confirmed" : $"failed; active=0x{active.ToInt64():X}")}");
    }

    public static void OpenPath(string path)
    {
        Process.Start(new ProcessStartInfo { FileName = path, UseShellExecute = true });
    }

    private static string Describe(IntPtr hwnd)
    {
        NativeMethods.GetWindowThreadProcessId(hwnd, out var pid);
        var title = new StringBuilder(256);
        NativeMethods.GetWindowText(hwnd, title, title.Capacity);
        var process = "?";
        try { process = Process.GetProcessById((int)pid).ProcessName; } catch { }
        return $"process={process} title='{title}'";
    }
}
