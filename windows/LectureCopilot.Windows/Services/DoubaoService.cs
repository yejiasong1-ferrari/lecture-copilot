using System.Diagnostics;
using System.Text;
using System.Windows.Automation;

namespace LectureCopilot.Windows.Services;

public sealed record DoubaoResult(bool Success, string Message);

public sealed class DoubaoService
{
    private static readonly string[] ProcessHints = ["doubao", "doubaobrowser"];
    private (double X, double Y)? _cachedCopyPoint;

    public bool IsRunning => FindWindow() != IntPtr.Zero;

    public async Task<bool> EnsureRunningAsync(bool activate)
    {
        var hwnd = FindWindow();
        if (hwnd == IntPtr.Zero)
        {
            StartDoubao();
            for (var i = 0; i < 80 && hwnd == IntPtr.Zero; i++)
            {
                await Task.Delay(100);
                hwnd = FindWindow();
            }
        }
        if (hwnd == IntPtr.Zero) return false;
        if (activate) Activate(hwnd);
        return true;
    }

    public async Task<DoubaoResult> SendImageAndPromptAsync(string prompt)
    {
        if (!await EnsureRunningAsync(true)) return new(false, "豆包没有在运行。请先安装并登录豆包 Windows 客户端。");
        var hwnd = FindWindow();
        NewChat(hwnd);
        await Task.Delay(650);
        FocusComposer(hwnd);
        InputSimulator.Chord(NativeMethods.VkControl, NativeMethods.VkV);
        await Task.Delay(850);
        await ClipboardService.SetTextAsync(prompt);
        FocusComposer(hwnd);
        InputSimulator.Chord(NativeMethods.VkControl, NativeMethods.VkV);
        await Task.Delay(100);
        InputSimulator.Press(NativeMethods.VkReturn);
        Logger.Write("Screenshot and prompt sent to Doubao");
        return new(true, "");
    }

    public async Task<DoubaoResult> SendTextAsync(string text)
    {
        if (!await EnsureRunningAsync(true)) return new(false, "豆包没有在运行。请先安装并登录豆包 Windows 客户端。");
        var hwnd = FindWindow();
        NewChat(hwnd);
        await Task.Delay(650);
        await ClipboardService.SetTextAsync(text);
        FocusComposer(hwnd);
        InputSimulator.Chord(NativeMethods.VkControl, NativeMethods.VkV);
        await Task.Delay(100);
        InputSimulator.Press(NativeMethods.VkReturn);
        Logger.Write("Class summary prompt sent to Doubao");
        return new(true, "");
    }

    public async Task<string?> CopyLatestAnswerAsync(string prompt)
    {
        if (!await EnsureRunningAsync(true)) return null;
        var hwnd = FindWindow();
        ScrollConversationToBottom(hwnd);
        HoverLatestResponse(hwnd);
        await Task.Delay(140);

        if (_cachedCopyPoint is { } cached && NativeMethods.GetWindowRect(hwnd, out var bounds))
        {
            var point = ((int)(bounds.Left + (bounds.Right - bounds.Left) * cached.X),
                         (int)(bounds.Top + (bounds.Bottom - bounds.Top) * cached.Y));
            var copied = await ClickAndReadAsync(point.Item1, point.Item2, prompt);
            if (copied is not null) return copied;
        }

        var target = FindLatestCopyControl(hwnd);
        if (target is null)
        {
            Logger.Write("Copy control not found in Doubao UIA tree");
            return null;
        }

        var rect = target.Current.BoundingRectangle;
        if (rect.IsEmpty) return null;
        var x = (int)rect.Left + Math.Max(1, (int)rect.Width / 2);
        var y = (int)rect.Top + Math.Max(1, (int)rect.Height / 2);
        string? result = null;

        try
        {
            var sentinel = $"lecture-copilot-copy-{Guid.NewGuid():N}";
            await ClipboardService.SetTextAsync(sentinel);
            if (target.TryGetCurrentPattern(InvokePattern.Pattern, out var pattern))
                ((InvokePattern)pattern).Invoke();
            else InputSimulator.Click(x, y);
            result = await ClipboardService.WaitForChangedTextAsync(sentinel, TimeSpan.FromMilliseconds(450));
        }
        catch (Exception ex) { Logger.Write($"UIA Copy invoke failed: {ex.Message}"); }

        result ??= await ClickAndReadAsync(x, y, prompt);
        if (IsUsable(result, prompt) && NativeMethods.GetWindowRect(hwnd, out bounds))
        {
            _cachedCopyPoint = ((x - bounds.Left) / (double)(bounds.Right - bounds.Left),
                                (y - bounds.Top) / (double)(bounds.Bottom - bounds.Top));
            return result!.Trim();
        }
        return null;
    }

