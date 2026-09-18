using System.Drawing;
using System.Drawing.Imaging;
using System.Windows;

namespace LectureCopilot.Windows.Services;

internal static class ScreenPixels
{
    public static Bitmap? Capture(Rect rect)
    {
        var x = (int)Math.Floor(rect.Left);
        var y = (int)Math.Floor(rect.Top);
        var width = Math.Max(1, (int)Math.Ceiling(rect.Width));
        var height = Math.Max(1, (int)Math.Ceiling(rect.Height));
        return Capture(x, y, width, height);
    }

    public static Bitmap? Capture(int x, int y, int width, int height)
    {
        if (width < 2 || height < 2) return null;
        try
        {
            var bitmap = new Bitmap(width, height, PixelFormat.Format32bppArgb);
            using var graphics = Graphics.FromImage(bitmap);
            graphics.CopyFromScreen(x, y, 0, 0, bitmap.Size, CopyPixelOperation.SourceCopy);
            return bitmap;
        }
        catch (Exception ex)
        {
            Logger.Write($"Screen capture failed: {ex.Message}");
            return null;
        }
    }

    public static ulong Hash(Bitmap bitmap)
    {
        using var tiny = new Bitmap(16, 8);
        using (var graphics = Graphics.FromImage(tiny))
        {
            graphics.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBilinear;
            graphics.DrawImage(bitmap, 0, 0, tiny.Width, tiny.Height);
        }
        ulong value = 0;
        var bit = 0;
        for (var y = 0; y < tiny.Height; y++)
        for (var x = 0; x < tiny.Width; x++)
        {
            var pixel = tiny.GetPixel(x, y);
            var gray = (pixel.R * 3 + pixel.G * 6 + pixel.B) / 10;
            if (gray >= 128) value |= 1UL << bit;
            bit++;
        }
        return value;
    }

    public static int Hamming(ulong left, ulong right)
    {
        var diff = left ^ right;
        var count = 0;
        while (diff != 0)
        {
            count++;
            diff &= diff - 1;
        }
        return count;
    }
}
