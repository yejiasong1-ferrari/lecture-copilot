using System.Text.Json;

namespace LectureCopilot.Windows.Services;

public sealed class PromptStore
{
    private readonly Dictionary<string, string> _defaults = new()
    {
        ["translate"] = """
        这是一张新截图。忽略之前所有对话和其他幻灯片。

        只做逐句对照翻译。不要解释。
        只翻译这张图里实际看得见的文字。图里没有的一句都不要写。
        不要扩写成讲义，不要补公式、例题、定义或下一页内容。
        如果图里只有标题，就只输出标题对照，到此结束。

        先翻标题和正文 bullet，最后翻底部注释。不要把示意图箭头标签做成单词表。

        格式，一组空一行：
        Assumptions
        假设条件

        No back orders or partial shipments
        不允许延期交货，也不允许部分发货。

        规则：
        - 一句英文，下一行中文。长句按句拆开。
        - 术语写成 中文（English），例如 主键（primary key）、SALES（销售）表。
        - 禁止输出 PRIMARY KEY / FOREIGN KEY / PARENT TABLE / BOOKS table 这种单词表。
        - 不要翻译 ISBN、书名、作者、Cengage。
        """,
        ["explain"] = """
        用一段中文把这页讲懂。像同学在旁边小声说。不要逐句翻译，不要列小标题。

        只输出一段话，大约 4 到 8 句。说清这页在讲什么、图或例子里谁和谁怎么连、最该记住的规则。
        术语写成 中文（English），表名和字段保留英文。
        不要写「核心：」「结构：」「关系：」。不要推荐问题。
        """,
        ["directAnswer"] = """
        模式：Direct Answer
        任务：直接回答截图里的题目。不要复述题干，不要把全部选项再抄一遍，不要编新题。

        如果是选择题，必须按这个格式：
        答案：B
        原因：一句话说明为什么对。
        其他选项：
        A 错：一句话
        C 错：一句话
        D 错：一句话

        如果是问答题，必须按这个格式：
        答案：先给一句话结论。
        原因：一句话说明为什么。

        术语保留英文，必要时写成 中文（English）。
        不要写“当然/可以/来一道”，不要表格，不要推荐问题。
        """,
        ["sayInClass"] = """
        模式：Say in Class
        任务：给一句我能在研究生课堂上直接说出口的英文。

        只按这个格式输出：
        你可以很口语地回答：
        1 到 2 句自然口语英文。像学生在说话，不要像背课文。

        要求：
        - 英文简单清楚，直接说结论和理由。
        - 可以不用 I think / I would say 开头。
        - 中文只保留“你可以很口语地回答：”这一行，下面必须是英文。
        - 不要复述题干，不要列出选项，不要写 essay，不要推荐问题。
        """,
        ["classSummary"] = """
        根据下面「课堂结构化记录」写一份复习笔记。只使用记录里出现的内容，不要编造没出现过的知识点。

        非常重要：
        - 只在当前聊天气泡里输出纯文本 Markdown。
        - 禁止生成文档、云文档、画布、大纲卡片、思维导图。
        - 不要弹出右侧文档页。答案必须可以直接点消息上的复制。
        - 不要用表格，不要用 [ ] 任务清单。

        严格按这个纯文本格式，方便整段复制：

        Class Summary
        两段话：这节课主要在问什么、卡住的点是什么。

        Key Concepts
        - 概念：一句话

        Important Questions
        - 题目：答案

        Things I Got Wrong
        - 没有就写 None

        Useful In-Class Answers
        - 课堂上能开口说的句子

        Review Checklist
        - 可复习的要点（普通短横线，不要复选框）

        用中文写说明，术语保留英文。每个小标题单独一行，下面用短横线列表。
        """
    };

    private Dictionary<string, string>? _cache;

    public string Get(string key)
    {
        _cache ??= Load();
        return _cache.TryGetValue(key, out var value) ? value : "";
    }

    public string EnsureFile()
    {
        if (!File.Exists(AppPaths.Prompts))
            Write(_defaults);
        return AppPaths.Prompts;
    }

    private Dictionary<string, string> Load()
    {
        EnsureFile();
        try
        {
            var custom = JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(AppPaths.Prompts)) ?? [];
            var merged = new Dictionary<string, string>(_defaults);
            foreach (var item in custom) merged[item.Key] = item.Value;
            return merged;
        }
        catch
        {
            return new Dictionary<string, string>(_defaults);
        }
    }

    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };
    private void Write(Dictionary<string, string> prompts) =>
        File.WriteAllText(AppPaths.Prompts, JsonSerializer.Serialize(prompts, JsonOptions));
}
