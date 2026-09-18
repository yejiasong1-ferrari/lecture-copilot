using System.Diagnostics;
using System.Text;
using System.Windows.Automation;

namespace LectureCopilot.Windows.Services;

public sealed record DoubaoResult(bool Success, string Message);

public sealed class DoubaoService
{
    private static readonly string[] ProcessHints = ["doubao", "doubaobrowser"];
    private string? _chatBaseline;
    private int _completionBaselineCount;
    private int _completionBaselineChars;
    private readonly DoubaoAnswerReader _answers = new();

    public bool IsRunning => FindWindow() != IntPtr.Zero;
    public IntPtr ChatWindowHandle() => FindWindow();

    public void ForceForeground()
    {
        var hwnd = FindWindow();
        if (hwnd == IntPtr.Zero) return;
        Activate(hwnd, true);
    }

    public bool IsProcessAlive
    {
        get
        {
            foreach (var name in ProcessHints)
            {
                try { if (Process.GetProcessesByName(name).Length > 0) return true; } catch { }
            }
            return false;
        }
    }

    public async Task<bool> EnsureRunningAsync(bool activate)
    {
        var hwnd = FindWindow();
        if (hwnd == IntPtr.Zero)
        {
            for (var i = 0; i < 8 && hwnd == IntPtr.Zero; i++)
            {
                await Task.Delay(80);
                hwnd = FindWindow();
            }
        }
        if (hwnd == IntPtr.Zero)
        {
            if (IsProcessAlive)
            {
                Logger.Write("Doubao is running in the background; restoring the chat window");
                RestoreHiddenDoubaoWindows();
            }
            else Logger.Write("Doubao is not running; launching client");
            StartDoubao();

            for (var i = 0; i < 120 && hwnd == IntPtr.Zero; i++)
            {
                await Task.Delay(100);
                hwnd = FindWindow();
            }
        }
        if (hwnd == IntPtr.Zero)
        {
            Logger.Write("Doubao chat window was not found");
            return false;
        }
        if (activate) await ActivateUntilForegroundAsync(hwnd);
        return true;
    }

    private async Task<bool> ActivateUntilForegroundAsync(IntPtr hwnd)
    {
        if (NativeMethods.GetForegroundWindow() == hwnd) return true;
        for (var i = 0; i < 12; i++)
        {
            Activate(hwnd, true);
            await Task.Delay(60);
            if (IsForegroundDoubao()) return true;
        }
        Logger.Write($"Could not keep Doubao in the foreground; now={ForegroundName()}");
        return false;
    }

    public async Task<DoubaoResult> SendImageAndPromptAsync(string prompt, Action? onSubmitted = null)
    {
        if (!await EnsureRunningAsync(true)) return new(false, "豆包没有在运行。请先安装并登录豆包 Windows 客户端。");
        var hwnd = FindWindow();
        if (hwnd == IntPtr.Zero) return new(false, "找不到豆包主窗口。请把豆包聊天窗口显示出来后再试。");
        if (!await ActivateUntilForegroundAsync(hwnd))
        {
            ReleaseTopMost(hwnd);
            return new(false, "无法把豆包切到前台。请先手动点一下豆包窗口，再按一次快捷键。");
        }
        try
        {
            EnsureOnScreen(hwnd);
            NewChat(hwnd);
            if (!await WaitForComposerAsync(hwnd))
                return new(false, "找不到豆包输入框。请先点一下豆包聊天输入框再试。");
            if (!IsForegroundDoubao()) Activate(hwnd, true);
            DismissPopups();
            FocusComposer(hwnd);
            await Task.Delay(120);
            var completion = DoubaoAnswerCompletion.Baseline(hwnd);
            _chatBaseline = completion.Text;
            _completionBaselineCount = completion.Elapsed;
            _completionBaselineChars = completion.Chars;
            if (File.Exists(AppPaths.LastCapture))
            {
                try { await ClipboardService.SetPngFileAsync(AppPaths.LastCapture); }
                catch (Exception ex) { return new(false, $"截图还在剪贴板里被占用：{ex.Message}"); }
            }
            if (!ClipboardService.HasImage())
                return new(false, "剪贴板里没有截图，没法发给豆包。");
            var pasted = await PasteImageConfirmedAsync(hwnd);
            if (!pasted) return new(false, "截图没有出现在豆包输入框。请点一下输入框后再试一次。");
            try { await ClipboardService.SetTextAsync(prompt); }
            catch (Exception ex) { return new(false, $"无法写入 prompt：{ex.Message}"); }
            if (!IsForegroundDoubao()) Activate(hwnd, true);
            FocusComposer(hwnd, dismissPopups: false);
            await Task.Delay(80);
            if (!InputSimulator.Chord(NativeMethods.VkControl, NativeMethods.VkV))
                return new(false, "无法向豆包输入提示词。请确认豆包与 Lecture Copilot 使用相同的运行权限。");
            await WaitForPromptPasteAsync(hwnd, prompt);
            if (!await SubmitComposerAsync(hwnd))
                return new(false, "没有确认豆包收到消息。请检查豆包输入框中的图片和文字，再手动点发送。");
            ReleaseTopMost(hwnd);
            onSubmitted?.Invoke();
            Logger.Write("Screenshot and prompt verified in Doubao chat");
            return new(true, "");
        }
        finally { ReleaseTopMost(hwnd); }
    }