    public string InspectTree()
    {
        var output = Path.Combine(AppPaths.SupportDirectory, "doubao-accessibility.txt");
        var hwnd = FindWindow();
        if (hwnd == IntPtr.Zero) return output;
        var root = AutomationElement.FromHandle(hwnd);
        var builder = new StringBuilder();
        foreach (AutomationElement element in root.FindAll(TreeScope.Descendants, Condition.TrueCondition))
        {
            try
            {
                var r = element.Current.BoundingRectangle;
                builder.AppendLine($"{element.Current.ControlType.ProgrammaticName} name=\"{element.Current.Name}\" id=\"{element.Current.AutomationId}\" rect={r}");
            }
            catch { }
        }
        File.WriteAllText(output, builder.ToString());
        return output;
    }

    public static bool IsDoubaoWindow(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return false;
        NativeMethods.GetWindowThreadProcessId(hwnd, out var pid);
        try
        {
            var process = Process.GetProcessById((int)pid);
            if (ProcessHints.Any(x => process.ProcessName.Contains(x, StringComparison.OrdinalIgnoreCase))) return true;
        }
        catch { }
        var title = WindowTitle(hwnd);
        return title.Contains("豆包", StringComparison.OrdinalIgnoreCase)
            || title.Contains("Doubao", StringComparison.OrdinalIgnoreCase);
    }

    private async Task<string?> ClickAndReadAsync(int x, int y, string prompt)
    {
        var sentinel = $"lecture-copilot-copy-{Guid.NewGuid():N}";
        await ClipboardService.SetTextAsync(sentinel);
        InputSimulator.Click(x, y);
        var copied = await ClipboardService.WaitForChangedTextAsync(sentinel, TimeSpan.FromMilliseconds(320));
        if (IsUsable(copied, prompt)) return copied!.Trim();
        InputSimulator.Click(x, y);
        copied = await ClipboardService.WaitForChangedTextAsync(sentinel, TimeSpan.FromMilliseconds(360));
        return IsUsable(copied, prompt) ? copied!.Trim() : null;
    }

    private static bool IsUsable(string? value, string prompt) => !string.IsNullOrWhiteSpace(value)
        && !string.Equals(value.Trim(), prompt.Trim(), StringComparison.Ordinal)
        && !value.StartsWith("lecture-copilot-copy-", StringComparison.Ordinal);

