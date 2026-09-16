using System.Windows;

namespace LectureCopilot.Windows.Services;

public static class ClipboardService
{
    public static Task SetTextAsync(string text) => Application.Current.Dispatcher.InvokeAsync(() =>
    {
        Retry(() => Clipboard.SetText(text));
    }).Task;

    public static Task<string?> GetTextAsync() => Application.Current.Dispatcher.InvokeAsync(() =>
    {
        try { return Clipboard.ContainsText() ? Clipboard.GetText() : null; }
        catch { return null; }
    }).Task;

    public static async Task<string?> WaitForChangedTextAsync(string sentinel, TimeSpan timeout)
    {
        var start = DateTime.UtcNow;
        while (DateTime.UtcNow - start < timeout)
        {
            await Task.Delay(45);
            var value = await GetTextAsync();
            if (!string.IsNullOrWhiteSpace(value) && value != sentinel) return value.Trim();
        }
        return null;
    }

    private static void Retry(Action action)
    {
        for (var i = 0; i < 8; i++)
        {
            try { action(); return; }
            catch when (i < 7) { Thread.Sleep(25); }
        }
    }
}