    public async Task<DoubaoResult> SendTextAsync(string text, Action? onSubmitted = null)
    {
        if (!await EnsureRunningAsync(true)) return new(false, "豆包没有在运行。请先安装并登录豆包 Windows 客户端。");
        var hwnd = FindWindow();
        if (hwnd == IntPtr.Zero) return new(false, "找不到豆包主窗口。请把豆包聊天窗口显示出来后再试。");
        try
        {
            Activate(hwnd);
            await Task.Delay(280);
            NewChat(hwnd);
            await Task.Delay(300);
            var completion = DoubaoAnswerCompletion.Baseline(hwnd);
            _chatBaseline = completion.Text;
            _completionBaselineCount = completion.Elapsed;
            _completionBaselineChars = completion.Chars;
            try { await ClipboardService.SetTextAsync(text); }
            catch (Exception ex) { return new(false, $"无法写入文字：{ex.Message}"); }
            FocusComposer(hwnd);
            await Task.Delay(120);
            if (!InputSimulator.Chord(NativeMethods.VkControl, NativeMethods.VkV))
                return new(false, "无法向豆包输入课堂总结。请确认两个程序使用相同的运行权限。");
            await WaitForPromptPasteAsync(hwnd, text);
            if (!await SubmitComposerAsync(hwnd))
                return new(false, "没有确认豆包收到课堂总结。请检查豆包输入框，再手动点发送。");
            ReleaseTopMost(hwnd);
            onSubmitted?.Invoke();
            Logger.Write("Class summary prompt verified in Doubao chat");
            return new(true, "");
        }
        finally { ReleaseTopMost(hwnd); }
    }

    private static async Task WaitForPromptPasteAsync(IntPtr hwnd, string prompt)
    {
        var elapsed = Stopwatch.StartNew();
        var budget = prompt.Length > 600 ? 800 : 350;
        var expected = prompt.Replace("\r\n", "\n").Trim();
        while (elapsed.ElapsedMilliseconds < budget)
        {
            await Task.Delay(50);
            var root = DoubaoUia.Root(hwnd);
            var editor = root is null ? null : DoubaoUia.ProseMirror(root);
            if (editor is null) continue;
            var actual = DoubaoUia.ReadPatterns(editor).Replace("\r\n", "\n");
            if (actual.Contains(expected, StringComparison.Ordinal))
            {
                Logger.Write($"Prompt paste ready after {elapsed.ElapsedMilliseconds} ms");
                return;
            }
        }
    }

    private async Task<bool> SubmitComposerAsync(IntPtr hwnd)
    {
        var before = CaptureSendBaseline(hwnd);
        if (!IsForegroundDoubao()) Activate(hwnd, true);
        if (!InputSimulator.Press(NativeMethods.VkReturn))
        {
            Logger.Write("Send key injection failed");
            return false;
        }
        if (await ConfirmSentAsync(hwnd, before)) return true;

        Logger.Write("Return did not clear composer; clicking send button");
        if (!IsForegroundDoubao()) Activate(hwnd, true);
        FocusComposer(hwnd, dismissPopups: false);
        await Task.Delay(80);
        ClickSend(hwnd);
        await Task.Delay(80);
        InputSimulator.Press(NativeMethods.VkReturn);
        return await ConfirmSentAsync(hwnd, before);
    }

