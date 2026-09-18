using System.Text;
using System.Text.RegularExpressions;

namespace LectureCopilot.Windows.Services;

internal static class AnswerTextCleaner
{
    private static readonly string[] Chrome =
    [
        "发消息或按住空格说话", "新工作任务", "开启新对话", "新建对话", "图像生成", "帮我写作",
        "音乐生成", "视频生成", "豆包 快速", "打开侧边工作台", "对话摘要", "定时任务",
        "插件 · 技能 · 伙伴", "云盘", "手机遥控电脑", "API 服务", "创建新项目",
        "查看套餐和定价", "Still generating", "复制", "Copy", "重新生成", "分享",
        "新对话", "主对话", "开启新对话", "新建对话", "对话主题", "对话摘要",
        "讲解页面内容", "直接回答题目", "直接回答截图题目",
        "截图内容翻译", "新截图内容翻译", "新截图内容对照翻译", "新截图内容逐句对照翻译",
        "AI 生成可能有误", "请核实", "展开全部", "对话产物", "对话资源", "最近文件",
        "doc_editor", "last-capture.png", "技能", "💡解答"
    ];

    private static readonly string[] Placeholders =
    [
        "一句话说明为什么", "先给一句话结论", "必须按这个格式", "如果是选择题", "如果是问答题",
        "不要复述题干", "不要写长篇", "不要推荐问题", "用一段中文把这页讲懂", "大约4到8句",
        "1到2句自然口语", "像学生在说话", "a错：一句话", "c错：一句话", "d错：一句话",
        "a错一句话", "c错一句话", "d错一句话"
    ];

    public static string Diff(string? baseline, string current)
    {
        current = Normalize(current);
        baseline = Normalize(baseline);
        if (current.Length == 0) return "";
        if (baseline.Length == 0) return current;
        if (current.StartsWith(baseline, StringComparison.Ordinal) && current.Length > baseline.Length)
            return current[baseline.Length..].Trim();

        var oldLines = baseline.Split('\n');
        var newLines = current.Split('\n');
        var i = 0;
        while (i < oldLines.Length && i < newLines.Length && oldLines[i] == newLines[i]) i++;
        if (i > 0 && i <= newLines.Length)
        {
            var rest = string.Join('\n', newLines.Skip(i)).Trim();
            if (rest.Length >= 8) return rest;
        }

        var oldSet = new HashSet<string>(oldLines.Where(l => l.Length > 0));
        var added = newLines.Where(line => line.Length > 0 && !oldSet.Contains(line)).ToList();
        return string.Join('\n', added).Trim();
    }

    public static string Clean(string text, string prompt)
    {
        text = Normalize(text);
        if (text.Length == 0) return "";
        // Chromium's document TextPattern can contain the whole application, including
        // the sidebar and a captured desktop. Prefer the final assistant message.
        if (text.Contains('\uFFFC') || text.Length > 1200)
        {
            var elapsed = Regex.Matches(text, @"共用时\s*\d+\s*秒");
            if (elapsed.Count > 0)
            {
                var start = elapsed[^1].Index + elapsed[^1].Length;
                text = text[start..].TrimStart();
            }
            else if (IsDirectAnswerPrompt(prompt))
            {
                var start = LastMeaningfulAnswerIndex(text);
                if (start >= 0) text = text[start..];
            }
            var objectMarker = text.IndexOf('\uFFFC');
            if (objectMarker >= 0) text = text[..objectMarker];
        }
        var promptNorm = Normalize(prompt);
        if (promptNorm.Length > 0 && text.StartsWith(promptNorm, StringComparison.Ordinal))
            text = text[promptNorm.Length..].Trim();

        var builder = new StringBuilder();
        foreach (var raw in text.Split('\n'))
        {
            var line = raw.Trim();
            if (line.Length == 0)
            {
                if (builder.Length > 0 && builder[^1] != '\n') builder.AppendLine();
                continue;
            }
            if (IsChrome(line) || IsAnswerBanner(line)) continue;
            if (IsPromptPlaceholderLine(line)) continue;
            if (!IsStructuralAnswerLine(line) && IsPromptLine(line, promptNorm)) continue;
            builder.AppendLine(line);
        }
        var cleaned = Normalize(builder.ToString());
        if (IsDirectAnswerPrompt(prompt))
            cleaned = KeepFromLastRealAnswer(cleaned);
        return cleaned;
    }

