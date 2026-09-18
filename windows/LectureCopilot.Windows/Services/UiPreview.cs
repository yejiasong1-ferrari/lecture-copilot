using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using LectureCopilot.Windows.Models;
using LectureCopilot.Windows.Views;

namespace LectureCopilot.Windows.Services;

internal static class UiPreview
{
    public static async Task VerifyReadAsync(string path)
    {
        var foreground = new ForegroundWindowService();
        foreground.RememberUnlessDoubao();
        var watch = System.Diagnostics.Stopwatch.StartNew();
        try
        {
            var answer = await new DoubaoService().CopyLatestAnswerAsync(new PromptStore().Get("directAnswer"));
            File.WriteAllText(path, $"success={!string.IsNullOrWhiteSpace(answer)}; chars={answer?.Length ?? 0}; elapsedMs={watch.ElapsedMilliseconds}");
        }
        catch (Exception ex) { File.WriteAllText(path, ex.ToString()); }
        finally
        {
            foreground.Restore();
            Application.Current.Shutdown();
        }
    }

    public static void Write(string directory)
    {
        Directory.CreateDirectory(directory);
        var hud = new HudWindow();
        hud.ToggleHidden();
        hud.ShowSession(ClassHudSnapshot.Idle);
        Save(hud, Path.Combine(directory, "hud-compact.png"));
        hud.ShowSession(new(SessionPhase.Running, TimeSpan.FromMinutes(12), 4, "AI Lecture", "20:30"));
        hud.ShowAnswer("答案：B\n\n**原因：**监督学习使用带标签的训练数据，学习输入与输出之间的映射关系。\n\n**其他选项：**\nA 错：无监督学习从无标签数据中发现结构。\nC 错：强化学习通过环境反馈学习策略。\nD 错：人工规则编程不需要训练数据。", CopilotAction.DirectAnswer);
        Save(hud, Path.Combine(directory, "hud-answer.png"));
        hud.ShowAnswer("What are training set, cross validation set and test set used for respectively?\n训练集、交叉验证集和测试集分别用于什么？\n\nTraining set trains model parameters.\n训练集用来训练模型参数。\n\nCross validation set selects hyperparameters.\n交叉验证集用来选择超参数。", CopilotAction.Translate);
        Save(hud, Path.Combine(directory, "hud-translate.png"));
        hud.ShowAnswer("这页讲的是如何把数据分成三部分，让模型既能学习，又能接受公平的检查。**训练集（training set）**用于学习模型参数，就像平时做练习。**交叉验证集（cross validation set）**用于选择超参数，例如比较不同模型的复杂程度。**测试集（test set）**留到最后评估泛化性能，不能参与参数调优，否则测出来的成绩会过于乐观。最该记住的是：用于最后考试的数据，不应该提前拿来调整模型。", CopilotAction.Explain);
        Save(hud, Path.Combine(directory, "hud-explain.png"));
        hud.ShowAnswer("你可以很口语地回答：\nWe use the training set to learn the model parameters and the validation set to tune hyperparameters. The test set tells us how well the final model works on unseen data.", CopilotAction.SayInClass);
        Save(hud, Path.Combine(directory, "hud-speak.png"));
        if (File.Exists(AppPaths.LastAnswer))
        {
            hud.ShowAnswer(File.ReadAllText(AppPaths.LastAnswer), CopilotAction.DirectAnswer);
            Save(hud, Path.Combine(directory, "hud-current-answer.png"));
            ((System.Windows.Controls.ScrollViewer)hud.FindName("DetailScroller")).ScrollToEnd();
            Save(hud, Path.Combine(directory, "hud-current-answer-bottom.png"));
        }
        hud.Close();
        using var tray = new TrayIconService();
        tray.WritePreview(Path.Combine(directory, "control-menu.png"));
    }

    private static void Save(HudWindow hud, string path)
    {
        var content = (FrameworkElement)hud.Content;
        hud.Content = null;
        content.Measure(new Size(hud.Width, hud.Height));
        content.Arrange(new Rect(0, 0, hud.Width, hud.Height));
        content.UpdateLayout();
        var bitmap = new RenderTargetBitmap((int)hud.Width * 2, (int)hud.Height * 2, 192, 192, PixelFormats.Pbgra32);
        bitmap.Render(content);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = File.Create(path);
        encoder.Save(stream);
        hud.Content = content;
    }
}