    private static (ulong? Composer, ulong? Chat) CaptureSendBaseline(IntPtr hwnd)
    {
        var root = DoubaoUia.Root(hwnd);
        var layout = root is null ? null : DoubaoUia.Layout(root);
        if (layout is null) return (null, null);
        var chat = new System.Windows.Rect(layout.ChatLeft, layout.ChatTop,
            Math.Max(40, layout.ChatRight - layout.ChatLeft),
            Math.Max(40, layout.ChatBottom - layout.ChatTop));
        return (HashRect(layout.Composer), HashRect(chat));
    }

    private static async Task<bool> ConfirmSentAsync(IntPtr hwnd, (ulong? Composer, ulong? Chat) before)
    {
        for (var attempt = 0; attempt < 10; attempt++)
        {
            await Task.Delay(120);
            var root = DoubaoUia.Root(hwnd);
            if (root is null) continue;
            if (DoubaoUia.ComposerLooksEmpty(root))
            {
                Logger.Write("Send confirmed by empty composer");
                return true;
            }
            var layout = DoubaoUia.Layout(root);
            if (layout is null) continue;
            var composerHash = HashRect(layout.Composer);
            if (before.Composer is not null && composerHash is not null
                && ScreenPixels.Hamming(before.Composer.Value, composerHash.Value) >= 8)
            {
                Logger.Write("Send confirmed by composer visual change");
                return true;
            }
            var chat = new System.Windows.Rect(layout.ChatLeft, layout.ChatTop,
                Math.Max(40, layout.ChatRight - layout.ChatLeft),
                Math.Max(40, layout.ChatBottom - layout.ChatTop));
            var chatHash = HashRect(chat);
            if (before.Chat is not null && chatHash is not null
                && ScreenPixels.Hamming(before.Chat.Value, chatHash.Value) >= 5)
            {
                Logger.Write("Send confirmed by chat visual change");
                return true;
            }
        }
        Logger.Write("Doubao send not verified; composer still looks occupied");
        return false;
    }

    private static ulong? HashRect(System.Windows.Rect rect)
    {
        if (rect.IsEmpty || rect.Width < 8 || rect.Height < 8) return null;
        using var shot = ScreenPixels.Capture(rect);
        return shot is null ? null : ScreenPixels.Hash(shot);
    }

    private static void ClickSend(IntPtr hwnd)
    {
        try
        {
            var root = DoubaoUia.Root(hwnd);
            var send = root is null ? null : DoubaoUia.SendControl(root);
            if (send is not null)
            {
                if (send.TryGetCurrentPattern(InvokePattern.Pattern, out var invoke))
                {
                    ((InvokePattern)invoke).Invoke();
                    Logger.Write("Invoked Doubao send control");
                    return;
                }
                ClickElement(send);
                Logger.Write("Clicked Doubao send control");
                return;
            }
        }
        catch (Exception ex) { Logger.Write($"Click send UIA failed: {ex.Message}"); }

        if (NativeMethods.GetWindowRect(hwnd, out var bounds))
        {
            var x = bounds.Right - 48;
            var y = bounds.Bottom - 48;
            InputSimulator.Click(x, y);
            Logger.Write($"Clicked Doubao send fallback ({x},{y})");
        }
    }

    private static void EnsureOnScreen(IntPtr hwnd)
    {
        if (!NativeMethods.GetWindowRect(hwnd, out var rect)) return;
        var screen = System.Windows.Forms.SystemInformation.VirtualScreen;
        var overflowRight = rect.Right - (screen.Left + screen.Width);
        var overflowBottom = rect.Bottom - (screen.Top + screen.Height);
        if (overflowRight <= 48 && overflowBottom <= 48
            && rect.Left >= screen.Left - 48 && rect.Top >= screen.Top - 48)
            return;
        NativeMethods.ShowWindow(hwnd, NativeMethods.SwMaximize);
        Logger.Write($"Maximized Doubao so the send button stays on screen overflowR={overflowRight} overflowB={overflowBottom}");
        Thread.Sleep(220);
    }

