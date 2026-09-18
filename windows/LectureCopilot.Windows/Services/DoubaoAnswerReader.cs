using System.Drawing;
using System.Drawing.Imaging;
using System.Windows.Automation;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using WinRect = System.Windows.Rect;

namespace LectureCopilot.Windows.Services;

internal sealed record AnswerRead(string? Text, string Source);

internal sealed class DoubaoAnswerReader
{
    private const double DefaultCopyXRatio = 0.210;
    private (double X, double Y)? _cachedCopyLocation;

    public static string SnapshotChatText(IntPtr hwnd)
    {
        var root = DoubaoUia.Root(hwnd);
        if (root is null) return "";
        var layout = DoubaoUia.Layout(root);
        if (layout is null) return "";
        return DoubaoUia.CollectChatText(DoubaoUia.Snapshot(root), layout);
    }

    public async Task<AnswerRead> ReadAsync(IntPtr hwnd, string prompt, string? baseline, Func<IntPtr, Task>? activate)
    {
        if (activate is not null) await activate(hwnd);
        var root = DoubaoUia.Root(hwnd);
        if (root is null) return new(null, "no-window");
        var layout = DoubaoUia.Layout(root);
        if (layout is null) return new(null, "no-layout");
        if (!NativeMethods.GetWindowRect(hwnd, out var window) || window.Right - window.Left < 200)
            return new(null, "no-window");

        HoverLatestAnswer(window);
        await Task.Delay(160);

        if (_cachedCopyLocation is { } cached)
        {
            var cachedPoint = (
                window.Left + (int)Math.Round((window.Right - window.Left) * cached.X),
                window.Top + (int)Math.Round((window.Bottom - window.Top) * cached.Y));
            var copied = await ClickCopyAsync(hwnd, cachedPoint.Item1, cachedPoint.Item2, prompt, "cached");
            if (copied is not null)
            {
                Logger.Write($"Answer via cached Copy ({copied.Length} chars)");
                return new(copied, "cv-copy-cached");
            }
            Logger.Write("Cached Copy missed; trying visual search");
        }

        HoverLatestAnswer(window);
        await Task.Delay(120);
        var visual = await ReadByCopyIconAsync(hwnd, window, layout, prompt);
        if (visual is not null) return new(visual, "cv-copy");

        var named = await ReadByCopyButtonsAsync(DoubaoUia.Snapshot(DoubaoUia.Root(hwnd) ?? root), layout, prompt);
        if (named is not null) return new(named, "uia-copy");

        Logger.Write("Copy unavailable; Doubao response may still be generating");
        return new(null, "none");
    }

    private static string? ReadFromUia(IReadOnlyList<UiaHit> hits, DoubaoLayout layout, string prompt, string? baseline)
    {
        var current = DoubaoUia.CollectChatText(hits, layout);
        if (!AnswerTextCleaner.LooksLikeSidebar(current))
        {
            var direct = AnswerTextCleaner.Clean(current, prompt);
            if (AnswerTextCleaner.IsUsable(direct, prompt))
            {
                Logger.Write($"Answer via UIA reply ({direct.Length} chars)");
                return direct;
            }
            Logger.Write($"UIA reply ignored ({Preview(direct)})");
        }
        var diffed = AnswerTextCleaner.Diff(baseline, current);
        if (AnswerTextCleaner.LooksLikeSidebar(diffed)) return null;
        var cleaned = AnswerTextCleaner.Clean(diffed, prompt);
        if (AnswerTextCleaner.IsUsable(cleaned, prompt))
        {
            Logger.Write($"Answer via UIA text ({cleaned.Length} chars)");
            return cleaned;
        }
        Logger.Write($"UIA text ignored ({Preview(cleaned)})");
        return null;
    }

    private async Task<string?> ReadByCopyButtonsAsync(IReadOnlyList<UiaHit> hits, DoubaoLayout layout, string prompt)
    {
        var named = NamedCopyButtons(hits, layout);
        Logger.Write($"Copy UIA candidates named={named.Count}");
        foreach (var hit in named)
        {
            var text = await InvokeCopyAsync(hit, prompt);
            if (text is not null)
            {
                Logger.Write($"Answer via UIA Copy button name='{hit.Name}' id='{hit.Id}'");
                return text;
            }
        }
        return null;
    }

    private async Task<string?> ReadByCopyRowAsync(IReadOnlyList<UiaHit> hits, DoubaoLayout layout, WinRect answer, string prompt)
    {
        var row = DoubaoUia.ToolbarButtons(hits, answer, layout)
            .Concat(DoubaoUia.CopyRowButtons(hits, layout)
                .Where(hit => hit.Rect.Top >= answer.Bottom - 22
                    && hit.Rect.Top <= answer.Bottom + 150))
            .DistinctBy(hit => (hit.Rect.Left, hit.Rect.Top, hit.Id))
            .OrderBy(hit => hit.Rect.Top)
            .ThenBy(hit => hit.Rect.Left)
            .ToList();
        Logger.Write("Copy row buttons=" + row.Count + string.Concat(row.Select(h =>
            $" [{h.Name}|{h.Id} {h.Rect.X:0},{h.Rect.Y:0} {h.Rect.Width:0}x{h.Rect.Height:0}]")));
        if (row.Count == 0) return null;
        foreach (var copy in row.Take(3))
        {
            var text = await InvokeCopyAsync(copy, prompt);
            if (text is null) continue;
            Logger.Write($"Answer via copy-row name='{copy.Name}' id='{copy.Id}' {copy.Rect.X:0},{copy.Rect.Y:0}");
            return text;
        }
        return null;
    }

