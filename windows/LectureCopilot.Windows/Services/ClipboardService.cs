using System.Runtime.InteropServices;
using System.Text;
using System.Windows;
using System.Windows.Media.Imaging;

namespace LectureCopilot.Windows.Services;

public static class ClipboardService
{
    public static Task SetTextAsync(string text) => Application.Current.Dispatcher.InvokeAsync(() =>
    {
        var bytes = Encoding.Unicode.GetBytes(text + "\0");
        SetWin32(NativeMethods.CfUnicodeText, bytes);
    }).Task;

    public static Task SetPngFileAsync(string path) => Application.Current.Dispatcher.InvokeAsync(() =>
    {
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        var image = new BitmapImage();
        image.BeginInit();
        image.CacheOption = BitmapCacheOption.OnLoad;
        image.StreamSource = stream;
        image.EndInit();
        image.Freeze();

        var dib = ToDib(image);
        var png = ToPng(image);
        using var bitmap = new System.Drawing.Bitmap(path);
        var bitmapHandle = bitmap.GetHbitmap();
        var drop = ToDropFiles(path);
        try
        {
            OpenExclusive();
            try
            {
                NativeMethods.EmptyClipboard();
                var pngFormat = NativeMethods.RegisterClipboardFormat("PNG");
                if (pngFormat != 0) Put(pngFormat, png);
                Put(NativeMethods.CfDib, dib);
                Put(NativeMethods.CfHdrop, drop);
                if (NativeMethods.SetClipboardData(NativeMethods.CfBitmap, bitmapHandle) != IntPtr.Zero)
                    bitmapHandle = IntPtr.Zero;
            }
            finally { NativeMethods.CloseClipboard(); }
        }
        finally
        {
            if (bitmapHandle != IntPtr.Zero) NativeMethods.DeleteObject(bitmapHandle);
        }
    }).Task;

    public static Task<string?> GetTextAsync() => Application.Current.Dispatcher.InvokeAsync(() =>
    {
        if (!TryOpen()) return null;
        try
        {
            var handle = NativeMethods.GetClipboardData(NativeMethods.CfUnicodeText);
            if (handle == IntPtr.Zero) return null;
            var locked = NativeMethods.GlobalLock(handle);
            if (locked == IntPtr.Zero) return null;
            try { return Marshal.PtrToStringUni(locked); }
            finally { NativeMethods.GlobalUnlock(handle); }
        }
        catch { return null; }
        finally { NativeMethods.CloseClipboard(); }
    }).Task;

    public static async Task<string?> WaitForNewTextAsync(uint sequence, string prompt, TimeSpan timeout)
    {
        var start = DateTime.UtcNow;
        while (DateTime.UtcNow - start < timeout)
        {
            await Task.Delay(40);
            if (NativeMethods.GetClipboardSequenceNumber() == sequence) continue;
            var value = await GetTextAsync();
            if (value is not null && value.StartsWith("lecture-copilot-copy-", StringComparison.Ordinal))
                continue;
            if (string.IsNullOrWhiteSpace(value)) continue;
            var copied = AnswerTextCleaner.Normalize(value);
            var promptNorm = AnswerTextCleaner.Normalize(prompt);
            if (promptNorm.Length > 0 && string.Equals(copied, promptNorm, StringComparison.Ordinal))
            {
                Logger.Write("capture: Copy returned the prompt instead of the answer");
                return null;
            }
            if (AnswerTextCleaner.IsCopiedAnswer(copied, prompt))
                return AnswerTextCleaner.Clean(copied, prompt);
            var cleaned = AnswerTextCleaner.Clean(copied, prompt);
            if (cleaned.Length >= 24 && !AnswerTextCleaner.LooksLikeSidebar(cleaned))
                return cleaned;
            var preview = copied.Replace('\n', '/');
            if (preview.Length > 80) preview = preview[..80];
            Logger.Write($"Copy clipboard ignored ({preview})");
            return null;
        }
        return null;
    }

    public static bool HasImage()
    {
        if (!TryOpen()) return false;
        try
        {
            var png = NativeMethods.RegisterClipboardFormat("PNG");
            return NativeMethods.IsClipboardFormatAvailable(NativeMethods.CfDib)
                   || NativeMethods.IsClipboardFormatAvailable(NativeMethods.CfBitmap)
                   || NativeMethods.IsClipboardFormatAvailable(NativeMethods.CfHdrop)
                   || png != 0 && NativeMethods.IsClipboardFormatAvailable(png);
        }
        catch { return false; }
        finally { NativeMethods.CloseClipboard(); }
    }

    private static void SetWin32(uint format, byte[] bytes)
    {
        OpenExclusive();
        try
        {
            NativeMethods.EmptyClipboard();
            Put(format, bytes);
        }
        finally { NativeMethods.CloseClipboard(); }
    }

    private static void OpenExclusive()
    {
        for (var i = 0; i < 80; i++)
        {
            if (NativeMethods.OpenClipboard(IntPtr.Zero)) return;
            Thread.Sleep(25);
        }
        throw new InvalidOperationException("剪贴板被豆包或其他程序占用，请再试一次。");
    }

    private static bool TryOpen()
    {
        for (var i = 0; i < 12; i++)
        {
            if (NativeMethods.OpenClipboard(IntPtr.Zero)) return true;
            Thread.Sleep(15);
        }
        return false;
    }

    private static void Put(uint format, byte[] bytes)
    {
        var memory = NativeMethods.GlobalAlloc(NativeMethods.GmemMoveable, (UIntPtr)bytes.Length);
        if (memory == IntPtr.Zero) throw new InvalidOperationException("Clipboard alloc failed.");
        var locked = NativeMethods.GlobalLock(memory);
        Marshal.Copy(bytes, 0, locked, bytes.Length);
        NativeMethods.GlobalUnlock(memory);
        if (NativeMethods.SetClipboardData(format, memory) == IntPtr.Zero)
            throw new InvalidOperationException("SetClipboardData failed.");
    }

    private static byte[] ToPng(BitmapSource image)
    {
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(image));
        using var output = new MemoryStream();
        encoder.Save(output);
        return output.ToArray();
    }

    private static byte[] ToDropFiles(string path)
    {
        var full = Path.GetFullPath(path) + "\0\0";
        var chars = Encoding.Unicode.GetBytes(full);
        var header = 20;
        var bytes = new byte[header + chars.Length];
        BitConverter.GetBytes(header).CopyTo(bytes, 0);
        bytes[16] = 1;
        Buffer.BlockCopy(chars, 0, bytes, header, chars.Length);
        return bytes;
    }

    private static byte[] ToDib(BitmapSource image)
    {
        var encoder = new BmpBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(image));
        using var output = new MemoryStream();
        encoder.Save(output);
        var bmp = output.ToArray();
        var dib = new byte[bmp.Length - 14];
        Buffer.BlockCopy(bmp, 14, dib, 0, dib.Length);
        return dib;
    }
}
