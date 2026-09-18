using System.Runtime.InteropServices;

namespace LectureCopilot.Windows.Services;

internal static class SelfTest
{
    public static int Run()
    {
        try
        {
            AppPaths.EnsureDirectories();
            var prompts = new PromptStore();
            if (!prompts.Get("translate").Contains("逐句对照翻译", StringComparison.Ordinal)) return 11;
            if (!prompts.Get("classSummary").Contains("纯文本 Markdown", StringComparison.Ordinal)) return 12;
            var settings = AppSettings.Load();
            var sessions = new ClassSessionStore(settings);
            var session = sessions.Start();
            if (session.Id == Guid.Empty || sessions.Snapshot().Phase != Models.SessionPhase.Running) return 13;
            sessions.End();
            if (sessions.Snapshot().Phase != Models.SessionPhase.Ended) return 14;
            var cleaned = AnswerTextCleaner.Clean("发消息或按住空格说话\n答案：B\n原因：labeled data.", "ignore");
            if (!cleaned.Contains("答案：B", StringComparison.Ordinal)) return 15;
            var residue = "格式，一组空一行：\n假设条件\n规则：";
            if (AnswerTextCleaner.IsUsable(residue, prompts.Get("translate"))) return 21;
            var diff = AnswerTextCleaner.Diff("keep this\nline", "keep this\nline\nnew assistant answer");
            if (!diff.Contains("new assistant answer", StringComparison.Ordinal)) return 16;
            if (string.IsNullOrWhiteSpace(NativeMethods.DpiAwarenessLabel())) return 17;
            if (Marshal.SizeOf<NativeMethods.Input>() != 40) return 18;
            var presentationSample = "## 💡解答\nWhat is the test set for?\n测试集用于什么？\n\n**答案：**评估泛化性能。\n原因：它不参与训练。\nA 错：x = 0.25，不能丢失数字或公式。\n\n未知格式也应完整保留。";
            foreach (var mode in new[] { Models.CopilotAction.Translate, Models.CopilotAction.Explain,
                         Models.CopilotAction.DirectAnswer, Models.CopilotAction.SayInClass })
            {
                var panel = new System.Windows.Controls.StackPanel();
                Views.AnswerView.Render(panel, presentationSample, mode);
                var expected = System.Text.RegularExpressions.Regex.Replace(presentationSample, @"(?m)^#{1,6}\s+", "").Replace("**", "");
                if (Compact(RenderedText(panel)) != Compact(expected)) return 22;
            }
            var document = "侧栏\uFFFC\n模式：Direct Answer\n答案：B\n共用时 14 秒\n答案：B\n原因：带标签数据。\n其他选项：\nA 错：无标签数据。\n\uFFFC\n本地电脑";
            var extracted = AnswerTextCleaner.Clean(document, prompts.Get("directAnswer"));
            if (extracted != "答案：B\n原因：带标签数据。\n其他选项：\nA 错：无标签数据。") return 19;
            var daPrompt = prompts.Get("directAnswer");
            var promptHud = "答案：B\n原因：一句话说明为什么对。\n其他选项：\n答案：先给一句话结论。\n原因：一句话说明为什么。";
            if (AnswerTextCleaner.IsUsable(promptHud, daPrompt)) return 23;
            if (AnswerTextCleaner.IsCopiedAnswer(promptHud, daPrompt)) return 24;
            var english = "答案：Regularization adds controlled extra penalty to model complexity to prevent overfitting.\n原因：It discourages the model from learning noise in training data.";
            if (!AnswerTextCleaner.IsCopiedAnswer(english, daPrompt)) return 25;
            if (!AnswerTextCleaner.IsUsable(english, daPrompt)) return 26;
            var speakPrompt = prompts.Get("sayInClass");
            var speakCopy = "## 💡解答\n你可以很口语地回答：\nRegularization adds a small penalty to model weights. It stops the model from memorizing noise.";
            if (!AnswerTextCleaner.IsCopiedAnswer(speakCopy, speakPrompt)) return 27;
            var speakCleaned = AnswerTextCleaner.Clean(speakCopy, speakPrompt);
            if (!speakCleaned.Contains("Regularization", StringComparison.Ordinal)) return 28;
            if (speakCleaned.Contains("💡解答", StringComparison.Ordinal)) return 29;
            try { Directory.Delete(Path.Combine(AppPaths.SessionsDirectory, session.Id.ToString()), true); } catch { }
            return 0;
        }
        catch (Exception ex)
        {
            Logger.Write($"Self-test failed: {ex}");
            return 99;
        }
    }

    private static string Compact(string text) => System.Text.RegularExpressions.Regex.Replace(text, @"\s+", "");

    private static string RenderedText(System.Windows.UIElement element) => element switch
    {
        System.Windows.Controls.TextBlock text => string.Concat(text.Inlines.OfType<System.Windows.Documents.Run>().Select(run => run.Text)),
        System.Windows.Controls.Border border when border.Child is not null => RenderedText(border.Child),
        System.Windows.Controls.Panel panel => string.Concat(panel.Children.Cast<System.Windows.UIElement>().Select(RenderedText)),
        _ => ""
    };
}