    private static List<UiaHit> NamedCopyButtons(IReadOnlyList<UiaHit> hits, DoubaoLayout layout) =>
        hits.Where(h =>
                h.Type == ControlType.Button
                && (DoubaoUia.InToolbarBand(h.Rect, layout) || DoubaoUia.InChat(h.Rect, layout))
                && h.Rect.Width > 8 && h.Rect.Height > 8
                && (h.Name is "复制" or "Copy"
                    || h.Name.Contains("复制", StringComparison.Ordinal)
                    || h.Help.Contains("复制", StringComparison.Ordinal)
                    || h.Id.Equals("copy", StringComparison.OrdinalIgnoreCase)))
            .OrderByDescending(h => h.Rect.Bottom)
            .ThenBy(h => h.Rect.Left)
            .Take(3)
            .ToList();

    private async Task<string?> ReadByCopyIconAsync(
        IntPtr hwnd, NativeMethods.Rect window, DoubaoLayout layout, string prompt)
    {
        using var bitmap = ScreenPixels.Capture(window.Left, window.Top,
            Math.Max(1, window.Right - window.Left), Math.Max(1, window.Bottom - window.Top));
        if (bitmap is null)
        {
            Logger.Write("capture: could not capture Copy search region");
            return null;
        }
        try { bitmap.Save(Path.Combine(AppPaths.SupportDirectory, "last-copy-search.png"), ImageFormat.Png); }
        catch { }
        var preferred = _cachedCopyLocation?.X ?? CopyColumnXRatio(window, layout);
        Logger.Write($"capture: Copy search preferred x={preferred:0.000}");
        var match = CopyIconMatcher.Find(bitmap, window, preferred);
        if (match is null)
        {
            Logger.Write("capture: visual Copy icon not found");
            return null;
        }
        Logger.Write($"capture: cached Copy location x={match.Value.XRatio:0.000} y={match.Value.YRatio:0.000} score={match.Value.Score:0.000}");
        var copied = await ClickCopyAsync(hwnd, match.Value.X, match.Value.Y, prompt, "visual");
        if (copied is not null)
            _cachedCopyLocation = (match.Value.XRatio, match.Value.YRatio);
        return copied;
    }

    private static WinRect CopySearchBand(DoubaoLayout layout)
    {
        var top = Math.Max(layout.ChatTop, layout.Window.Top + layout.Window.Height * 0.48);
        top = Math.Min(top, Math.Max(layout.ChatTop, layout.Composer.Top - 560));
        var height = Math.Max(80, layout.Composer.Top - top + 8);
        var width = Math.Max(160, Math.Min(520, (layout.ChatRight - layout.ChatLeft) * 0.55));
        return new WinRect(layout.ChatLeft, top, width, height);
    }

    private static async Task<string?> ReadByOcrAsync(WinRect answer, string prompt)
    {
        if (answer.Width < 40 || answer.Height < 20) return null;
        using var bitmap = ScreenPixels.Capture(answer);
        if (bitmap is null) return null;
        try
        {
            var text = await RecognizeAsync(bitmap);
            var cleaned = AnswerTextCleaner.Clean(text ?? "", prompt);
            if (!AnswerTextCleaner.IsUsable(cleaned, prompt)) return null;
            Logger.Write($"Answer via OCR ({cleaned.Length} chars)");
            return cleaned;
        }
        catch (Exception ex)
        {
            Logger.Write($"OCR failed: {ex.Message}");
            return null;
        }
    }

    private async Task<string?> InvokeCopyAsync(UiaHit hit, string prompt)
    {
        var sequence = NativeMethods.GetClipboardSequenceNumber();
        var x = (int)(hit.Rect.Left + Math.Max(6, hit.Rect.Width / 2));
        var y = (int)(hit.Rect.Top + Math.Max(6, hit.Rect.Height / 2));
        try
        {
            InputSimulator.Click(x, y);
        }
        catch (Exception ex)
        {
            Logger.Write($"Copy click failed: {ex.Message}");
            return null;
        }
        var text = await ClipboardService.WaitForNewTextAsync(sequence, prompt, TimeSpan.FromMilliseconds(500));
        if (text is not null) return text;
        try
        {
            if (hit.Invoke && hit.Element.TryGetCurrentPattern(InvokePattern.Pattern, out var pattern))
                ((InvokePattern)pattern).Invoke();
        }
        catch (Exception ex)
        {
            Logger.Write($"Copy invoke failed: {ex.Message}");
            return null;
        }
        return await ClipboardService.WaitForNewTextAsync(sequence, prompt, TimeSpan.FromMilliseconds(500));
    }

