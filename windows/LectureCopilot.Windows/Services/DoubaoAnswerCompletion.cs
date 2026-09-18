using System.Text.RegularExpressions;
using System.Windows.Automation;

namespace LectureCopilot.Windows.Services;

internal static class DoubaoAnswerCompletion
{
    private static readonly Regex Elapsed = new(@"共用时\s*\d+\s*秒|用时\s*\d+\s*秒", RegexOptions.Compiled);

    public static (int Elapsed, int Chars, string Text) Baseline(IntPtr hwnd)
    {
        var snap = Measure(hwnd);
        return (snap.Elapsed, snap.ChatChars, snap.ChatText ?? "");
    }

    public static int MarkerCount(IntPtr hwnd) => Measure(hwnd).Elapsed;

    public static bool IsGenerating(IntPtr hwnd)
    {
        var root = DoubaoUia.Root(hwnd);
        return root is not null && DoubaoUia.Snapshot(root).Any(hit => IsStop(hit.Name));
    }

    public static async Task<bool> WaitUntilSafeAsync(IntPtr hwnd, int baselineElapsed, int baselineChars)
    {
        var first = Measure(hwnd);
        if (first.Generating)
        {
            Logger.Write("Doubao still generating (stop control)");
            return false;
        }
        if (HasFinishedChrome(first, baselineElapsed))
        {
            Logger.Write($"Doubao answer finished elapsed={first.Elapsed} toolbar={first.FinishedToolbar} chars={first.ChatChars}");
            return true;
        }

        await Task.Delay(450);
        var second = Measure(hwnd);
        if (second.Generating)
        {
            Logger.Write("Doubao still generating after first settle sample");
            return false;
        }
        if (HasFinishedChrome(second, baselineElapsed))
        {
            Logger.Write($"Doubao answer finished after settle elapsed={second.Elapsed} toolbar={second.FinishedToolbar}");
            return true;
        }
        if (second.ChatChars >= first.ChatChars + 8)
        {
            Logger.Write($"Doubao answer still growing {first.ChatChars}->{second.ChatChars}; skip extract");
            return false;
        }

        await Task.Delay(450);
        var third = Measure(hwnd);
        if (third.Generating)
        {
            Logger.Write("Doubao still generating after second settle sample");
            return false;
        }
        if (HasFinishedChrome(third, baselineElapsed))
        {
            Logger.Write($"Doubao answer finished after second settle elapsed={third.Elapsed} toolbar={third.FinishedToolbar}");
            return true;
        }
        if (third.ChatChars >= second.ChatChars + 8)
        {
            Logger.Write($"Doubao answer still growing {second.ChatChars}->{third.ChatChars}; skip extract");
            return false;
        }
        if (third.ChatChars < baselineChars + 24)
        {
            Logger.Write($"Doubao answer not ready chars={third.ChatChars} baseline={baselineChars}");
            return false;
        }
        if (AnswerTextCleaner.LooksLikeSidebar(third.ChatText))
        {
            Logger.Write("Doubao chat text still looks like the sidebar; skip extract");
            return false;
        }

        Logger.Write($"Doubao answer complete chars={third.ChatChars} baseline={baselineChars}");
        return true;
    }

    private static bool HasFinishedChrome(in Snapshot snap, int baselineElapsed) =>
        snap.Elapsed > baselineElapsed || snap.FinishedToolbar;

    private static Snapshot Measure(IntPtr hwnd)
    {
        var root = DoubaoUia.Root(hwnd);
        if (root is null) return default;
        var layout = DoubaoUia.Layout(root);
        if (layout is null) return default;
        var hits = DoubaoUia.Snapshot(root);
        var generating = false;
        var elapsed = 0;
        var finishedToolbar = false;
        foreach (var hit in hits)
        {
            if (IsStop(hit.Name)) generating = true;
            if (Elapsed.IsMatch(hit.Name) && DoubaoUia.InToolbarBand(hit.Rect, layout)) elapsed++;
            if (IsFinishedAction(hit.Name) && DoubaoUia.InToolbarBand(hit.Rect, layout))
                finishedToolbar = true;
        }
        var chat = DoubaoUia.CollectChatText(hits, layout);
        elapsed = Math.Max(elapsed, Elapsed.Matches(chat).Count);
        return new Snapshot(generating, elapsed, finishedToolbar, chat, chat.Length);
    }

    private static bool IsStop(string name) =>
        name.Contains("停止生成", StringComparison.Ordinal)
        || name.Contains("停止输出", StringComparison.Ordinal)
        || name.Contains("Stop generating", StringComparison.OrdinalIgnoreCase);

    private static bool IsFinishedAction(string name) =>
        name.Contains("重新生成", StringComparison.Ordinal)
        || name is "分享" or "复制" or "Copy";

    private readonly record struct Snapshot(
        bool Generating, int Elapsed, bool FinishedToolbar, string ChatText, int ChatChars);
}