    private async Task<bool> PasteImageConfirmedAsync(IntPtr hwnd)
    {
        if (!ClipboardService.HasImage() && File.Exists(AppPaths.LastCapture))
        {
            try { await ClipboardService.SetPngFileAsync(AppPaths.LastCapture); }
            catch (Exception ex)
            {
                Logger.Write($"Paste confirm clipboard failed: {ex.Message}");
                return false;
            }
        }
        if (!ClipboardService.HasImage()) return false;

        for (var attempt = 0; attempt < 3; attempt++)
        {
            if (attempt > 0)
            {
                Logger.Write($"Retrying image paste attempt={attempt + 1}");
                DismissPopups();
                try { await ClipboardService.SetPngFileAsync(AppPaths.LastCapture); }
                catch (Exception ex) { Logger.Write($"Paste retry clipboard failed: {ex.Message}"); return false; }
            }

            var root = DoubaoUia.Root(hwnd);
            var layout = root is null ? null : DoubaoUia.Layout(root);
            var beforeHeight = ProseMirrorHeight(root);
            var beforePlaceholder = layout is not null && root is not null
                && DoubaoUia.HasPlaceholder(DoubaoUia.Snapshot(root), layout);
            ulong? beforeHash = HashComposerTextBand(layout);

            if (!IsForegroundDoubao()) Activate(hwnd, true);
            DismissPopups();
            FocusComposer(hwnd);
            await Task.Delay(90);
            if (!IsForegroundDoubao() || !InputSimulator.Chord(NativeMethods.VkControl, NativeMethods.VkV))
            {
                Logger.Write($"Image paste key injection failed; foreground={ForegroundName()}");
                continue;
            }

            for (var check = 0; check < 8; check++)
            {
                await Task.Delay(120);
                root = DoubaoUia.Root(hwnd);
                if (root is null) continue;
                layout = DoubaoUia.Layout(root);
                if (layout is null) continue;
                var hits = DoubaoUia.Snapshot(root);
                var attachments = DoubaoUia.AttachmentCount(hits, layout);
                if (attachments > 0)
                {
                    Logger.Write($"Paste confirmed by UIA attachment ({attachments}), attempt={attempt + 1}");
                    return true;
                }
                var afterHeight = ProseMirrorHeight(root);
                if (beforeHeight > 0 && afterHeight >= beforeHeight + 8)
                {
                    Logger.Write($"Paste confirmed by editor growth ({beforeHeight} -> {afterHeight})");
                    return true;
                }
                if (beforePlaceholder && !DoubaoUia.HasPlaceholder(hits, layout))
                {
                    Logger.Write("Paste confirmed by placeholder disappearing");
                    return true;
                }
                var afterHash = HashComposerTextBand(layout);
                if (beforeHash is not null && afterHash is not null
                    && ScreenPixels.Hamming(beforeHash.Value, afterHash.Value) >= 4)
                {
                    Logger.Write("Paste confirmed by composer visual change");
                    return true;
                }
            }
        }
        Logger.Write($"Paste not confirmed; foreground={ForegroundName()} clipboardImage={ClipboardService.HasImage()}");
        return false;
    }

    private static ulong? HashComposerTextBand(DoubaoLayout? layout)
    {
        if (layout is null) return null;
        var band = new System.Windows.Rect(
            layout.Composer.Left + 80,
            layout.Composer.Top + 4,
            Math.Max(40, layout.Composer.Width - 160),
            Math.Max(28, Math.Min(72, layout.Composer.Height * 0.45)));
        using var shot = ScreenPixels.Capture(band);
        return shot is null ? null : ScreenPixels.Hash(shot);
    }

    private static int ProseMirrorHeight(AutomationElement? root)
    {
        if (root is null) return 0;
        try
        {
            var editor = DoubaoUia.ProseMirror(root);
            var rect = editor?.Current.BoundingRectangle ?? default;
            return rect.IsEmpty ? 0 : (int)rect.Height;
        }
        catch { return 0; }
    }

    private static async Task<bool> WaitForComposerAsync(IntPtr hwnd)
    {
        for (var i = 0; i < 40; i++)
        {
            var root = DoubaoUia.Root(hwnd);
            if (root is not null && (DoubaoUia.ProseMirror(root) is not null || DoubaoUia.Composer(root) is not null))
                return true;
            await Task.Delay(80);
        }
        var last = DoubaoUia.Root(hwnd);
        return last is not null && DoubaoUia.Composer(last) is not null;
    }

    private static void DismissPopups()
    {
        InputSimulator.Press(NativeMethods.VkEscape);
        Thread.Sleep(40);
        InputSimulator.Press(NativeMethods.VkEscape);
    }

