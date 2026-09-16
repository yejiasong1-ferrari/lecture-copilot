using System.Text;
using System.Text.Json;
using LectureCopilot.Windows.Models;

namespace LectureCopilot.Windows.Services;

public sealed class ClassSessionStore
{
    private readonly AppSettings _settings;
    public ClassSession? Session { get; private set; }

    public bool RecordTranslate
    {
        get => _settings.RecordTranslate;
        set { _settings.RecordTranslate = value; _settings.Save(); }
    }

    public ClassSessionStore(AppSettings settings) => _settings = settings;

    public ClassSession Start()
    {
        Session = new ClassSession();
        Persist();
        return Session;
    }

    public void End()
    {
        if (Session is null) return;
        Session.EndTime ??= DateTimeOffset.Now;
        Persist();
    }

    public void Clear() => Session = null;

    public Guid? BeginInteraction(CopilotAction action)
    {
        if (Session is null || Session.EndTime is not null || !ShouldRecord(action)) return null;
        var item = new ClassInteraction { Mode = action.DisplayName(), Prompt = action.DisplayName() };
        var sessionFolder = Folder(Session.Id);
        var shots = Path.Combine(sessionFolder, "shots");
        if (File.Exists(AppPaths.LastCapture))
        {
            Directory.CreateDirectory(shots);
            var relative = Path.Combine("shots", $"{item.Id:N}.png");
            File.Copy(AppPaths.LastCapture, Path.Combine(sessionFolder, relative), true);
            item.ScreenshotRelativePath = relative.Replace('\\', '/');
        }
        Session.Interactions.Add(item);
        Persist();
        return item.Id;
    }

    public void FinishInteraction(Guid id, string answer)
    {
        if (Session is null || string.IsNullOrWhiteSpace(answer) || answer.StartsWith("Still generating")) return;
        var item = Session.Interactions.FirstOrDefault(x => x.Id == id);
        if (item is null) return;
        item.Answer = answer.Trim();
        Persist();
    }

    public void SetSummary(string summary)
    {
        if (Session is null) return;
        Session.Summary = summary.Trim();
        Persist();
    }

    public ClassHudSnapshot Snapshot()
    {
        if (Session is null) return ClassHudSnapshot.Idle;
        var phase = Session.SavePath is not null ? SessionPhase.Saved
            : !string.IsNullOrWhiteSpace(Session.Summary) ? SessionPhase.SummaryReady
            : Session.EndTime is not null ? SessionPhase.Ended
            : SessionPhase.Running;
        return new(phase, Session.Duration, Session.RecordedCount, Session.Title, Session.StartTime.ToString("h:mm tt"));
    }

    public string SummaryPayload()
    {
        if (Session is null) return "No class session.";
        var notes = Session.Interactions.Where(x => !string.IsNullOrWhiteSpace(x.Answer)).ToList();
        var builder = new StringBuilder()
            .AppendLine("Class Session")
            .AppendLine($"Start: {Session.StartTime:h:mm tt}")
            .AppendLine($"Duration: {ClassHudSnapshot.DurationText(Session.Duration)}")
            .AppendLine();
        if (notes.Count == 0) return builder.Append("No Explain / Direct Answer / Say in Class notes were saved this class.").ToString();
        foreach (var note in notes)
            builder.AppendLine($"[{note.Timestamp:HH:mm:ss}] {note.Mode}").AppendLine().AppendLine(note.Answer).AppendLine();
        return builder.ToString().Trim();
    }

    public string WritePreview()
    {
        var path = Path.Combine(AppPaths.SupportDirectory, "class-summary-preview.md");
        File.WriteAllText(path, Markdown(Session?.Title ?? "Class Session", null), Encoding.UTF8);
        return path;
    }

    public void Save(string path)
    {
        if (Session is null) return;
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var shotsFolder = Path.Combine(Path.GetDirectoryName(path)!, Path.GetFileNameWithoutExtension(path) + " shots");
        if (Directory.Exists(shotsFolder)) Directory.Delete(shotsFolder, true);
        File.WriteAllText(path, Markdown(Path.GetFileNameWithoutExtension(path), shotsFolder), Encoding.UTF8);
        Session.SavePath = path;
        Session.Title = Path.GetFileNameWithoutExtension(path);
        Persist();
    }

    public string DefaultSavePath => Path.Combine(AppPaths.NotesDirectory,
        $"Class {(Session?.StartTime ?? DateTimeOffset.Now):yyyy-MM-dd HHmm}.md");

    private string Markdown(string title, string? outputShots)
    {
        if (Session is null) return "";
        var builder = new StringBuilder()
            .AppendLine($"# {title}").AppendLine()
            .AppendLine($"- Start: {Session.StartTime:h:mm tt}")
            .AppendLine($"- End: {(Session.EndTime ?? DateTimeOffset.Now):h:mm tt}")
            .AppendLine($"- Duration: {ClassHudSnapshot.DurationText(Session.Duration)}")
            .AppendLine($"- Notes: {Session.RecordedCount}").AppendLine();
        if (!string.IsNullOrWhiteSpace(Session.Summary)) builder.AppendLine(Session.Summary).AppendLine();
        var notes = Session.Interactions.Where(x => !string.IsNullOrWhiteSpace(x.Answer)).ToList();
        if (notes.Count == 0) return builder.ToString();
        builder.AppendLine("---").AppendLine().AppendLine("## Class Record");
        foreach (var note in notes)
        {
            builder.AppendLine().AppendLine($"### [{note.Timestamp:HH:mm:ss}] {note.Mode}").AppendLine();
            if (outputShots is not null && note.ScreenshotRelativePath is not null)
            {
                var source = Path.Combine(Folder(Session.Id), note.ScreenshotRelativePath.Replace('/', Path.DirectorySeparatorChar));
                if (File.Exists(source))
                {
                    Directory.CreateDirectory(outputShots);
                    var target = Path.Combine(outputShots, Path.GetFileName(source));
                    File.Copy(source, target, true);
                    builder.AppendLine($"![slide]({Path.GetFileName(outputShots)}/{Path.GetFileName(source)})").AppendLine();
                }
            }
            builder.AppendLine(note.Answer);
        }
        return builder.ToString();
    }

    private bool ShouldRecord(CopilotAction action) => action is CopilotAction.Explain or CopilotAction.DirectAnswer or CopilotAction.SayInClass
        || action == CopilotAction.Translate && RecordTranslate;

    private void Persist()
    {
        if (Session is null) return;
        var folder = Folder(Session.Id);
        Directory.CreateDirectory(folder);
        File.WriteAllText(Path.Combine(folder, "session.json"), JsonSerializer.Serialize(Session,
            new JsonSerializerOptions { WriteIndented = true }));
    }

    private static string Folder(Guid id) => Path.Combine(AppPaths.SessionsDirectory, id.ToString());
}
