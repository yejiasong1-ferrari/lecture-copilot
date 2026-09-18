using System.Drawing;
using System.Drawing.Imaging;
using System.Windows.Media.Imaging;

namespace LectureCopilot.Windows.Services;

internal static class CopyIconMatcher
{
    internal readonly record struct Match(int X, int Y, double Score, double XRatio, double YRatio);

    private static byte[]? _template;
    private static int _templateWidth;
    private static int _templateHeight;

    public static Match? Find(Bitmap windowImage, NativeMethods.Rect window, double? preferredXRatio)
    {
        EnsureTemplate();
        if (_template is null || windowImage.Width < 16 || windowImage.Height < 16) return null;

        using var source = Downsample(windowImage, 720);
        var gray = Grayscale(source);
        var leftRatio = preferredXRatio is { } preferred
            ? Math.Max(0.02, preferred - 0.045)
            : 0.02;
        var rightRatio = preferredXRatio is { } preferredRight
            ? Math.Min(0.52, preferredRight + 0.045)
            : 0.52;
        var searchLeft = (int)(gray.Width * leftRatio);
        var searchTop = (int)(gray.Height * 0.55);
        var searchRight = (int)(gray.Width * rightRatio);
        var searchBottom = (int)(gray.Height * 0.96);

        var bestScore = double.NegativeInfinity;
        var bestX = 0;
        var bestY = 0;
        var bestW = _templateWidth;
        var bestH = _templateHeight;
        foreach (var scale in new[] { 0.20, 0.22, 0.24, 0.25, 0.27, 0.30, 0.34 })
        {
            var tw = Math.Max(12, (int)(_templateWidth * scale));
            var th = Math.Max(10, (int)(_templateHeight * scale));
            if (searchRight - searchLeft <= tw || searchBottom - searchTop <= th) continue;
            var scaled = ScaleBilinear(_template, _templateWidth, _templateHeight, tw, th);
            for (var y = searchTop; y <= searchBottom - th; y++)
            for (var x = searchLeft; x <= searchRight - tw; x++)
            {
                var score = Correlation(gray.Pixels, gray.Width, x, y, scaled, tw, th);
                if (score <= bestScore) continue;
                bestScore = score;
                bestX = x;
                bestY = y;
                bestW = tw;
                bestH = th;
            }
        }

        var px = (bestX + bestW / 2.0) / source.Width;
        var py = (bestY + bestH / 2.0) / source.Height;
        var guided = preferredXRatio is { } guide && Math.Abs(px - guide) <= 0.045;
        var threshold = guided ? 0.52 : 0.70;
        Logger.Write($"Copy icon best score={bestScore:0.000} threshold={threshold:0.00} x={px:0.000} guided={(guided ? "yes" : "no")} at image ({bestX},{bestY})");
        if (bestScore < threshold) return null;

        var width = Math.Max(1, window.Right - window.Left);
        var height = Math.Max(1, window.Bottom - window.Top);
        return new Match(
            window.Left + (int)Math.Round(px * width),
            window.Top + (int)Math.Round(py * height),
            bestScore,
            px,
            py);
    }

    private static Bitmap Downsample(Bitmap source, int maxWidth)
    {
        if (source.Width <= maxWidth) return new Bitmap(source);
        var height = Math.Max(1, (int)Math.Round(source.Height * (maxWidth / (double)source.Width)));
        var dest = new Bitmap(maxWidth, height, PixelFormat.Format32bppArgb);
        using var graphics = Graphics.FromImage(dest);
        graphics.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBilinear;
        graphics.DrawImage(source, 0, 0, maxWidth, height);
        return dest;
    }

    private static void EnsureTemplate()
    {
        if (_template is not null) return;
        try
        {
            var uri = new Uri("pack://application:,,,/Assets/copy-icon-template.png");
            var info = System.Windows.Application.GetResourceStream(uri);
            if (info is null) return;
            var image = new BitmapImage();
            image.BeginInit();
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.StreamSource = info.Stream;
            image.EndInit();
            image.Freeze();
            using var bitmap = ToBitmap(image);
            var gray = Grayscale(bitmap);
            _template = gray.Pixels;
            _templateWidth = gray.Width;
            _templateHeight = gray.Height;
            Logger.Write($"Copy icon template loaded {_templateWidth}x{_templateHeight}");
        }
        catch (Exception ex) { Logger.Write($"Copy icon template missing: {ex.Message}"); }
    }

