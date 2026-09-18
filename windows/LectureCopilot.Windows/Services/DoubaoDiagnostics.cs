using System.Text;
using System.Windows.Automation;

namespace LectureCopilot.Windows.Services;

internal static class DoubaoDiagnostics
{
    public static int RunUploadMenu()
    {
        try
        {
            return Task.Run(async () =>
            {
                var doubao = new DoubaoService();
                if (!await doubao.EnsureRunningAsync(true)) return 22;
                var hwnd = doubao.ChatWindowHandle();
                var root = DoubaoUia.Root(hwnd);
                if (root is null) return 23;
                DoubaoService.NewChat(hwnd);
                await Task.Delay(1800);
                hwnd = doubao.ChatWindowHandle();
                root = DoubaoUia.Root(hwnd);
                if (root is null) return 24;
                var layout = DoubaoUia.Layout(root);
                if (layout is null) return 26;
                var composer = DoubaoUia.Composer(root);
                var upload = composer?.FindAll(TreeScope.Descendants,
                    new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Button))
                    .Cast<AutomationElement>()
                    .OrderBy(e => e.Current.BoundingRectangle.Left).FirstOrDefault();
                var parent = upload is null ? null : TreeWalker.ControlViewWalker.GetParent(upload);
                if (parent is null || !parent.TryGetCurrentPattern(InvokePattern.Pattern, out var menuAction)) return 28;
                ((InvokePattern)menuAction).Invoke();
                await Task.Delay(250);
                var menuItem = root.FindFirst(TreeScope.Descendants,
                    new PropertyCondition(AutomationElement.NameProperty, "上传文件或图片"));
                if (menuItem is null || !menuItem.TryGetCurrentPattern(InvokePattern.Pattern, out var uploadAction)) return 29;
                ((InvokePattern)uploadAction).Invoke();
                await Task.Delay(800);
                root = DoubaoUia.Root(hwnd);
                if (root is null) return 27;
                using (var bitmap = ScreenPixels.Capture(root.Current.BoundingRectangle))
                    bitmap?.Save(Path.Combine(AppPaths.SupportDirectory, "doubao-upload-menu.png"));
                var hits = DoubaoUia.Snapshot(root);
                var output = Path.Combine(AppPaths.SupportDirectory, "new-chat-diagnostic.txt");
                File.WriteAllLines(output, hits.Select(hit =>
                    $"{hit.Type.ProgrammaticName} name='{hit.Name}' id='{hit.Id}' class='{hit.ClassName}' rect={hit.Rect}"));
                var windows = AutomationElement.RootElement.FindAll(TreeScope.Children, Condition.TrueCondition)
                    .Cast<AutomationElement>()
                    .SelectMany(window => new[] { window }.Concat(window.FindAll(TreeScope.Descendants,
                        new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Edit)).Cast<AutomationElement>()))
                    .Select(element => $"{element.Current.ControlType.ProgrammaticName} name='{element.Current.Name}' id='{element.Current.AutomationId}' hwnd={element.Current.NativeWindowHandle} rect={element.Current.BoundingRectangle}");
                File.WriteAllLines(Path.Combine(AppPaths.SupportDirectory, "upload-dialog.txt"), windows);
                return 0;
            }).GetAwaiter().GetResult();
        }
        catch (Exception ex) { Logger.Write($"Upload menu diagnose failed: {ex}"); return 25; }
    }

    public static int Run()
    {
        try
        {
            AppPaths.EnsureDirectories();
            var output = Path.Combine(AppPaths.SupportDirectory, "diagnose-doubao.txt");
            var text = Build();
            File.WriteAllText(output, text, Encoding.UTF8);
            Logger.Write($"Wrote Doubao diagnose dump to {output}");
            try { ForegroundWindowService.OpenPath(output); } catch { }
            return 0;
        }
        catch (Exception ex)
        {
            Logger.Write($"diagnose-doubao failed: {ex}");
            return 21;
        }
    }

    public static string WriteAndPath()
    {
        AppPaths.EnsureDirectories();
        var output = Path.Combine(AppPaths.SupportDirectory, "diagnose-doubao.txt");
        File.WriteAllText(output, Build(), Encoding.UTF8);
        return output;
    }

    private static string Build()
    {
        var builder = new StringBuilder();
        builder.AppendLine($"Lecture Copilot diagnose {DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss}");
        builder.AppendLine($"DPI awareness: {NativeMethods.DpiAwarenessLabel()}");
        var screen = System.Windows.Forms.SystemInformation.VirtualScreen;
        builder.AppendLine($"VirtualScreen: {screen.Left},{screen.Top} {screen.Width}x{screen.Height}");
        builder.AppendLine($"Clipboard image: {(ClipboardService.HasImage() ? "yes" : "no")}");
        builder.AppendLine($"Clipboard sequence: {NativeMethods.GetClipboardSequenceNumber()}");
        builder.AppendLine($"last-capture: {(File.Exists(AppPaths.LastCapture) ? new FileInfo(AppPaths.LastCapture).Length + " bytes" : "missing")}");
        builder.AppendLine($"last-answer: {(File.Exists(AppPaths.LastAnswer) ? new FileInfo(AppPaths.LastAnswer).Length + " bytes" : "missing")}");
        builder.AppendLine();

        var doubao = new DoubaoService();
        var hwnd = doubao.ChatWindowHandle();
        builder.AppendLine($"Doubao HWND: 0x{hwnd.ToInt64():X}");
        if (hwnd == IntPtr.Zero)
        {
            builder.AppendLine("Doubao chat window was not found.");
            return builder.ToString();
        }

        NativeMethods.GetWindowRect(hwnd, out var wr);
        builder.AppendLine($"Window rect: {wr.Left},{wr.Top} {wr.Right - wr.Left}x{wr.Bottom - wr.Top}");
        var root = DoubaoUia.Root(hwnd);
        if (root is null)
        {
            builder.AppendLine("UIA root unavailable.");
            return builder.ToString();
        }

        var layout = DoubaoUia.Layout(root);
        builder.AppendLine($"Input found: {(layout is null ? "no" : "yes")}");
        if (layout is not null)
        {
            builder.AppendLine($"Input bounds: {layout.Composer}");
            builder.AppendLine($"Chat pane: L={layout.ChatLeft:0} R={layout.ChatRight:0} T={layout.ChatTop:0} B={layout.ChatBottom:0}");
        }

        var hits = DoubaoUia.Snapshot(root);
        var textPattern = hits.Count(h => h.TextPattern);
        var valuePattern = hits.Count(h => h.ValuePattern);
        builder.AppendLine($"UIA nodes: {hits.Count}");
        builder.AppendLine($"TextPattern available: {(textPattern > 0 ? "yes" : "no")} ({textPattern})");
        builder.AppendLine($"ValuePattern available: {(valuePattern > 0 ? "yes" : "no")} ({valuePattern})");

        var chatText = layout is null ? "" : DoubaoUia.CollectChatText(hits, layout);
        builder.AppendLine($"Latest chat text chars: {chatText.Length}");
        var latest = layout is null ? null : DoubaoUia.LatestAnswer(hits, layout, "");
        builder.AppendLine($"Latest answer found: {(latest is null ? "no" : "yes")}");
        if (latest is not null)
        {
            var sample = DoubaoUia.ReadText(latest);
            builder.AppendLine($"Latest answer type={latest.Type.ProgrammaticName} name='{latest.Name}' id='{latest.Id}' rect={latest.Rect}");
            builder.AppendLine($"Latest answer preview: {Preview(sample)}");
            builder.AppendLine();
            builder.AppendLine("Buttons near latest answer:");
            var buttons = DoubaoUia.ToolbarButtons(hits, latest.Rect, layout!);
            if (buttons.Count == 0) builder.AppendLine("(none)");
            for (var i = 0; i < buttons.Count; i++)
            {
                var b = buttons[i];
                builder.AppendLine($"#{i + 1} Type={b.Type.ProgrammaticName} Name=\"{b.Name}\" AutomationId=\"{b.Id}\" Class={b.ClassName} Invoke={b.Invoke} Rect={b.Rect} Patterns={DoubaoUia.Patterns(b)}");
            }
        }

        builder.AppendLine();
        builder.AppendLine("=== Chat-region UIA (interesting) ===");
        if (layout is not null)
        {
            foreach (var hit in hits.Where(h => DoubaoUia.InChat(h.Rect, layout)
                                                && (h.TextPattern || h.ValuePattern || h.Invoke
                                                    || h.Type == ControlType.Text || h.Type == ControlType.Document
                                                    || h.Type == ControlType.Edit || h.Type == ControlType.Button
                                                    || (!string.IsNullOrWhiteSpace(h.Name) && h.Name.Length > 8)))
                         .OrderBy(h => h.Rect.Top)
                         .Take(80))
            {
                var text = DoubaoUia.ReadText(hit);
                builder.AppendLine($"{hit.Type.ProgrammaticName} name=\"{hit.Name}\" id=\"{hit.Id}\" class=\"{hit.ClassName}\" patterns={DoubaoUia.Patterns(hit)} rect={hit.Rect} text={Preview(text)}");
            }
        }

        builder.AppendLine();
        builder.AppendLine("=== Composer descendants ===");
        if (layout is not null)
        {
            foreach (var hit in hits.Where(h => Overlaps(h.Rect, layout.Composer)).Take(40))
                builder.AppendLine($"{hit.Type.ProgrammaticName} name=\"{hit.Name}\" id=\"{hit.Id}\" class=\"{hit.ClassName}\" patterns={DoubaoUia.Patterns(hit)} rect={hit.Rect}");
        }

        return builder.ToString();
    }

    private static string Preview(string text)
    {
        var compact = AnswerTextCleaner.Normalize(text).Replace('\n', ' ');
        return compact.Length <= 160 ? compact : compact[..160] + "…";
    }

    private static bool Overlaps(System.Windows.Rect a, System.Windows.Rect b) =>
        a.Left < b.Right && a.Right > b.Left && a.Top < b.Bottom && a.Bottom > b.Top;
}