    private static AutomationElement? FindLatestCopyControl(IntPtr hwnd)
    {
        try
        {
            var root = AutomationElement.FromHandle(hwnd);
            var controls = root.FindAll(TreeScope.Descendants, Condition.TrueCondition)
                .Cast<AutomationElement>()
                .Select(e => new { Element = e, Info = SafeInfo(e) })
                .Where(x => x.Info.Rect.Width > 4 && x.Info.Rect.Height > 4)
                .ToList();

            var named = controls
                .Where(x => x.Info.Name.Contains("复制", StringComparison.OrdinalIgnoreCase)
                         || x.Info.Name.Contains("copy", StringComparison.OrdinalIgnoreCase)
                         || x.Info.Help.Contains("复制", StringComparison.OrdinalIgnoreCase)
                         || x.Info.Help.Contains("copy", StringComparison.OrdinalIgnoreCase))
                .OrderByDescending(x => x.Info.Rect.Bottom)
                .FirstOrDefault();
            if (named is not null) return named.Element;

            var smallButtons = controls
                .Where(x => x.Info.Type == ControlType.Button
                         && x.Info.Rect.Width is >= 10 and <= 70
                         && x.Info.Rect.Height is >= 10 and <= 70)
                .OrderByDescending(x => x.Info.Rect.Bottom)
                .ToList();
            foreach (var seed in smallButtons)
            {
                var row = smallButtons.Where(x => Math.Abs(x.Info.Rect.Top - seed.Info.Rect.Top) <= 8).ToList();
                if (row.Count >= 3) return row.OrderBy(x => x.Info.Rect.Left).First().Element;
            }
        }
        catch (Exception ex) { Logger.Write($"Find Copy UIA failed: {ex.Message}"); }
        return null;
    }

    private static (string Name, string Help, ControlType Type, System.Windows.Rect Rect) SafeInfo(AutomationElement element)
    {
        try { return (element.Current.Name ?? "", element.Current.HelpText ?? "", element.Current.ControlType, element.Current.BoundingRectangle); }
        catch { return ("", "", ControlType.Custom, System.Windows.Rect.Empty); }
    }

    private static void FocusComposer(IntPtr hwnd)
    {
        Activate(hwnd);
        try
        {
            var root = AutomationElement.FromHandle(hwnd);
            var window = root.Current.BoundingRectangle;
            var edits = root.FindAll(TreeScope.Descendants,
                    new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Edit))
                .Cast<AutomationElement>()
                .Where(e =>
                {
                    var r = e.Current.BoundingRectangle;
                    return e.Current.IsEnabled && !r.IsEmpty && r.Top > window.Top + window.Height * 0.55;
                })
                .OrderByDescending(e => e.Current.BoundingRectangle.Width * e.Current.BoundingRectangle.Height)
                .ToList();
            if (edits.FirstOrDefault() is { } edit)
            {
                edit.SetFocus();
                return;
            }
        }
        catch { }

