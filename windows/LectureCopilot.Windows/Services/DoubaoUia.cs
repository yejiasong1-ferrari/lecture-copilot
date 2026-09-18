using System.Text;
using System.Windows;
using System.Windows.Automation;
using AutomationCondition = System.Windows.Automation.Condition;

namespace LectureCopilot.Windows.Services;

internal sealed record DoubaoLayout(
    Rect Window,
    Rect Composer,
    double ChatLeft,
    double ChatRight,
    double ChatTop,
    double ChatBottom);

internal sealed record UiaHit(
    AutomationElement Element,
    ControlType Type,
    string Name,
    string Id,
    string ClassName,
    string Help,
    Rect Rect,
    bool Invoke,
    bool TextPattern,
    bool ValuePattern,
    bool Legacy);

internal static class DoubaoUia
{
    public static AutomationElement? Root(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return null;
        try { return AutomationElement.FromHandle(hwnd); }
        catch { return null; }
    }

    public static DoubaoLayout? Layout(AutomationElement root)
    {
        Rect window;
        try { window = root.Current.BoundingRectangle; }
        catch { return null; }
        if (window.IsEmpty) return null;
        var composer = Composer(root);
        Rect composerRect;
        try { composerRect = composer?.Current.BoundingRectangle ?? default; }
        catch { composerRect = default; }
        if (composerRect.IsEmpty)
            composerRect = new Rect(window.Left + window.Width * 0.22, window.Bottom - 210, window.Width * 0.74, 180);
        var chatLeft = SidebarRight(root, window) + 6;
        return new DoubaoLayout(
            window,
            composerRect,
            chatLeft,
            window.Right - 12,
            window.Top + 72,
            Math.Max(window.Top + 120, composerRect.Top - 6));
    }