    private static void FocusComposer(IntPtr hwnd, bool dismissPopups = true)
    {
        Activate(hwnd);
        if (dismissPopups) DismissPopups();
        try
        {
            var root = AutomationElement.FromHandle(hwnd);
            var editor = DoubaoUia.ProseMirror(root);
            if (editor is not null)
            {
                var rect = editor.Current.BoundingRectangle;
                if (!rect.IsEmpty)
                {
                    try { editor.SetFocus(); } catch { }
                    InputSimulator.Click(
                        (int)(rect.Left + Math.Min(220, rect.Width * 0.35)),
                        (int)(rect.Top + Math.Max(8, rect.Height / 2)));
                    Logger.Write($"Focused Doubao ProseMirror ({rect.Left:0},{rect.Top:0} {rect.Width:0}x{rect.Height:0})");
                    return;
                }
            }

            var composer = DoubaoUia.Composer(root);
            if (composer is not null)
            {
                var rect = composer.Current.BoundingRectangle;
                if (!rect.IsEmpty && rect.Width > 200 && rect.Height > 40)
                {
                    var x = (int)(rect.Left + Math.Max(90, rect.Width * 0.28));
                    var y = (int)(rect.Top + Math.Min(28, rect.Height * 0.22));
                    InputSimulator.Click(x, y);
                    Logger.Write($"Clicked Doubao composer text area ({x},{y})");
                    return;
                }
            }
        }
        catch (Exception ex) { Logger.Write($"Focus composer UIA failed: {ex.Message}"); }

        if (NativeMethods.GetWindowRect(hwnd, out var bounds))
        {
            var x = bounds.Left + (bounds.Right - bounds.Left) / 2;
            var y = bounds.Bottom - 220;
            InputSimulator.Click(x, y);
            Logger.Write($"Clicked Doubao composer fallback ({x},{y})");
        }
    }

    public async Task<string?> CopyLatestAnswerAsync(string prompt)
    {
        var hwnd = FindWindow();
        if (hwnd == IntPtr.Zero)
        {
            if (!await EnsureRunningAsync(false)) return null;
            hwnd = FindWindow();
        }
        if (hwnd == IntPtr.Zero) return null;
        try
        {
            if (DoubaoAnswerCompletion.IsGenerating(hwnd))
            {
                Logger.Write("Doubao answer is still generating; read postponed");
                return null;
            }
            if (!await ActivateUntilForegroundAsync(hwnd)) return null;
            ScrollConversationToBottom(hwnd);
            var result = await _answers.ReadAsync(hwnd, prompt, _chatBaseline, null);
            if (string.IsNullOrWhiteSpace(result.Text)
                || result.Source is not ("uia-copy" or "cv-copy" or "cv-copy-cached"))
            {
                Logger.Write($"Copy unavailable; source={result.Source}");
                return null;
            }
            Logger.Write($"Read answer source={result.Source} chars={result.Text?.Length ?? 0}");
            return result.Text;
        }
        finally { ReleaseTopMost(hwnd); }
    }

