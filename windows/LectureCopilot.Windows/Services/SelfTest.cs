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
            sessions.Clear();
            return 0;
        }
        catch (Exception ex)
        {
            Logger.Write($"Self-test failed: {ex}");
            return 99;
        }
    }
}