    private static Bitmap ToBitmap(BitmapSource source)
    {
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(source));
        using var stream = new MemoryStream();
        encoder.Save(stream);
        stream.Position = 0;
        return new Bitmap(stream);
    }

    private static (byte[] Pixels, int Width, int Height) Grayscale(Bitmap bitmap)
    {
        var data = bitmap.LockBits(new Rectangle(0, 0, bitmap.Width, bitmap.Height),
            ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try
        {
            var pixels = new byte[bitmap.Width * bitmap.Height];
            var stride = data.Stride;
            var buffer = new byte[stride * bitmap.Height];
            System.Runtime.InteropServices.Marshal.Copy(data.Scan0, buffer, 0, buffer.Length);
            for (var y = 0; y < bitmap.Height; y++)
            for (var x = 0; x < bitmap.Width; x++)
            {
                var i = y * stride + x * 4;
                pixels[y * bitmap.Width + x] = (byte)((buffer[i] + buffer[i + 1] * 2 + buffer[i + 2]) / 4);
            }
            return (pixels, bitmap.Width, bitmap.Height);
        }
        finally { bitmap.UnlockBits(data); }
    }

    private static byte[] ScaleBilinear(byte[] source, int width, int height, int newWidth, int newHeight)
    {
        var dest = new byte[newWidth * newHeight];
        for (var y = 0; y < newHeight; y++)
        {
            var sourceY = (y + 0.5) * height / newHeight - 0.5;
            var y0 = Math.Max(0, Math.Min(height - 1, (int)Math.Floor(sourceY)));
            var y1 = Math.Min(height - 1, y0 + 1);
            var fy = Math.Max(0, Math.Min(1, sourceY - y0));
            for (var x = 0; x < newWidth; x++)
            {
                var sourceX = (x + 0.5) * width / newWidth - 0.5;
                var x0 = Math.Max(0, Math.Min(width - 1, (int)Math.Floor(sourceX)));
                var x1 = Math.Min(width - 1, x0 + 1);
                var fx = Math.Max(0, Math.Min(1, sourceX - x0));
                var top = source[y0 * width + x0] * (1 - fx) + source[y0 * width + x1] * fx;
                var bottom = source[y1 * width + x0] * (1 - fx) + source[y1 * width + x1] * fx;
                dest[y * newWidth + x] = (byte)Math.Clamp(Math.Round(top * (1 - fy) + bottom * fy), 0, 255);
            }
        }
        return dest;
    }

    private static double Correlation(byte[] image, int imageWidth, int originX, int originY,
        byte[] template, int tw, int th)
    {
        var n = tw * th;
        double sumI = 0, sumT = 0;
        for (var y = 0; y < th; y++)
        for (var x = 0; x < tw; x++)
        {
            sumI += image[(originY + y) * imageWidth + originX + x];
            sumT += template[y * tw + x];
        }
        var meanI = sumI / n;
        var meanT = sumT / n;
        double num = 0, flipped = 0, denI = 0, denT = 0;
        for (var y = 0; y < th; y++)
        {
            var imageRow = (originY + y) * imageWidth + originX;
            var templateRow = y * tw;
            var flippedRow = (th - 1 - y) * tw;
            for (var x = 0; x < tw; x++)
            {
                var di = image[imageRow + x] - meanI;
                var dt = template[templateRow + x] - meanT;
                var df = template[flippedRow + x] - meanT;
                num += di * dt;
                flipped += di * df;
                denI += di * di;
                denT += dt * dt;
            }
        }
        var den = Math.Sqrt(denI * denT);
        if (den <= 1) return -1;
        return Math.Max(Math.Abs(num / den), Math.Abs(flipped / den));
    }
}