    public static bool IsUsable(string? text, string prompt)
    {
        if (string.IsNullOrWhiteSpace(text)) return false;
        var value = Normalize(text);
        if (value.Length < 8) return false;
        if (value.StartsWith("lecture-copilot-copy-", StringComparison.Ordinal)) return false;
        if (value.Contains('\uFFFC')) return false;
        var promptNorm = Normalize(prompt);
        if (promptNorm.Length > 0 && string.Equals(value, promptNorm, StringComparison.Ordinal)) return false;
        if (IsChrome(value)) return false;
        if (LooksLikeSidebar(value)) return false;
        if (IsPromptResidue(value, promptNorm)) return false;
        if (!IsPlausibleAnswer(value, promptNorm)) return false;
        var chromeHits = Chrome.Count(item => value.Contains(item, StringComparison.OrdinalIgnoreCase));
        return chromeHits < 3;
    }

    public static bool IsCopiedAnswer(string? text, string prompt)
    {
        if (string.IsNullOrWhiteSpace(text)) return false;
        var copied = Normalize(text);
        if (copied.StartsWith("lecture-copilot-copy-", StringComparison.Ordinal)) return false;
        var promptNorm = Normalize(prompt);
        if (promptNorm.Length > 0 && string.Equals(copied, promptNorm, StringComparison.Ordinal)) return false;
        var cleaned = Clean(copied, prompt);
        if (cleaned.Length < 8) return false;
        if (LooksLikeSidebar(cleaned) || IsChrome(cleaned)) return false;
        if (!IsPromptResidue(cleaned, prompt)) return true;
        return HasUniqueContent(cleaned, prompt) && cleaned.Length >= 24;
    }

    public static bool IsPromptResidue(string text, string prompt)
    {
        var compactText = Compact(text);
        var compactPrompt = Compact(prompt);
        if (compactText.Length >= 8 && compactPrompt.Length >= 12 && compactPrompt.Contains(compactText))
            return true;
        var lines = Normalize(text).Split('\n').Select(line => line.Trim()).Where(line => line.Length > 0).ToList();
        if (lines.Count == 0) return true;
        var unique = lines.Where(line => HasUniqueContent(line, prompt)).ToList();
        if (unique.Count == 0) return true;
        var uniqueLength = unique.Sum(line => line.Length);
        if (uniqueLength >= 24) return false;
        var promptHits = lines.Count(line =>
            !HasUniqueContent(line, prompt) && !IsStructuralAnswerLine(line) && !IsAnswerBanner(line));
        return promptHits >= Math.Max(2, (lines.Count + 1) / 2);
    }

    public static bool IsPlausibleAnswer(string text, string prompt)
    {
        if (IsPromptResidue(text, prompt)) return false;
        var chinese = text.Count(IsChinese);
        var latin = text.Any(ch => ch is (>= 'A' and <= 'Z') or (>= 'a' and <= 'z'));
        if (IsDirectAnswerPrompt(prompt))
            return HasMeaningfulDirectAnswer(text);
        if (prompt.Contains("Say in Class", StringComparison.OrdinalIgnoreCase)
            || prompt.Contains("你可以很口语地回答", StringComparison.Ordinal))
            return latin && text.Length >= 24;
        if (prompt.Contains("逐句对照翻译", StringComparison.Ordinal) || prompt.Contains("只做逐句", StringComparison.Ordinal))
            return latin && chinese >= 8 && text.Length >= 24;
        return text.Length >= 24 && (chinese >= 8 || latin);
    }

    private static bool IsDirectAnswerPrompt(string prompt) =>
        prompt.Contains("Direct Answer", StringComparison.OrdinalIgnoreCase)
        || prompt.Contains("直接回答", StringComparison.Ordinal);

    private static bool HasMeaningfulDirectAnswer(string text)
    {
        if (!text.Contains("答案", StringComparison.Ordinal)) return false;
        foreach (var line in Normalize(text).Split('\n'))
        {
            if (HasMeaningfulPayload(line.Trim())) return true;
        }
        return false;
    }

    private static string KeepFromLastRealAnswer(string text)
    {
        var index = LastMeaningfulAnswerIndex(text);
        return index >= 0 ? text[index..].Trim() : text;
    }

    private static int LastMeaningfulAnswerIndex(string text)
    {
        var last = -1;
        var offset = 0;
        foreach (var raw in text.Split('\n'))
        {
            var line = raw.Trim();
            if (line.StartsWith("答案", StringComparison.Ordinal) && HasMeaningfulPayload(line))
                last = offset + raw.IndexOf("答案", StringComparison.Ordinal);
            offset += raw.Length + 1;
        }
        return last;
    }

    private static bool IsPromptPlaceholderLine(string line)
    {
        var compactLine = Compact(line);
        if (compactLine.Length < 4) return false;
        if (Placeholders.Any(item => compactLine.Contains(item, StringComparison.OrdinalIgnoreCase)))
            return true;
        var payload = PayloadAfterColon(line);
        return payload is { Length: >= 2 and <= 18 }
               && Placeholders.Any(item => Compact(payload).Contains(item, StringComparison.OrdinalIgnoreCase));
    }