    public string InspectTree() => DoubaoDiagnostics.WriteAndPath();

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
        return false;
    }

    private static AutomationElement? FindComposerEdit(AutomationElement root)
    {
        try
        {
            var byId = root.FindFirst(TreeScope.Descendants,
                new PropertyCondition(AutomationElement.AutomationIdProperty, "input-engine-container"));
            if (byId is not null)
            {
                var nested = byId.FindFirst(TreeScope.Descendants,
                    new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Edit));
                if (nested is not null) return nested;
            }
        }
        catch { }

        try
        {
            var window = root.Current.BoundingRectangle;
            return root.FindAll(TreeScope.Descendants,
                    new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Edit))
                .Cast<AutomationElement>()
                .Where(e =>
                {
                    var r = e.Current.BoundingRectangle;
                    return e.Current.IsEnabled && !r.IsEmpty && r.Width > 200
                           && r.Top > window.Top + window.Height * 0.45;
                })
                .OrderByDescending(e => e.Current.BoundingRectangle.Width)
                .FirstOrDefault();
        }
        catch { return null; }
    }

    internal static void NewChat(IntPtr hwnd)
    {
        Activate(hwnd);
        try
        {
            var root = AutomationElement.FromHandle(hwnd);
            var all = root.FindAll(TreeScope.Descendants, Condition.TrueCondition).Cast<AutomationElement>();
            var newChat = all.FirstOrDefault(e =>
            {
                try
                {
                    var name = e.Current.Name ?? "";
                    var id = e.Current.AutomationId ?? "";
                    if (id.StartsWith("conversation_", StringComparison.Ordinal)) return false;
                    return name is "新对话" or "开启新对话" or "新建对话";
                }
                catch { return false; }
            });
            if (newChat is not null)
            {
                var parent = TreeWalker.ControlViewWalker.GetParent(newChat);
                if (parent is not null && parent.TryGetCurrentPattern(InvokePattern.Pattern, out var action))
                {
                    ((InvokePattern)action).Invoke();
                    Logger.Write("Invoked Doubao new-chat navigation item");
                }
                else
                {
                    ClickElement(newChat);
                    Logger.Write("Clicked Doubao new-chat navigation item");
                }
                return;
            }
        }
        catch (Exception ex) { Logger.Write($"New chat UIA failed: {ex.Message}"); }

        Logger.Write("Sending Ctrl+N to start a Doubao chat");
        InputSimulator.Chord(NativeMethods.VkControl, NativeMethods.VkN);
    }

    private static void ClickElement(AutomationElement element)
    {
        var rect = element.Current.BoundingRectangle;
        if (rect.IsEmpty) return;
        InputSimulator.Click((int)(rect.Left + Math.Max(8, rect.Width / 2)),
            (int)(rect.Top + Math.Max(8, rect.Height / 2)));
    }

    private static void ScrollConversationToBottom(IntPtr hwnd)
    {
        var root = DoubaoUia.Root(hwnd);
        var layout = root is null ? null : DoubaoUia.Layout(root);
        try
        {
            var scrollable = root?.FindAll(TreeScope.Descendants,
                    new PropertyCondition(AutomationElement.IsScrollPatternAvailableProperty, true))
                .Cast<AutomationElement>()
                .Where(e =>
                {
                    try
                    {
                        var rect = e.Current.BoundingRectangle;
                        if (layout is not null && (rect.Left < layout.ChatLeft - 32
                            || rect.Right > layout.ChatRight + 32
                            || rect.Top >= layout.Composer.Top)) return false;
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
                Logger.Write("Scrolled Doubao chat with UIA");
            }
        }
        catch { }

        if (layout is not null)
        {
            InputSimulator.ScrollDown(
                (int)(layout.ChatLeft + (layout.ChatRight - layout.ChatLeft) * 0.48),
                (int)Math.Clamp(layout.Composer.Top - 170, layout.ChatTop + 80, layout.ChatBottom - 30), 20);
            Logger.Write("Scrolled Doubao chat to latest reply");
        }
    }

    private static void Activate(IntPtr hwnd, bool stayTopMost = true)
    {
        if (hwnd == IntPtr.Zero) return;
        NativeMethods.AllowSetForegroundWindow(NativeMethods.AsfwAny);
        if (NativeMethods.IsIconic(hwnd))
            NativeMethods.ShowWindow(hwnd, NativeMethods.SwRestore);
        NativeMethods.ShowWindow(hwnd, NativeMethods.SwShow);

        NativeMethods.keybd_event((byte)NativeMethods.VkMenu, 0, 0, UIntPtr.Zero);
        NativeMethods.keybd_event((byte)NativeMethods.VkMenu, 0, NativeMethods.KeyEventFKeyUp, UIntPtr.Zero);

        var current = NativeMethods.GetCurrentThreadId();
        var target = (uint)NativeMethods.GetWindowThreadProcessId(hwnd, out _);
        var foreground = NativeMethods.GetForegroundWindow();
        var foregroundThread = (uint)NativeMethods.GetWindowThreadProcessId(foreground, out _);
        var attached = foregroundThread != 0 && foregroundThread != current
            && NativeMethods.AttachThreadInput(current, foregroundThread, true);
        var attachedTarget = target != 0 && target != current
            && NativeMethods.AttachThreadInput(current, target, true);

        NativeMethods.BringWindowToTop(hwnd);
        NativeMethods.SwitchToThisWindow(hwnd, true);
        NativeMethods.SetWindowPos(hwnd, NativeMethods.HwndTopmost, 0, 0, 0, 0,
            NativeMethods.SwpNomove | NativeMethods.SwpNosize | NativeMethods.SwpShowWindow);
        NativeMethods.SetForegroundWindow(hwnd);
        if (!stayTopMost) ReleaseTopMost(hwnd);

        if (attachedTarget) NativeMethods.AttachThreadInput(current, target, false);
        if (attached) NativeMethods.AttachThreadInput(current, foregroundThread, false);

        Logger.Write($"Activated Doubao hwnd=0x{hwnd.ToInt64():X} foreground={ForegroundName()}");
    }

    private static void ReleaseTopMost(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return;
        NativeMethods.SetWindowPos(hwnd, NativeMethods.HwndNoTopmost, 0, 0, 0, 0,
            NativeMethods.SwpNomove | NativeMethods.SwpNosize | NativeMethods.SwpShowWindow);
    }

    private static bool IsForegroundDoubao() => IsDoubaoWindow(NativeMethods.GetForegroundWindow());

    private static string ForegroundName()
    {
        var hwnd = NativeMethods.GetForegroundWindow();
        NativeMethods.GetWindowThreadProcessId(hwnd, out var pid);
        try { return Process.GetProcessById((int)pid).ProcessName; }
        catch { return hwnd.ToString("X"); }
    }

    private static IntPtr FindWindow()
    {
        var best = IntPtr.Zero;
        var bestArea = 0;
        NativeMethods.EnumWindows((hwnd, _) =>
        {
            if (!NativeMethods.IsWindowVisible(hwnd) || !IsDoubaoWindow(hwnd)) return true;
            var ex = NativeMethods.GetWindowLongPtr(hwnd, NativeMethods.GwlExStyle).ToInt64();
            if ((ex & NativeMethods.WsExToolWindow) != 0) return true;
            if (!NativeMethods.GetWindowRect(hwnd, out var rect)) return true;
            var width = rect.Right - rect.Left;
            var height = rect.Bottom - rect.Top;
            if (width < 400 || height < 280) return true;
            var area = width * height;
            if (area <= bestArea) return true;
            bestArea = area;
            best = hwnd;
            return true;
        }, IntPtr.Zero);
        if (best != IntPtr.Zero)
            Logger.Write($"Found Doubao chat window hwnd=0x{best.ToInt64():X} area={bestArea} title='{WindowTitle(best)}'");
        return best;
    }

    private static string WindowTitle(IntPtr hwnd)
    {
        var buffer = new StringBuilder(512);
        NativeMethods.GetWindowText(hwnd, buffer, buffer.Capacity);
        return buffer.ToString();
    }

    private static string WindowClass(IntPtr hwnd)
    {
        var buffer = new StringBuilder(256);
        NativeMethods.GetClassName(hwnd, buffer, buffer.Capacity);
        return buffer.ToString();
    }

    private static void RestoreHiddenDoubaoWindows()
    {
        NativeMethods.EnumWindows((hwnd, _) =>
        {
            if (!IsDoubaoWindow(hwnd)) return true;
            NativeMethods.ShowWindow(hwnd, NativeMethods.SwRestore);
            NativeMethods.ShowWindow(hwnd, NativeMethods.SwShow);
            NativeMethods.BringWindowToTop(hwnd);
            return true;
        }, IntPtr.Zero);
    }

    private static void StartDoubao()
    {
        foreach (var candidate in DoubaoLaunchTargets().Where(File.Exists))
        {
            Logger.Write($"Launching Doubao from {candidate}");
            Process.Start(new ProcessStartInfo(candidate) { UseShellExecute = true });
            return;
        }
        try
        {
            Process.Start(new ProcessStartInfo("doubao") { UseShellExecute = true });
            Logger.Write("Launching Doubao by app name");
        }
        catch (Exception ex) { Logger.Write($"Failed to launch Doubao: {ex.Message}"); }
    }

    private static IEnumerable<string> DoubaoLaunchTargets()
    {
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var startMenu = Environment.GetFolderPath(Environment.SpecialFolder.StartMenu);
        var programs = Environment.GetFolderPath(Environment.SpecialFolder.Programs);
        return
        [
            Path.Combine(startMenu, "Programs", "豆包.lnk"),
            Path.Combine(programs, "豆包.lnk"),
            Path.Combine(local, "Doubao", "Application", "Doubao.exe"),
            Path.Combine(local, "Doubao", "Application", "app", "launcher", "Doubao.exe"),
            Path.Combine(local, "Doubao", "Application", "app", "Doubao.exe"),
            Path.Combine(local, "Programs", "Doubao", "Doubao.exe"),
            Path.Combine(local, "Doubao", "Doubao.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Doubao", "Doubao.exe")
        ];
    }
}
