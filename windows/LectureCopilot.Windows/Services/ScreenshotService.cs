using System.Diagnostics;
using System.Windows;
using System.Windows.Media.Imaging;

namespace LectureCopilot.Windows.Services;

public sealed class ScreenshotService
{
    public async Task<bool> CaptureSelectionAsync()
    {
        await Application.Current.Dispatcher.InvokeAsync(() =>
        {
            Clipboard.Clear();
            Process.Start(new ProcessStartInfo("ms-screenclip:") { UseShellExecute = true });
        });
        var started = DateTime.UtcNow;
        while (DateTime.UtcNow - started < TimeSpan.FromSeconds(30))
        {
            await Task.Delay(100);
            var captured = await Application.Current.Dispatcher.InvokeAsync(() =>
            {
                try { return Clipboard.ContainsImage() ? Clipboard.GetImage() : null; }
                catch { return null; }
            });
            if (captured is null) continue;
            await Application.Current.Dispatcher.InvokeAsync(() =>
            {
                var encoder = new PngBitmapEncoder();
                encoder.Frames.Add(BitmapFrame.Create(captured));
                using var output = File.Create(AppPaths.LastCapture);
                encoder.Save(output);
            });
            Logger.Write("Windows screen clipping captured");
            return true;
        }
        return false;
    }

    public async Task<bool> CopyLastCaptureAsync()
    {
        if (!File.Exists(AppPaths.LastCapture)) return false;
        return await Application.Current.Dispatcher.InvokeAsync(() =>
        {
            try
            {
                using var stream = new FileStream(AppPaths.LastCapture, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
                var image = new BitmapImage();
                image.BeginInit();
                image.CacheOption = BitmapCacheOption.OnLoad;
                image.StreamSource = stream;
                image.EndInit();
                image.Freeze();
                Clipboard.SetImage(image);
                return true;
            }
            catch (Exception ex)
            {
                Logger.Write($"Copy screenshot failed: {ex.Message}");
                return false;
            }
        });
    }

    public bool HasFreshCapture(TimeSpan maxAge) => File.Exists(AppPaths.LastCapture)
        && DateTime.UtcNow - File.GetLastWriteTimeUtc(AppPaths.LastCapture) <= maxAge;
}
