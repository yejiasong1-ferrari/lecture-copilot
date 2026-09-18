using System.Text.Json;

namespace LectureCopilot.Windows.Services;

public sealed class AppSettings
{
    public bool ClassModeEnabled { get; set; } = true;
    public bool RecordTranslate { get; set; }
    public bool ReturnToPreviousApp { get; set; } = true;

    public static AppSettings Load()
    {
        try
        {
            return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(AppPaths.Settings)) ?? new AppSettings();
        }
        catch { return new AppSettings(); }
    }

    public void Save() => File.WriteAllText(AppPaths.Settings,
        JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
}