    public static AutomationElement? Composer(AutomationElement root)
    {
        try
        {
            var byId = root.FindFirst(TreeScope.Descendants,
                new PropertyCondition(AutomationElement.AutomationIdProperty, "input-engine-container"));
            if (byId is not null) return byId;
        }
        catch { }

        try
        {
            var window = root.Current.BoundingRectangle;
            return root.FindAll(TreeScope.Descendants,
                    new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Edit))
                .Cast<AutomationElement>()
                .Select(e => new { Element = e, Rect = SafeRect(e), Name = SafeName(e) })
                .Where(x => x.Element.Current.IsEnabled
                            && x.Rect.Width > 200
                            && x.Rect.Height >= 28
                            && x.Rect.Top > window.Top + window.Height * 0.4
                            && !LooksLikeFileDialog(x.Name))
                .OrderByDescending(x => x.Rect.Width)
                .Select(x => x.Element)
                .FirstOrDefault();
        }
        catch { return null; }
    }

    public static IReadOnlyList<UiaHit> Snapshot(AutomationElement root, int limit = 6000)
    {
        var hits = new List<UiaHit>(1024);
        try
        {
            var cache = SnapshotCache();
            using var activeCache = cache.Activate();
            foreach (AutomationElement element in root.FindAll(TreeScope.Descendants, AutomationCondition.TrueCondition))
            {
                var hit = DescribeCached(element);
                if (hit is null) continue;
                hits.Add(hit);
                if (hits.Count >= limit) break;
            }
        }
        catch (Exception ex) { Logger.Write($"UIA snapshot failed: {ex.Message}"); }
        return hits;
    }

    private static CacheRequest SnapshotCache()
    {
        var cache = new CacheRequest { TreeScope = TreeScope.Element };
        foreach (var property in new[] {
            AutomationElement.BoundingRectangleProperty, AutomationElement.ControlTypeProperty,
            AutomationElement.NameProperty, AutomationElement.AutomationIdProperty,
            AutomationElement.ClassNameProperty, AutomationElement.HelpTextProperty,
            AutomationElement.IsInvokePatternAvailableProperty, AutomationElement.IsTextPatternAvailableProperty,
            AutomationElement.IsValuePatternAvailableProperty }) cache.Add(property);
        return cache;
    }

    private static UiaHit? DescribeCached(AutomationElement element)
    {
        try
        {
            var info = element.Cached;
            if (info.BoundingRectangle.IsEmpty) return null;
            return new UiaHit(element, info.ControlType, info.Name ?? "", info.AutomationId ?? "",
                info.ClassName ?? "", info.HelpText ?? "", info.BoundingRectangle,
                (bool)element.GetCachedPropertyValue(AutomationElement.IsInvokePatternAvailableProperty),
                (bool)element.GetCachedPropertyValue(AutomationElement.IsTextPatternAvailableProperty),
                (bool)element.GetCachedPropertyValue(AutomationElement.IsValuePatternAvailableProperty), false);
        }
        catch { return Describe(element); }
    }

    public static string CollectChatText(IReadOnlyList<UiaHit> hits, DoubaoLayout layout)
    {
        var chunks = CollectChatChunks(hits, layout);
        if (chunks.Length >= 8 && !AnswerTextCleaner.LooksLikeSidebar(chunks))
            return chunks;

        var document = hits
            .Where(h => h.Type == ControlType.Document && h.TextPattern)
            .OrderByDescending(h => h.Rect.Width * h.Rect.Height)
            .Select(ReadText)
            .FirstOrDefault(text => text.Length >= 8) ?? "";
        if (AnswerTextCleaner.LooksLikeSidebar(document)) return chunks;
        return chunks.Length >= 8 ? chunks : document;
    }

    private static string CollectChatChunks(IReadOnlyList<UiaHit> hits, DoubaoLayout layout)
    {
        var chunks = new List<(double Y, string Text)>();
        foreach (var hit in hits)
        {
            if (!InChat(hit.Rect, layout)) continue;
            var text = ReadText(hit);
            if (text.Length < 2 || AnswerTextCleaner.IsChrome(text)) continue;
            if (AnswerTextCleaner.LooksLikeSidebar(text)) continue;
            chunks.Add((hit.Rect.Top, text));
        }

        var ordered = new List<string>();
        string? last = null;
        foreach (var chunk in chunks.OrderBy(c => c.Y).ThenBy(c => c.Text.Length))
        {
            if (last is not null && (chunk.Text == last || last.Contains(chunk.Text))) continue;
            if (last is not null && chunk.Text.Contains(last) && chunk.Text.Length > last.Length)
            {
                ordered[^1] = chunk.Text;
                last = chunk.Text;
                continue;
            }
            ordered.Add(chunk.Text);
            last = chunk.Text;
        }
        return string.Join("\n", ordered);
    }

    public static string ReadText(UiaHit hit)
    {
        var fromPattern = ReadPatterns(hit.Element);
        if (fromPattern.Length >= 2) return fromPattern;
        return hit.Name.Trim();
    }

    public static string ReadPatterns(AutomationElement element)
    {
        try
        {
            if (element.TryGetCurrentPattern(TextPattern.Pattern, out var textPattern))
            {
                var text = ((TextPattern)textPattern).DocumentRange.GetText(-1)?.Trim() ?? "";
                if (text.Length >= 2) return text;
            }
        }
        catch { }

        try
        {
            if (element.TryGetCurrentPattern(ValuePattern.Pattern, out var valuePattern))
            {
                var text = ((ValuePattern)valuePattern).Current.Value?.Trim() ?? "";
                if (text.Length >= 2) return text;
            }
        }
        catch { }

        try
        {
            var name = element.Current.Name?.Trim() ?? "";
            if (name.Length >= 2) return name;
        }
        catch { }
        return "";
    }

    public static bool InChat(Rect rect, DoubaoLayout layout)
    {
        if (rect.IsEmpty || rect.Width < 40 || rect.Height < 10) return false;
        return rect.Left >= layout.ChatLeft - 12
               && rect.Top >= layout.ChatTop
               && rect.Bottom <= layout.ChatBottom + 8
               && rect.Width >= 80;
    }

    public static bool InToolbarBand(Rect rect, DoubaoLayout layout)
    {
        if (rect.IsEmpty) return false;
        return rect.Left >= layout.ChatLeft - 24
               && rect.Right <= layout.ChatRight + 36
               && rect.Top >= layout.ChatTop
               && rect.Top < layout.Composer.Top + 8
               && rect.Width is >= 14 and <= 220
               && rect.Height is >= 14 and <= 80;
    }

    public static UiaHit? LatestAnswer(IReadOnlyList<UiaHit> hits, DoubaoLayout layout, string prompt)
    {
        return hits
            .Where(h => InChat(h.Rect, layout)
                        && h.Rect.Height >= 18
                        && h.Type is not null
                        && (h.Type == ControlType.Text || h.Type == ControlType.Document
                            || h.Type == ControlType.Group || h.Type == ControlType.Custom
                            || h.Type == ControlType.ListItem || h.Type == ControlType.Pane))
            .Select(h => (Hit: h, Text: ReadText(h)))
            .Where(x => x.Text.Length >= 8
                        && !AnswerTextCleaner.IsChrome(x.Text)
                        && !AnswerTextCleaner.IsPromptResidue(x.Text, prompt)
                        && !string.Equals(x.Text, prompt.Trim(), StringComparison.Ordinal))
            .OrderByDescending(x => x.Hit.Rect.Bottom)
            .ThenByDescending(x => x.Text.Length)
            .Select(x => x.Hit)
            .FirstOrDefault();
    }

    public static List<UiaHit> ToolbarButtons(IReadOnlyList<UiaHit> hits, Rect answer, DoubaoLayout layout)
    {
        var top = answer.Bottom - 18;
        var bottom = Math.Min(layout.ChatBottom + 36, answer.Bottom + 250);
        var left = Math.Max(layout.ChatLeft - 20, answer.Left - 48);
        var right = Math.Min(layout.ChatRight, answer.Right + 80);
        return hits
            .Where(h => h.Type == ControlType.Button
                        && h.Rect.Width is >= 10 and <= 78
                        && h.Rect.Height is >= 10 and <= 78
                        && h.Rect.Top >= top
                        && h.Rect.Bottom <= bottom
                        && h.Rect.Left >= left
                        && h.Rect.Right <= right)
            .OrderBy(h => h.Rect.Top)
            .ThenBy(h => h.Rect.Left)
            .ToList();
    }

    public static List<UiaHit> CopyRowButtons(IReadOnlyList<UiaHit> hits, DoubaoLayout layout)
    {
        var right = layout.ChatLeft + Math.Max(280, (layout.ChatRight - layout.ChatLeft) * 0.58);
        var candidates = hits
            .Where(h => LooksLikeCopyAction(h)
                        && h.Rect.Top >= layout.ChatTop
                        && h.Rect.Bottom <= layout.Composer.Top + 16
                        && h.Rect.Left >= layout.ChatLeft - 16
                        && h.Rect.Left <= right)
            .ToList();
        if (candidates.Count == 0) return candidates;
        var bottom = candidates.Max(h => h.Rect.Bottom);
        return candidates
            .Where(h => bottom - h.Rect.Bottom <= 28)
            .OrderBy(h => h.Rect.Left)
            .ToList();
    }

    public static bool LooksLikeCopyAction(UiaHit hit)
    {
        if (hit.Rect.Width is < 14 or > 72 || hit.Rect.Height is < 14 or > 72) return false;
        if (Math.Abs(hit.Rect.Width - hit.Rect.Height) > 22) return false;
        return hit.Type == ControlType.Button
               || hit.Type == ControlType.Custom
               || hit.Type == ControlType.Image;
    }

    public static AutomationElement? ProseMirror(AutomationElement root)
    {
        try
        {
            var cache = SnapshotCache();
            using var activeCache = cache.Activate();
            foreach (AutomationElement element in root.FindAll(TreeScope.Descendants, AutomationCondition.TrueCondition))
            {
                string className;
                Rect rect;
                try
                {
                    className = element.Cached.ClassName ?? "";
                    rect = element.Cached.BoundingRectangle;
                }
                catch { continue; }
                if (rect.Width < 120 || rect.Height < 16) continue;
                if (className.Contains("ProseMirror", StringComparison.OrdinalIgnoreCase)
                    || className.Contains("tiptap", StringComparison.OrdinalIgnoreCase))
                    return element;
            }
        }
        catch { }
        return null;
    }

    public static bool HasPlaceholder(IReadOnlyList<UiaHit> hits, DoubaoLayout layout) =>
        hits.Any(hit => Overlaps(hit.Rect, layout.Composer)
                        && hit.Name.Contains("发消息或按住空格说话", StringComparison.Ordinal));

    public static bool ComposerLooksEmpty(AutomationElement root)
    {
        var editor = ProseMirror(root);
        if (editor is null) return false;
        try
        {
            if ((editor.Current.Name ?? "").Contains("发消息或按住空格说话", StringComparison.Ordinal))
                return true;
            foreach (AutomationElement child in editor.FindAll(TreeScope.Children, AutomationCondition.TrueCondition))
            {
                try
                {
                    if ((child.Current.Name ?? "").Contains("发消息或按住空格说话", StringComparison.Ordinal))
                        return true;
                }
                catch { }
            }
            if (editor.TryGetCurrentPattern(TextPattern.Pattern, out var pattern))
            {
                var text = ((TextPattern)pattern).DocumentRange.GetText(80) ?? "";
                if (string.IsNullOrWhiteSpace(text)
                    || text.Contains("发消息或按住空格说话", StringComparison.Ordinal))
                    return true;
            }
        }
        catch { }
        return false;
    }

    public static AutomationElement? SendControl(AutomationElement root)
    {
        var composer = Composer(root);
        if (composer is null) return null;
        Rect band;
        try { band = composer.Current.BoundingRectangle; }
        catch { return null; }
        if (band.IsEmpty) return null;
        AutomationElement? best = null;
        var bestLeft = double.MinValue;
        try
        {
            foreach (AutomationElement element in composer.FindAll(TreeScope.Descendants, AutomationCondition.TrueCondition))
            {
                Rect rect;
                string className;
                try
                {
                    rect = element.Current.BoundingRectangle;
                    className = element.Current.ClassName ?? "";
                }
                catch { continue; }
                if (rect.Width is < 28 or > 78 || rect.Height is < 28 or > 78) continue;
                if (rect.Left < band.Right - 96) continue;
                if (rect.Top < band.Bottom - 96) continue;
                if (rect.Left < band.Left + 120) continue;
                if (className.Contains("aria-disabled", StringComparison.Ordinal)
                    || className.Contains("rounded-full", StringComparison.Ordinal)
                    || className.Contains("size-36", StringComparison.Ordinal)
                    || className.Contains("cursor-pointer", StringComparison.Ordinal))
                {
                    if (rect.Left > bestLeft)
                    {
                        best = element;
                        bestLeft = rect.Left;
                    }
                }
            }
        }
        catch { }
        return best;
    }

    public static int AttachmentCount(IReadOnlyList<UiaHit> hits, DoubaoLayout layout)
    {
        var count = 0;
        var textBand = new Rect(layout.Composer.Left, layout.Composer.Top, layout.Composer.Width,
            Math.Max(36, layout.Composer.Height * 0.55));
        foreach (var hit in hits)
        {
            if (!Overlaps(hit.Rect, textBand)) continue;
            if (hit.Rect.Width < 24 || hit.Rect.Height < 16) continue;
            var blob = $"{hit.Name} {hit.Id} {hit.Help} {hit.ClassName}";
            if (hit.Type == ControlType.Image)
            {
                count++;
                continue;
            }
            if (blob.Contains("图片", StringComparison.OrdinalIgnoreCase)
                || blob.Contains("截图", StringComparison.OrdinalIgnoreCase)
                || blob.Contains("附件", StringComparison.OrdinalIgnoreCase)
                || blob.Contains("thumbnail", StringComparison.OrdinalIgnoreCase)
                || blob.Contains("attachment", StringComparison.OrdinalIgnoreCase)
                || blob.Contains(".png", StringComparison.OrdinalIgnoreCase)
                || blob.Contains("remove", StringComparison.OrdinalIgnoreCase)
                || blob.Contains("删除", StringComparison.Ordinal))
                count++;
        }
        return count;
    }

    public static UiaHit? Describe(AutomationElement element)
    {
        try
        {
            var rect = element.Current.BoundingRectangle;
            if (rect.IsEmpty) return null;
            var invoke = false;
            var text = false;
            var value = false;
            var legacy = false;
            try { invoke = element.TryGetCurrentPattern(InvokePattern.Pattern, out _); } catch { }
            try { text = element.TryGetCurrentPattern(TextPattern.Pattern, out _); } catch { }
            try { value = element.TryGetCurrentPattern(ValuePattern.Pattern, out _); } catch { }
            return new UiaHit(
                element,
                element.Current.ControlType,
                element.Current.Name ?? "",
                element.Current.AutomationId ?? "",
                element.Current.ClassName ?? "",
                element.Current.HelpText ?? "",
                rect,
                invoke, text, value, legacy);
        }
        catch { return null; }
    }

    public static string Patterns(UiaHit hit)
    {
        var parts = new List<string>(4);
        if (hit.Invoke) parts.Add("Invoke");
        if (hit.TextPattern) parts.Add("Text");
        if (hit.ValuePattern) parts.Add("Value");
        if (hit.Legacy) parts.Add("Legacy");
        return parts.Count == 0 ? "-" : string.Join(",", parts);
    }

    private static double SidebarRight(AutomationElement root, Rect window)
    {
        var right = window.Left + window.Width * 0.20;
        try
        {
            var cache = SnapshotCache();
            using var activeCache = cache.Activate();
            foreach (AutomationElement element in root.FindAll(TreeScope.Descendants, AutomationCondition.TrueCondition))
            {
                string id;
                Rect rect;
                try
                {
                    id = element.Cached.AutomationId ?? "";
                    rect = element.Cached.BoundingRectangle;
                }
                catch { continue; }
                if (!id.StartsWith("conversation_", StringComparison.Ordinal) || rect.IsEmpty) continue;
                if (rect.Left < window.Left + window.Width * 0.45)
                    right = Math.Max(right, rect.Right);
            }
        }
        catch { }
        return right;
    }

    private static Rect SafeRect(AutomationElement element)
    {
        try { return element.Current.BoundingRectangle; }
        catch { return Rect.Empty; }
    }

    private static string SafeName(AutomationElement element)
    {
        try { return element.Current.Name ?? ""; }
        catch { return ""; }
    }

    private static bool LooksLikeFileDialog(string name) =>
        name.Contains("文件名", StringComparison.Ordinal)
        || name.Contains("修改日期", StringComparison.Ordinal)
        || name.Contains("类型", StringComparison.Ordinal)
        || name.Contains("大小", StringComparison.Ordinal)
        || name.Contains("File name", StringComparison.OrdinalIgnoreCase)
        || name.Contains("Address", StringComparison.OrdinalIgnoreCase);

    private static bool Overlaps(Rect a, Rect b) =>
        a.Left < b.Right && a.Right > b.Left && a.Top < b.Bottom && a.Bottom > b.Top;
}
