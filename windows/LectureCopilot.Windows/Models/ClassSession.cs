namespace LectureCopilot.Windows.Models;

public sealed class ClassSession
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Title { get; set; } = "Class Session";
    public DateTimeOffset StartTime { get; set; } = DateTimeOffset.Now;
    public DateTimeOffset? EndTime { get; set; }
    public List<ClassInteraction> Interactions { get; set; } = [];
    public string? Summary { get; set; }
    public string? SavePath { get; set; }
    public TimeSpan Duration => (EndTime ?? DateTimeOffset.Now) - StartTime;
    public int RecordedCount => Interactions.Count(x => !string.IsNullOrWhiteSpace(x.Answer));
}

public sealed class ClassInteraction
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public DateTimeOffset Timestamp { get; set; } = DateTimeOffset.Now;
    public string Mode { get; set; } = "";
    public string? ScreenshotRelativePath { get; set; }
    public string Prompt { get; set; } = "";
    public string Answer { get; set; } = "";
}

public enum SessionPhase { Idle, Running, Ended, Summarizing, SummaryReady, Saved }

public sealed record ClassHudSnapshot(
    SessionPhase Phase,
    TimeSpan Elapsed,
    int InteractionCount,
    string Title,
    string StartClock)
{
    public static ClassHudSnapshot Idle { get; } = new(SessionPhase.Idle, TimeSpan.Zero, 0, "Class Session", "");

    public static string DurationText(TimeSpan duration) =>
        duration.TotalHours >= 1 ? duration.ToString(@"h\:mm\:ss") : duration.ToString(@"mm\:ss");
}