        if (NativeMethods.GetWindowRect(hwnd, out var bounds))
            InputSimulator.Click(bounds.Left + (bounds.Right - bounds.Left) * 2 / 3, bounds.Bottom - 95);
    }

    private static void NewChat(IntPtr hwnd)
    {
        Activate(hwnd);
        try
        {
            var root = AutomationElement.FromHandle(hwnd);
            var all = root.FindAll(TreeScope.Descendants, Condition.TrueCondition).Cast<AutomationElement>();
            var button = all.FirstOrDefault(e =>
            {
                try
                {
                    var name = e.Current.Name ?? "";
                    return (name.Contains("新对话", StringComparison.OrdinalIgnoreCase)
                            || name.Contains("新建对话", StringComparison.OrdinalIgnoreCase)
                            || name.Contains("New Chat", StringComparison.OrdinalIgnoreCase)
                            || name.Contains("New Conversation", StringComparison.OrdinalIgnoreCase))
                           && e.Current.IsEnabled;
                }
                catch { return false; }
            });
            if (button is not null && button.TryGetCurrentPattern(InvokePattern.Pattern, out var pattern))
            {
                ((InvokePattern)pattern).Invoke();
                return;
            }
        }
        catch { }
        InputSimulator.Chord(NativeMethods.VkControl, NativeMethods.VkN);
    }

    private static void ScrollConversationToBottom(IntPtr hwnd)
    {
        try
        {
            var root = AutomationElement.FromHandle(hwnd);
            var scrollable = root.FindAll(TreeScope.Descendants, Condition.TrueCondition)
                .Cast<AutomationElement>()
                .Where(e =>
                {
                    try
                    {
                        return e.TryGetCurrentPattern(ScrollPattern.Pattern, out var value)
                               && ((ScrollPattern)value).Current.VerticallyScrollable;
                    }
                    catch { return false; }
                })
                .OrderByDescending(e =>
                {
                    var r = e.Current.BoundingRectangle;
                    return r.Width * r.Height;
                })
                .FirstOrDefault();
            if (scrollable is not null
                && scrollable.TryGetCurrentPattern(ScrollPattern.Pattern, out var pattern))
            {
                ((ScrollPattern)pattern).SetScrollPercent(ScrollPattern.NoScroll, 100);
                return;
            }
        }
        catch { }

        if (NativeMethods.GetWindowRect(hwnd, out var bounds))
        {
            InputSimulator.Click(bounds.Left + (bounds.Right - bounds.Left) / 2,
                bounds.Top + (bounds.Bottom - bounds.Top) / 2);
            InputSimulator.Chord(NativeMethods.VkControl, NativeMethods.VkEnd);
        }
    }

    private static void HoverLatestResponse(IntPtr hwnd)
    {
        try
        {
            var root = AutomationElement.FromHandle(hwnd);
            var window = root.Current.BoundingRectangle;
            var latest = root.FindAll(TreeScope.Descendants, Condition.TrueCondition)
                .Cast<AutomationElement>()
                .Where(e =>
                {
                    try
                    {
                        var r = e.Current.BoundingRectangle;
                        return !r.IsEmpty && r.Height >= 14 && r.Top > window.Top + window.Height * 0.25
                            && r.Bottom < window.Bottom - 90
                            && e.Current.ControlType is not null
                            && (e.Current.ControlType == ControlType.Text || e.Current.ControlType == ControlType.Document);
                    }
                    catch { return false; }
                })
                .OrderByDescending(e => e.Current.BoundingRectangle.Bottom)
                .FirstOrDefault();
            if (latest is not null)
            {
                var r = latest.Current.BoundingRectangle;
                NativeMethods.SetCursorPos((int)Math.Min(r.Right - 4, r.Left + 30), (int)Math.Max(r.Top + 4, r.Bottom - 8));
                return;
            }
        }
        catch { }

        if (NativeMethods.GetWindowRect(hwnd, out var bounds))
            NativeMethods.SetCursorPos(bounds.Left + (bounds.Right - bounds.Left) / 3, bounds.Bottom - 220);
    }

    private static void Activate(IntPtr hwnd)
    {
        NativeMethods.ShowWindow(hwnd, NativeMethods.SwRestore);
        NativeMethods.SetForegroundWindow(hwnd);
    }

    private static IntPtr FindWindow()
    {
        var result = IntPtr.Zero;
        NativeMethods.EnumWindows((hwnd, _) =>
        {
            if (!NativeMethods.IsWindowVisible(hwnd) || !IsDoubaoWindow(hwnd)) return true;
            result = hwnd;
            return false;
        }, IntPtr.Zero);
        return result;
    }

    private static string WindowTitle(IntPtr hwnd)
    {
        var buffer = new StringBuilder(512);
        NativeMethods.GetWindowText(hwnd, buffer, buffer.Capacity);
        return buffer.ToString();
    }

    private static void StartDoubao()
    {
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        var candidates = new[]
        {
            Path.Combine(local, "Programs", "Doubao", "Doubao.exe"),
            Path.Combine(local, "Doubao", "Doubao.exe"),
            Path.Combine(programFiles, "Doubao", "Doubao.exe")
        };
        foreach (var candidate in candidates.Where(File.Exists))
        {
            Process.Start(new ProcessStartInfo(candidate) { UseShellExecute = true });
            return;
        }
        try { Process.Start(new ProcessStartInfo("doubao") { UseShellExecute = true }); } catch { }
    }
}
