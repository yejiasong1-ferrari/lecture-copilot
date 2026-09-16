namespace LectureCopilot.Windows.Services;

public static class AppPaths
{
    public static string SupportDirectory { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Lecture Copilot");
    public static string SessionsDirectory => Path.Combine(SupportDirectory, "sessions");
    public static string NotesDirectory { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "Lecture Copilot");
    public static string LastCapture => Path.Combine(SupportDirectory, "last-capture.png");
    public static string LastAnswer => Path.Combine(SupportDirectory, "last-answer.txt");
    public static string Prompts => Path.Combine(SupportDirectory, "prompts.json");
    public static string Settings => Path.Combine(SupportDirectory, "settings.json");
    public static string DebugLog => Path.Combine(SupportDirectory, "debug.log");

    public static void EnsureDirectories()
    {
        Directory.CreateDirectory(SupportDirectory);
        Directory.CreateDirectory(SessionsDirectory);
        Directory.CreateDirectory(NotesDirectory);
    }
}
