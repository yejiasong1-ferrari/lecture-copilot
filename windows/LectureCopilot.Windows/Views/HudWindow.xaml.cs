using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using System.Windows.Documents;
using System.Text.RegularExpressions;
using LectureCopilot.Windows.Models;
using LectureCopilot.Windows.Services;

namespace LectureCopilot.Windows.Views;

public partial class HudWindow : Window
{
    private const double Chrome = 36;
    private const double CompactHeight = 82;
    private const double CompactMinWidth = 320;
    private const double CompactMaxWidth = 460;
    private const double ExpandedWidth = 480;
    private const double ExpandedHeight = 380;
    private static readonly BrushConverter BrushBox = new();

    private readonly DispatcherTimer _collapseTimer;
    private bool _expanded;
    private bool _hiddenByUser;
    private bool _loading;
    private bool _doubaoReady = true;
    private bool _doubaoLaunching;
    private ClassHudSnapshot _snapshot = ClassHudSnapshot.Idle;
    private string? _detail;
    private CopilotAction? _answerAction;

    public event Action? StartClass;
    public event Action? EndClass;
    public event Action? SummarizeClass;
    public event Action? ReviewNote;
    public event Action? SaveNote;
    public event Action? NewClass;
    public event Action? OpenDoubao;

    public HudWindow()
    {
        InitializeComponent();
        _collapseTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) };
        _collapseTimer.Tick += (_, _) => { _collapseTimer.Stop(); Collapse(); };
        MouseEnter += (_, _) => { _collapseTimer.Stop(); Expand(); };
        MouseLeave += (_, _) => _collapseTimer.Start();
        MouseLeftButtonDown += HandleDrag;
        SourceInitialized += (_, _) => ApplyToolWindowChrome();
        Loaded += (_, _) =>
        {
            Render();
            PositionAtTopRight();
        };
    }

    public bool HiddenByUser => _hiddenByUser;

    public void ToggleHidden()
    {
        _hiddenByUser = !_hiddenByUser;
        if (_hiddenByUser) Hide();
        else { Render(); ShowWithoutActivation(); }
    }

    public void Reveal()
    {
        _hiddenByUser = false;
        Render();
        ShowWithoutActivation();
    }

    public void ShowSession(ClassHudSnapshot snapshot, string? detail = null)
    {
        _snapshot = snapshot;
        _detail = detail;
        _answerAction = null;
        _loading = false;
        Render();
        if (!_hiddenByUser) ShowWithoutActivation();
    }

    public void ShowLoading(string text, CopilotAction action)
    {
        _answerAction = action;
        _detail = text;
        _loading = true;
        Render();
        if (!_hiddenByUser) ShowWithoutActivation();
    }

    public void ShowAnswer(string text, CopilotAction action)
    {
        _answerAction = action;
        _detail = text;
        _loading = false;
        DetailScroller.ScrollToTop();
        Render();
        Expand();
        if (!_hiddenByUser) ShowWithoutActivation();
    }

    public void Tick(ClassHudSnapshot snapshot)
    {
        _snapshot = snapshot;
        if (_answerAction is not null)
        {
            SetEyebrow($"CLASS · {ClassHudSnapshot.DurationText(_snapshot.Elapsed)}");
            return;
        }
        if (_snapshot.Phase == SessionPhase.Running)
        {
            SetTitle(ClassHudSnapshot.DurationText(_snapshot.Elapsed));
            ModeLabel.Text = NoteChipTitle(_snapshot.InteractionCount);
        }
    }

    public void SetDoubaoReady(bool ready, bool launching = false)
    {
        _doubaoReady = ready;
        _doubaoLaunching = launching;
        if (_answerAction is null) Render();
    }

    private void Render()
    {
        FooterActions.Children.Clear();
        FooterActions.Visibility = Visibility.Collapsed;
        SessionChip.Visibility = Visibility.Collapsed;
        ModeChip.Visibility = Visibility.Collapsed;

        var kind = CurrentKind();
        var accent = AccentColor(kind, _answerAction);
        ApplyAccent(accent, kind);

        if (_answerAction is { } action)
        {
            var loading = kind is "loading" or "summary-loading";
            SetEyebrow(_snapshot.Phase == SessionPhase.Running
                ? $"CLASS · {ClassHudSnapshot.DurationText(_snapshot.Elapsed)}"
                : "LECTURE COPILOT");
            SetTitle(loading && kind != "summary-loading" ? "Working" : kind == "summary-loading" ? "Summarizing" : "Answer");
            ShowModeChip(action.ChipTitle(), accent);
            SetDetail(_detail ?? "Working…");
            AddPersistentSessionAction();
            FitFrame();
            return;
        }

        SetDetail(_detail ?? DetailForPhase());
        switch (_snapshot.Phase)
        {
            case SessionPhase.Idle:
                SetEyebrow("LECTURE COPILOT");
                SetTitle("Start Class");
                ShowSessionChip("Start Class", "#2B6BDBC0", "#8C6BDBC0");
                ShowCompanionChip();
                break;
            case SessionPhase.Running:
                SetEyebrow("CLASS SESSION");
                SetTitle(ClassHudSnapshot.DurationText(_snapshot.Elapsed));
                ShowModeChip(NoteChipTitle(_snapshot.InteractionCount), accent);
                ShowSessionChip("End", "#3DFF735B", "#8CFF735B");
                break;
            case SessionPhase.Ended:
                SetEyebrow("CLASS SESSION");
                SetTitle("Class Ended");
                ShowSessionChip("Summary", "#3DF2C761", "#8CF2C761");
                AddFooter("New", "#D26F3B", NewClass);
                break;
            case SessionPhase.Summarizing:
                SetEyebrow("CLASS SESSION");
                SetTitle("Summarizing");
                ShowModeChip("Wait", AccentColor("loading", null));
                break;
            case SessionPhase.SummaryReady:
            case SessionPhase.Saved:
                SetEyebrow("CLASS SESSION");
                SetTitle(_snapshot.Phase == SessionPhase.Saved ? "Saved" : "Class Summary");
                ShowModeChip(_snapshot.Phase == SessionPhase.Saved ? "Saved" : "Ready", accent);
                ShowSessionChip("Save", "#2B69D4A5", "#8C69D4A5");
                AddFooter("Review Note", "#367CC9", ReviewNote);
                AddFooter("New", "#D26F3B", NewClass);
                break;
        }

        FitFrame();
    }

    private void ShowCompanionChip()
    {
        if (_doubaoLaunching)
        {
            ShowModeChip("Opening…", Color.FromRgb(255, 173, 82));
            return;
        }
        if (_doubaoReady) return;
        ShowModeChip("Open Doubao", Color.FromRgb(255, 173, 82));
        ModeChip.Cursor = Cursors.Hand;
    }

    private void ShowModeChip(string text, Color accent)
    {
        ModeLabel.Text = text;
        ModeChip.Visibility = Visibility.Visible;
        ModeChip.Background = Soft(accent, 0x28);
        ModeChip.BorderBrush = Soft(accent, 0x78);
        ModeLabel.Foreground = Blend(accent, Colors.White, 0.22);
        ModeChip.Cursor = Cursors.Arrow;
    }

    private void ShowSessionChip(string text, string background, string border)
    {
        SessionChip.Content = text;
        SessionChip.Background = Brush(background);
        SessionChip.BorderBrush = Brush(border);
        SessionChip.Visibility = Visibility.Visible;
    }

    private void AddPersistentSessionAction()
    {
        if (_snapshot.Phase == SessionPhase.Idle)
            ShowSessionChip("Start Class", "#2B6BDBC0", "#8C6BDBC0");
        else if (_snapshot.Phase == SessionPhase.Running)
            ShowSessionChip("End", "#3DFF735B", "#8CFF735B");
        else if (_snapshot.Phase == SessionPhase.Ended)
            ShowSessionChip("Summary", "#3DF2C761", "#8CF2C761");
        else if (_snapshot.Phase is SessionPhase.SummaryReady or SessionPhase.Saved)
            ShowSessionChip("Save", "#2B69D4A5", "#8C69D4A5");
    }

    private string DetailForPhase() => _snapshot.Phase switch
    {
        SessionPhase.Idle => _doubaoReady
            ? "开始上课后，Explain / Direct Answer / Say in Class 会自动记进这节课。\n\nTranslate 默认不记，可在托盘菜单里打开。"
            : "豆包还没有打开。先启动并登录豆包 Windows 客户端，再按 Shift + 方向键。",
        SessionPhase.Running => $"{_snapshot.Title}\nStart: {_snapshot.StartClock}\nDuration: {ClassHudSnapshot.DurationText(_snapshot.Elapsed)}\n\n{_snapshot.InteractionCount} interactions saved",
        SessionPhase.Ended => "这节课已结束。\n\n点 Summary 才发给豆包做总结。\n不想总结就点 New 开新课。",
        SessionPhase.Summarizing => "正在把这节课的记录发给豆包做总结。生成完成后按 Shift + Return。",
        SessionPhase.SummaryReady => _detail ?? "Class summary ready",
        SessionPhase.Saved => _detail ?? "笔记已保存。",
        _ => ""
    };

    private static string NoteChipTitle(int count) => count == 1 ? "1 Note" : $"{count} Notes";

    private void SetDetail(string text)
    {
        AnswerView.Render(DetailContent, text, _loading ? null : _answerAction);
    }

    private string CurrentKind()
    {
        if (_answerAction is not null)
        {
            if (_loading && _answerAction == CopilotAction.ClassSummary) return "summary-loading";
            if (_loading) return "loading";
            return _answerAction == CopilotAction.ClassSummary ? "summary" : "answer";
        }
        return _snapshot.Phase switch
        {
            SessionPhase.Summarizing => "summary-loading",
            SessionPhase.SummaryReady or SessionPhase.Saved => "summary",
            _ => "session"
        };
    }

    private void ApplyAccent(Color accent, string kind)
    {
        AccentLine.Background = new SolidColorBrush(Color.FromArgb(0xE0, accent.R, accent.G, accent.B));
        AccentGlow.Background = new LinearGradientBrush(
            Color.FromArgb(0x00, accent.R, accent.G, accent.B),
            Color.FromArgb(0x00, accent.R, accent.G, accent.B),
            0)
        {
            GradientStops =
            {
                new GradientStop(Color.FromArgb(0x00, accent.R, accent.G, accent.B), 0),
                new GradientStop(Color.FromArgb(0xB8, accent.R, accent.G, accent.B), 0.5),
                new GradientStop(Color.FromArgb(0x00, accent.R, accent.G, accent.B), 1)
            }
        };
        AccentWash.Background = new RadialGradientBrush(Color.FromArgb(0x73, accent.R, accent.G, accent.B), Colors.Transparent)
        {
            Center = new Point(0.16, 0),
            GradientOrigin = new Point(0.1, -0.08),
            RadiusX = 0.9,
            RadiusY = 0.72
        };
        StatusDot.Background = new SolidColorBrush(accent);
        StatusDotGlow.Background = Soft(accent, 0x88);
        var branded = kind is "session" or "summary" or "summary-loading";
        if (branded)
        {
            IconBadge.BorderBrush = Brush("#73FFFFFF");
        }
        else
        {
            IconBadge.BorderBrush = Soft(accent, 0x66);
        }
        SetDotPulsing(kind is "loading" or "summary-loading" || _snapshot.Phase == SessionPhase.Running || _doubaoLaunching);
    }

    private static Color AccentColor(string kind, CopilotAction? action)
    {
        if (kind is "loading" or "summary-loading") return Color.FromRgb(255, 173, 82);
        if (kind == "session") return Color.FromRgb(133, 184, 255);
        return action switch
        {
            CopilotAction.Translate => Color.FromRgb(107, 219, 176),
            CopilotAction.Explain => Color.FromRgb(133, 184, 255),
            CopilotAction.DirectAnswer => Color.FromRgb(255, 158, 82),
            CopilotAction.SayInClass => Color.FromRgb(199, 158, 255),
            CopilotAction.ClassSummary => Color.FromRgb(242, 199, 97),
            _ => Color.FromRgb(107, 219, 176)
        };
    }

    private void AddFooter(string text, string background, Action? action)
    {
        var button = new System.Windows.Controls.Button
        {
            Content = text,
            Background = Brush(background),
            BorderBrush = Brush("#2EFFFFFF"),
            Style = (Style)FindResource("Pill")
        };
        button.Click += (_, _) => action?.Invoke();
        FooterActions.Children.Add(button);
    }

    private void Expand()
    {
        if (_expanded) return;
        _expanded = true;
        Hairline.Visibility = Visibility.Visible;
        DetailWell.Visibility = Visibility.Visible;
        FooterActions.Visibility = FooterActions.Children.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        ApplyFrame(ExpandedWidth, ExpandedCardHeight());
    }

    private void Collapse()
    {
        if (!_expanded) return;
        _expanded = false;
        Hairline.Visibility = Visibility.Collapsed;
        DetailWell.Visibility = Visibility.Collapsed;
        FooterActions.Visibility = Visibility.Collapsed;
        ApplyFrame(CollapsedCardWidth(), CompactHeight);
    }

    private void FitFrame()
    {
        if (_expanded)
        {
            FooterActions.Visibility = FooterActions.Children.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
            ApplyFrame(ExpandedWidth, ExpandedCardHeight());
        }
        else ApplyFrame(CollapsedCardWidth(), CompactHeight);
    }

    private double ExpandedCardHeight()
    {
        DetailContent.Measure(new Size(ExpandedWidth - 88, double.PositiveInfinity));
        var footer = FooterActions.Children.Count > 0 ? 48 : 0;
        return Math.Clamp(126 + DetailContent.DesiredSize.Height + footer, 180, ExpandedHeight);
    }

    private double CollapsedCardWidth()
    {
        Eyebrow.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        TitleText.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        ModeChip.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        SessionChip.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        var text = Math.Max(Eyebrow.DesiredSize.Width, TitleText.DesiredSize.Width);
        var mode = ModeChip.Visibility == Visibility.Visible ? ModeChip.DesiredSize.Width + 7 : 0;
        var session = SessionChip.Visibility == Visibility.Visible ? SessionChip.DesiredSize.Width + 7 : 0;
        var fitted = 16 + 40 + 12 + text + 10 + mode + session + 28 + 12 + 16;
        return Math.Clamp(Math.Ceiling(fitted), CompactMinWidth, CompactMaxWidth);
    }

    private void ApplyFrame(double cardWidth, double cardHeight)
    {
        var nextWidth = cardWidth + Chrome;
        var nextHeight = cardHeight + Chrome;
        var right = Left + Width;
        var area = SystemParameters.WorkArea;
        Width = Math.Min(nextWidth, area.Width);
        Height = Math.Min(nextHeight, area.Height);
        if (IsLoaded)
        {
            Left = Math.Clamp(right - Width, area.Left, Math.Max(area.Left, area.Right - Width));
            Top = Math.Clamp(Top, area.Top, Math.Max(area.Top, area.Bottom - Height));
        }
    }

    private void PositionAtTopRight()
    {
        var area = SystemParameters.WorkArea;
        Left = area.Right - Width - 2;
        Top = area.Top + 8;
    }

    private void ShowWithoutActivation()
    {
        Show();
        Topmost = true;
    }

    private void ApplyToolWindowChrome()
    {
        var hwnd = new WindowInteropHelper(this).Handle;
        var ex = NativeMethods.GetWindowLongPtr(hwnd, NativeMethods.GwlExStyle);
        NativeMethods.SetWindowLongPtr(hwnd, NativeMethods.GwlExStyle,
            ex | (IntPtr)(NativeMethods.WsExToolWindow | NativeMethods.WsExNoActivate));
    }

    private void HandleDrag(object sender, MouseButtonEventArgs e)
    {
        if (e.ButtonState != MouseButtonState.Pressed) return;
        if (IsInsideInteractiveChrome(e.OriginalSource as DependencyObject)) return;
        try { DragMove(); } catch { }
    }

    private bool IsInsideInteractiveChrome(DependencyObject? node)
    {
        while (node is not null)
        {
            if (node is System.Windows.Controls.Button || ReferenceEquals(node, ModeChip) || ReferenceEquals(node, SessionChip))
                return true;
            node = VisualTreeHelper.GetParent(node);
        }
        return false;
    }

    private void SessionChipClicked(object sender, RoutedEventArgs e)
    {
        switch (_snapshot.Phase)
        {
            case SessionPhase.Idle: StartClass?.Invoke(); break;
            case SessionPhase.Running: EndClass?.Invoke(); break;
            case SessionPhase.Ended: SummarizeClass?.Invoke(); break;
            case SessionPhase.SummaryReady:
            case SessionPhase.Saved: SaveNote?.Invoke(); break;
        }
    }

    private void ModeChipClicked(object sender, MouseButtonEventArgs e)
    {
        if (_answerAction is null && _snapshot.Phase == SessionPhase.Idle && !_doubaoReady)
            OpenDoubao?.Invoke();
    }

    private void CloseClicked(object sender, RoutedEventArgs e)
    {
        if (_answerAction is not null && _snapshot.Phase == SessionPhase.Running)
        {
            _answerAction = null;
            _detail = null;
            _loading = false;
            ShowSession(_snapshot);
        }
        else ToggleHidden();
    }

    private void SetDotPulsing(bool pulsing)
    {
        StatusDot.BeginAnimation(OpacityProperty, null);
        if (!pulsing)
        {
            StatusDot.Opacity = 1;
            return;
        }
        StatusDot.BeginAnimation(OpacityProperty, new DoubleAnimation(1, 0.28, TimeSpan.FromMilliseconds(850))
        {
            AutoReverse = true,
            RepeatBehavior = RepeatBehavior.Forever,
            EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut }
        });
    }

    private static SolidColorBrush Soft(Color color, byte alpha) =>
        new(Color.FromArgb(alpha, color.R, color.G, color.B));

    private static SolidColorBrush Blend(Color color, Color other, double amount) =>
        new(Color.FromRgb(
            (byte)(color.R + (other.R - color.R) * amount),
            (byte)(color.G + (other.G - color.G) * amount),
            (byte)(color.B + (other.B - color.B) * amount)));

    private static Brush Brush(string hex) => (Brush)BrushBox.ConvertFromString(hex)!;

    private void SetEyebrow(string text) => Eyebrow.Text = text;

    private void SetTitle(string text) => TitleText.Text = text;
}
