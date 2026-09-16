using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace LectureCopilot.Windows.Services;

public sealed class HotKeyService : IDisposable
{
    private readonly HwndSource _source;
    private readonly NativeMethods.HookProc _hookProc;
    private IntPtr _hook;
    private bool _shiftDown;
    private bool _shiftWasChord;
    private DateTime _shiftDownAt;
    private DateTime? _lastBareShiftUp;

    public event Action<Models.HotKeyEvent>? Pressed;

    public HotKeyService()
    {
        _source = new HwndSource(new HwndSourceParameters("LectureCopilotHotKeys")
        {
            Width = 0,
            Height = 0,
            WindowStyle = unchecked((int)0x80000000)
        });
        _source.AddHook(WindowProc);
        _hookProc = KeyboardHook;
    }

    public void Start()
    {
        Register(1, NativeMethods.VkLeft);
        Register(2, NativeMethods.VkRight);
        Register(3, NativeMethods.VkUp);
        Register(4, NativeMethods.VkDown);
        Register(5, NativeMethods.VkReturn);
        using var process = Process.GetCurrentProcess();
        using var module = process.MainModule;
        _hook = NativeMethods.SetWindowsHookEx(NativeMethods.WhKeyboardLl, _hookProc,
            NativeMethods.GetModuleHandle(module?.ModuleName), 0);
        Logger.Write("Global hotkeys and double-Shift hook started");
    }

    private void Register(int id, int key)
    {
        if (!NativeMethods.RegisterHotKey(_source.Handle, id, NativeMethods.ModShift, (uint)key))
            Logger.Write($"RegisterHotKey failed id={id} error={Marshal.GetLastWin32Error()}");
    }

    private IntPtr WindowProc(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (message != NativeMethods.WmHotKey) return IntPtr.Zero;
        handled = true;
        var item = wParam.ToInt32() switch
        {
            1 => Models.HotKeyEvent.ShiftLeft,
            2 => Models.HotKeyEvent.ShiftRight,
            3 => Models.HotKeyEvent.ShiftUp,
            4 => Models.HotKeyEvent.ShiftDown,
            5 => Models.HotKeyEvent.ShiftReturn,
            _ => (Models.HotKeyEvent?)null
        };
        if (item is not null) Pressed?.Invoke(item.Value);
        return IntPtr.Zero;
    }

    private IntPtr KeyboardHook(int code, IntPtr wParam, IntPtr lParam)
    {
        if (code < 0) return NativeMethods.CallNextHookEx(_hook, code, wParam, lParam);
        var data = Marshal.PtrToStructure<NativeMethods.KeyboardHookStruct>(lParam);
        var key = (int)data.VkCode;
        var down = wParam.ToInt32() is NativeMethods.WmKeyDown or NativeMethods.WmSysKeyDown;
        var up = wParam.ToInt32() is NativeMethods.WmKeyUp or NativeMethods.WmSysKeyUp;
        var isShift = key is NativeMethods.VkShift or NativeMethods.VkLShift or NativeMethods.VkRShift;

        if (!isShift && down && _shiftDown)
        {
            _shiftWasChord = true;
            _lastBareShiftUp = null;
        }
        else if (isShift && down && !_shiftDown)
        {
            _shiftDown = true;
            _shiftWasChord = false;
            _shiftDownAt = DateTime.UtcNow;
        }
        else if (isShift && up && _shiftDown)
        {
            _shiftDown = false;
            var now = DateTime.UtcNow;
            if (!_shiftWasChord && now - _shiftDownAt <= TimeSpan.FromMilliseconds(350))
            {
                if (_lastBareShiftUp is { } previous && now - previous <= TimeSpan.FromMilliseconds(450))
                {
                    _lastBareShiftUp = null;
                    Application.Current.Dispatcher.BeginInvoke(() => Pressed?.Invoke(Models.HotKeyEvent.ToggleHud));
                }
                else _lastBareShiftUp = now;
            }
            else _lastBareShiftUp = null;
        }
        return NativeMethods.CallNextHookEx(_hook, code, wParam, lParam);
    }

    public void Dispose()
    {
        for (var id = 1; id <= 5; id++) NativeMethods.UnregisterHotKey(_source.Handle, id);
        if (_hook != IntPtr.Zero) NativeMethods.UnhookWindowsHookEx(_hook);
        _source.Dispose();
    }
}