    private async Task<string?> ClickCopyAsync(IntPtr hwnd, int x, int y, string prompt, string source)
    {
        var sentinel = $"lecture-copilot-copy-{Guid.NewGuid():N}";
        try { await ClipboardService.SetTextAsync(sentinel); }
        catch (Exception ex)
        {
            Logger.Write($"capture: could not prepare clipboard for {source} Copy: {ex.Message}");
            return null;
        }
        var sequence = NativeMethods.GetClipboardSequenceNumber();
        InputSimulator.Click(x, y);
        var text = await ClipboardService.WaitForNewTextAsync(sequence, prompt, TimeSpan.FromMilliseconds(300));
        if (text is not null) return text;

        Logger.Write($"capture: {source} Copy retrying physical click after focus");
        InputSimulator.Click(x, y);
        text = await ClipboardService.WaitForNewTextAsync(sequence, prompt, TimeSpan.FromMilliseconds(250));
        if (text is not null) return text;

        if (PressNearbyCopyButton(hwnd, x, y))
        {
            Logger.Write($"capture: {source} Copy retrying with UIA invoke");
            text = await ClipboardService.WaitForNewTextAsync(sequence, prompt, TimeSpan.FromMilliseconds(400));
            if (text is not null) return text;
        }

        Logger.Write($"capture: {source} Copy did not update clipboard");
        return null;
    }

    private static bool PressNearbyCopyButton(IntPtr hwnd, int x, int y)
    {
        var root = DoubaoUia.Root(hwnd);
        if (root is null) return false;
        var hits = DoubaoUia.Snapshot(root);
        var nearby = hits
            .Where(h => h.Type == ControlType.Button && h.Rect.Width is >= 8 and <= 78 && h.Rect.Height is >= 8 and <= 78
                && h.Name is not ("朗读" or "重新生成")
                && !h.Name.Contains("重新生成", StringComparison.Ordinal)
                && !h.Name.Contains("朗读", StringComparison.Ordinal))
            .Select(h =>
            {
                var dx = h.Rect.Left + h.Rect.Width / 2 - x;
                var dy = h.Rect.Top + h.Rect.Height / 2 - y;
                return (Hit: h, Distance: Math.Sqrt(dx * dx + dy * dy));
            })
            .Where(item => item.Distance <= 56)
            .OrderBy(item => item.Distance)
            .Select(item => item.Hit)
            .FirstOrDefault();
        if (nearby is null) return false;
        try
        {
            if (nearby.Invoke && nearby.Element.TryGetCurrentPattern(InvokePattern.Pattern, out var pattern))
            {
                ((InvokePattern)pattern).Invoke();
                return true;
            }
        }
        catch { }
        InputSimulator.Click(
            (int)(nearby.Rect.Left + nearby.Rect.Width / 2),
            (int)(nearby.Rect.Top + nearby.Rect.Height / 2));
        return true;
    }

    private static void HoverLatestAnswer(NativeMethods.Rect window)
    {
        NativeMethods.SetCursorPos(
            window.Left + (int)Math.Round((window.Right - window.Left) * 0.64),
            window.Top + (int)Math.Round((window.Bottom - window.Top) * 0.78));
    }

    private static double CopyColumnXRatio(NativeMethods.Rect window, DoubaoLayout layout)
    {
        var width = Math.Max(1, window.Right - window.Left);
        var column = layout.Composer.Width > 80 ? layout.Composer.Left : layout.ChatLeft;
        var ratio = (column + 22 - window.Left) / width;
        return ratio is >= 0.12 and <= 0.42 ? ratio : DefaultCopyXRatio;
    }

    private static WinRect AnswerBand(DoubaoLayout layout) =>
        new(layout.ChatLeft, Math.Max(layout.ChatTop, layout.ChatBottom - 360),
            Math.Max(80, layout.ChatRight - layout.ChatLeft), 320);

    private static async Task<string?> RecognizeAsync(Bitmap bitmap)
    {
        var engine = OcrEngine.TryCreateFromUserProfileLanguages()
                     ?? OcrEngine.TryCreateFromLanguage(new global::Windows.Globalization.Language("zh-Hans"));
        if (engine is null) return null;
        var path = Path.Combine(Path.GetTempPath(), $"lecture-copilot-ocr-{Guid.NewGuid():N}.png");
        try
        {
            bitmap.Save(path, ImageFormat.Png);
            var file = await global::Windows.Storage.StorageFile.GetFileFromPathAsync(path);
            using var stream = await file.OpenAsync(global::Windows.Storage.FileAccessMode.Read);
            var decoder = await BitmapDecoder.CreateAsync(stream);
            var software = await decoder.GetSoftwareBitmapAsync();
            var result = await engine.RecognizeAsync(software);
            return result.Text;
        }
        finally
        {
            try { File.Delete(path); } catch { }
        }
    }

    private static string Preview(string? text)
    {
        var value = AnswerTextCleaner.Normalize(text).Replace('\n', '/');
        return value.Length <= 80 ? value : value[..80];
    }
}