    private static bool HasUniqueContent(string line, string prompt)
    {
        if (IsPromptPlaceholderLine(line)) return false;
        var payload = PayloadAfterColon(line);
        if (!string.IsNullOrEmpty(payload) && !IsChoiceLetter(payload))
        {
            var compactPayload = Compact(payload);
            if (compactPayload.Length >= 4 && !Compact(prompt).Contains(compactPayload))
                return true;
        }
        if (IsPromptLine(line, prompt)) return false;
        return HasMeaningfulPayload(line) || line.Length >= 8;
    }

    private static bool HasMeaningfulPayload(string line)
    {
        var payload = PayloadAfterColon(line) ?? (line.StartsWith("答案", StringComparison.Ordinal) ? line : "");
        if (payload.Length == 0) return false;
        if (IsChoiceLetter(payload)) return true;
        if (IsPromptPlaceholderLine(line)) return false;
        var compact = Compact(payload);
        if (compact.Length < 2) return false;
        var latin = payload.Count(ch => ch is (>= 'A' and <= 'Z') or (>= 'a' and <= 'z'));
        var chinese = payload.Count(IsChinese);
        return latin >= 8 || chinese >= 4;
    }

    private static bool IsChoiceLetter(string text)
    {
        var compact = Compact(text);
        return compact.Length == 1 && compact[0] is >= 'A' and <= 'D';
    }

    private static string? PayloadAfterColon(string line)
    {
        var index = line.IndexOf('：');
        if (index < 0) index = line.IndexOf(':');
        if (index < 0 || index >= line.Length - 1) return null;
        return line[(index + 1)..].Trim();
    }

    private static bool IsPromptLine(string line, string prompt)
    {
        if (line.Length < 3) return false;
        var compactLine = Compact(line);
        var compactPrompt = Compact(prompt);
        return compactLine.Length >= 3 && compactPrompt.Contains(compactLine);
    }

    private static bool IsAnswerBanner(string line)
    {
        var trimmed = line.Trim().TrimStart('#', '*').Trim();
        return trimmed is "💡解答" or "解答" or "回答";
    }

    private static bool IsStructuralAnswerLine(string line) =>
        line.StartsWith("答案", StringComparison.Ordinal)
        || line.StartsWith("原因", StringComparison.Ordinal)
        || line.StartsWith("其他选项", StringComparison.Ordinal)
        || line.StartsWith("你可以很口语地回答", StringComparison.Ordinal)
        || line.StartsWith("Class Summary", StringComparison.Ordinal);

    private static string Compact(string text)
    {
        var builder = new StringBuilder(text.Length);
        foreach (var ch in text)
        {
            if (!char.IsWhiteSpace(ch) && ch is not '*' and not '•' and not '·') builder.Append(ch);
        }
        return builder.ToString();
    }

    private static bool IsChinese(char ch) => ch >= 0x4E00 && ch <= 0x9FFF;

    public static bool LooksLikeSidebar(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return false;
        var lines = Normalize(text).Split('\n')
            .Select(line => line.Trim())
            .Where(line => line.Length > 0)
            .ToList();
        if (lines.Count < 4) return false;
        var titleHits = lines.Count(IsSessionTitle);
        if (titleHits >= 3) return true;
        var shortLines = lines.Count(line => line.Length <= 18);
        return lines.Count >= 8 && shortLines >= lines.Count * 0.7 && titleHits >= 2;
    }

    public static bool IsSessionTitle(string line)
    {
        var trimmed = line.Trim();
        return Chrome.Any(item => string.Equals(item, trimmed, StringComparison.OrdinalIgnoreCase));
    }

    public static bool IsChrome(string text)
    {
        var trimmed = text.Trim();
        if (trimmed.Length == 0) return true;
        if (Regex.IsMatch(trimmed, @"^今天\s*\d{1,2}:\d{2}$")) return true;
        if (Chrome.Any(item => string.Equals(item, trimmed, StringComparison.OrdinalIgnoreCase)))
            return true;
        if (Chrome.Any(item => item.Length >= 6 && trimmed.Contains(item, StringComparison.OrdinalIgnoreCase)))
            return true;
        return trimmed is "对话" or "工作" or "更多" or "翻译" or "搜索" or "最小化" or "最大化" or "关闭";
    }

    public static string Normalize(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return "";
        var lines = text.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n')
            .Select(l => l.TrimEnd())
            .ToList();
        while (lines.Count > 0 && lines[0].Length == 0) lines.RemoveAt(0);
        while (lines.Count > 0 && lines[^1].Length == 0) lines.RemoveAt(lines.Count - 1);
        return string.Join('\n', lines).Trim();
    }
}
