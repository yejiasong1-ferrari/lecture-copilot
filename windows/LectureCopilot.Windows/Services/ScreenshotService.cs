using System.Windows;
using LectureCopilot.Windows.Views;

namespace LectureCopilot.Windows.Services;

public sealed class ScreenshotService
{
    public async Task<bool> CaptureSelectionAsync(Action? revealTarget = null)
    {
        var hidden = Array.Empty<Window>();
        await Application.Current.Dispatcher.InvokeAsync(() => hidden = HideLectureWindows());
        await Task.Delay(40);
        try
        {
            return await Application.Current.Dispatcher.InvokeAsync(() =>
            {
                var overlay = new SelectionOverlayWindow { RevealTarget = revealTarget };
                var accepted = overlay.ShowDialog() == true;
                if (!accepted || overlay.CapturedPng is null || overlay.CapturedPng.Length == 0)
                    return false;
                File.WriteAllBytes(AppPaths.LastCapture, overlay.CapturedPng);
                Logger.Write($"Region screenshot captured ({overlay.CapturedPng.Length} bytes)");
                return true;
            }).Task;
        }
        catch (Exception ex)
        {
            Logger.Write($"Region screenshot failed: {ex}");
            return false;
        }
        finally
        {
            await Application.Current.Dispatcher.InvokeAsync(() =>
            {
                foreach (var window in hidden)
                {
                    if (window is HudWindow) continue;
                    try { window.Show(); } catch { }
                }
            });
        }
    }

    public async Task<bool> CopyLastCaptureAsync()
    {
        if (!File.Exists(AppPaths.LastCapture)) return false;
        try
        {
            await ClipboardService.SetPngFileAsync(AppPaths.LastCapture);
            return true;
        }
        catch (Exception ex)
        {
            Logger.Write($"Copy screenshot failed: {ex.Message}");
            return false;
        }
    }

    public bool HasFreshCapture(TimeSpan maxAge) => File.Exists(AppPaths.LastCapture)
        && DateTime.UtcNow - File.GetLastWriteTimeUtc(AppPaths.LastCapture) <= maxAge;

    private static Window[] HideLectureWindows()
    {
        var hidden = new List<Window>();
        foreach (Window window in Application.Current.Windows)
        {
            if (!window.IsVisible || window is SelectionOverlayWindow) continue;
            window.Hide();
            hidden.Add(window);
        }
        return hidden.ToArray();
    }
}
