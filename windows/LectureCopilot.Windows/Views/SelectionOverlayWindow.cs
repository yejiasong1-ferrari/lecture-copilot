using System.Drawing;
using System.Drawing.Imaging;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using LectureCopilot.Windows.Services;
using MediaBrushes = System.Windows.Media.Brushes;
using MediaColor = System.Windows.Media.Color;
using MediaImage = System.Windows.Controls.Image;
using Point = System.Windows.Point;

namespace LectureCopilot.Windows.Views;

internal sealed class SelectionOverlayWindow : Window
{
    private readonly BitmapSource _screen;
    private readonly Border _rubber;
    private readonly System.Drawing.Rectangle _virtualScreen;
    private Point _origin;
    private bool _dragging;

    public byte[]? CapturedPng { get; private set; }
    public Action? RevealTarget { get; set; }

    public SelectionOverlayWindow()
    {
        _virtualScreen = System.Windows.Forms.SystemInformation.VirtualScreen;
        _screen = CaptureVirtualScreen(_virtualScreen);

        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.Manual;
        AllowsTransparency = false;
        Background = MediaBrushes.Black;
        Topmost = true;
        ShowInTaskbar = false;
        Cursor = Cursors.Cross;
        Focusable = true;
        ShowActivated = true;

        var image = new MediaImage
        {
            Source = _screen,
            Stretch = Stretch.Fill,
            SnapsToDevicePixels = true
        };
        var dim = new Border
        {
            Background = new SolidColorBrush(MediaColor.FromArgb(88, 8, 12, 20)),
            IsHitTestVisible = false
        };
        _rubber = new Border
        {
            BorderBrush = new SolidColorBrush(MediaColor.FromRgb(110, 210, 255)),
            BorderThickness = new Thickness(2),
            Background = new SolidColorBrush(MediaColor.FromArgb(36, 110, 210, 255)),
            Visibility = Visibility.Collapsed,
            IsHitTestVisible = false
        };
        var hint = new TextBlock
        {
            Text = "拖选题目区域 · Esc 取消",
            Foreground = MediaBrushes.White,
            FontSize = 15,
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(20, 18, 0, 0),
            IsHitTestVisible = false
        };
        var canvas = new Canvas { Background = MediaBrushes.Transparent };
        canvas.Children.Add(_rubber);
        canvas.Children.Add(hint);

        var root = new Grid();
        root.Children.Add(image);
        root.Children.Add(dim);
        root.Children.Add(canvas);
        Content = root;

        SourceInitialized += (_, _) => NativeMethods.SetWindowPos(
            new WindowInteropHelper(this).Handle,
            NativeMethods.HwndTopmost,
            _virtualScreen.Left, _virtualScreen.Top, _virtualScreen.Width, _virtualScreen.Height,
            NativeMethods.SwpShowWindow);
        Loaded += (_, _) => Activate();
        PreviewKeyDown += HandleKey;
        MouseLeftButtonDown += HandleDown;
        MouseMove += HandleMove;
        MouseLeftButtonUp += HandleUp;
        MouseRightButtonUp += (_, _) => Cancel();
    }

    private void HandleKey(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Escape) return;
        e.Handled = true;
        Cancel();
    }

    private void HandleDown(object sender, MouseButtonEventArgs e)
    {
        _origin = e.GetPosition(this);
        _dragging = true;
        CaptureMouse();
        _rubber.Visibility = Visibility.Visible;
        PlaceRubber(_origin, _origin);
    }

    private void HandleMove(object sender, MouseEventArgs e)
    {
        if (!_dragging) return;
        PlaceRubber(_origin, e.GetPosition(this));
    }

    private void HandleUp(object sender, MouseButtonEventArgs e)
    {
        if (!_dragging) return;
        _dragging = false;
        if (IsMouseCaptured) ReleaseMouseCapture();
        var end = e.GetPosition(this);
        var rect = PixelRect(_origin, end);
        if (rect.Width < 12 || rect.Height < 12)
        {
            Cancel();
            return;
        }

        CapturedPng = EncodePng(new CroppedBitmap(_screen, rect));
        RevealTarget?.Invoke();
        DialogResult = true;
    }

    private void Cancel()
    {
        CapturedPng = null;
        if (_dragging && IsMouseCaptured) ReleaseMouseCapture();
        try { DialogResult = false; }
        catch { Close(); }
    }

    private void PlaceRubber(Point a, Point b)
    {
        var x = Math.Min(a.X, b.X);
        var y = Math.Min(a.Y, b.Y);
        Canvas.SetLeft(_rubber, x);
        Canvas.SetTop(_rubber, y);
        _rubber.Width = Math.Abs(a.X - b.X);
        _rubber.Height = Math.Abs(a.Y - b.Y);
    }

    private Int32Rect PixelRect(Point a, Point b)
    {
        var width = Math.Max(ActualWidth, 1);
        var height = Math.Max(ActualHeight, 1);
        var left = (int)Math.Floor(Math.Min(a.X, b.X) / width * _screen.PixelWidth);
        var top = (int)Math.Floor(Math.Min(a.Y, b.Y) / height * _screen.PixelHeight);
        var right = (int)Math.Ceiling(Math.Max(a.X, b.X) / width * _screen.PixelWidth);
        var bottom = (int)Math.Ceiling(Math.Max(a.Y, b.Y) / height * _screen.PixelHeight);
        left = Math.Clamp(left, 0, _screen.PixelWidth - 1);
        top = Math.Clamp(top, 0, _screen.PixelHeight - 1);
        right = Math.Clamp(right, left + 1, _screen.PixelWidth);
        bottom = Math.Clamp(bottom, top + 1, _screen.PixelHeight);
        return new Int32Rect(left, top, right - left, bottom - top);
    }

    private static byte[] EncodePng(BitmapSource image)
    {
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(image));
        using var stream = new MemoryStream();
        encoder.Save(stream);
        return stream.ToArray();
    }

    private static BitmapSource CaptureVirtualScreen(System.Drawing.Rectangle screen)
    {
        using var bitmap = new Bitmap(screen.Width, screen.Height, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        using (var graphics = Graphics.FromImage(bitmap))
            graphics.CopyFromScreen(screen.Left, screen.Top, 0, 0, bitmap.Size, CopyPixelOperation.SourceCopy);
        var handle = bitmap.GetHbitmap();
        try
        {
            var source = Imaging.CreateBitmapSourceFromHBitmap(
                handle, IntPtr.Zero, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
            source.Freeze();
            return source;
        }
        finally { NativeMethods.DeleteObject(handle); }
    }
}
