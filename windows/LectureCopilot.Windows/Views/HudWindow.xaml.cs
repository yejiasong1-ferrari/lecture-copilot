using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using LectureCopilot.Windows.Models;

namespace LectureCopilot.Windows.Views;

public partial class HudWindow : Window
{
    private const double CompactWidth = 790;
    private const double CompactHeight = 112;
    private const double ExpandedWidth = 720;
    private const double ExpandedHeight = 430;
    private readonly DispatcherTimer _collapseTimer;
    private bool _expanded;
    private bool _hiddenByUser;
    private ClassHudSnapshot _snapshot = ClassHudSnapshot.Idle;
    private string? _detail;
    private CopilotAction? _answerAction;

    public event Action? StartClass;
    public event Action? EndClass;
    public event Action? SummarizeClass;
    public event Action? ReviewNote;
    public event Action? SaveNote;
    public event Action? NewClass;

    public HudWindow()
    {
        InitializeComponent();
        _collapseTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(220) };
        _collapseTimer.Tick += (_, _) => { _collapseTimer.Stop(); Collapse(); };
        MouseEnter += (_, _) => { _collapseTimer.Stop(); Expand(); };
        MouseLeave += (_, _) => _collapseTimer.Start();
        MouseLeftButtonDown += (_, e) => { if (e.ButtonState == MouseButtonState.Pressed) DragMove(); };
        Loaded += (_, _) => PositionAtTopRight();
    }

    public bool HiddenByUser => _hiddenByUser;

    public void ToggleHidden()
    {
        _hiddenByUser = !_hiddenByUser;
        if (_hiddenByUser) Hide(); else { Render(); ShowWithoutActivation(); }
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
        Render();
        if (!_hiddenByUser) ShowWithoutActivation();
    }

    public void ShowLoading(string text, CopilotAction action)
    {
        _answerAction = action;
        _detail = text;
        Render();
        if (!_hiddenByUser) ShowWithoutActivation();
    }

    public void ShowAnswer(string text, CopilotAction action)
    {
        _answerAction = action;
        _detail = text;
        Render();
        Expand();
        if (!_hiddenByUser) ShowWithoutActivation();
    }

    public void Tick(ClassHudSnapshot snapshot)
    {
        _snapshot = snapshot;
        if (_answerAction is null) Render();
    }

    private void Render()
    {
        HeaderActions.Children.Clear();
        FooterActions.Children.Clear();
        FooterActions.Visibility = Visibility.Collapsed;

        if (_answerAction is { } action)
        {
            Eyebrow.Text = _snapshot.Phase == SessionPhase.Running
                ? $"CLASS · {ClassHudSnapshot.DurationText(_snapshot.Elapsed)}"
                : "LECTURE COPILOT";
            TitleText.Text = action.ChipTitle();
            DetailText.Text = _detail ?? "Working…";
            AddPersistentSessionAction();
            return;
        }

        Eyebrow.Text = _snapshot.Phase == SessionPhase.Running
            ? $"CLASS · {ClassHudSnapshot.DurationText(_snapshot.Elapsed)} · {_snapshot.InteractionCount} NOTES"
            : "LECTURE COPILOT";
        DetailText.Text = _detail ?? DetailForPhase();
        switch (_snapshot.Phase)
        {
            case SessionPhase.Idle:
                TitleText.Text = "Start Class";
                AddHeader("Start", "#263B5270", "#7DB8FF", () => StartClass?.Invoke());
                break;
            case SessionPhase.Running:
                TitleText.Text = "Class Session";
                AddHeader("End", "#5A3A2F35", "#FF8A7A", () => EndClass?.Invoke());
                break;
            case SessionPhase.Ended:
                TitleText.Text = "Class Ended";
                AddHeader("Summary", "#55472D24", "#F4C16D", () => SummarizeClass?.Invoke());
                AddFooter("Summary", "#C38B3E", () => SummarizeClass?.Invoke());
                AddFooter("New", "#D26F3B", () => NewClass?.Invoke());
                break;
            case SessionPhase.Summarizing:
                TitleText.Text = "Summarizing";
                break;
            case SessionPhase.SummaryReady:
            case SessionPhase.Saved:
                TitleText.Text = _snapshot.Phase == SessionPhase.Saved ? "Class Saved" : "Class Summary";
                AddHeader("Save", "#263E4235", "#69D4A5", () => SaveNote?.Invoke());
                AddFooter("Review Note", "#367CC9", () => ReviewNote?.Invoke());
                AddFooter("Save", "#2B9A6E", () => SaveNote?.Invoke());
                AddFooter("New", "#D26F3B", () => NewClass?.Invoke());
                break;
        }
    }

    private void AddPersistentSessionAction()
    {
        if (_snapshot.Phase == SessionPhase.Running)
            AddHeader("End", "#5A3A2F35", "#FF8A7A", () => EndClass?.Invoke());
        else if (_snapshot.Phase == SessionPhase.Ended)
            AddHeader("Summary", "#55472D24", "#F4C16D", () => SummarizeClass?.Invoke());
        else if (_snapshot.Phase is SessionPhase.SummaryReady or SessionPhase.Saved)
            AddHeader("Save", "#263E4235", "#69D4A5", () => SaveNote?.Invoke());
    }

    private string DetailForPhase() => _snapshot.Phase switch
    {
        SessionPhase.Idle => "按 Start 开始记录课堂。使用 Shift + 方向键框选并发送给豆包。",
        SessionPhase.Running => $"Started {_snapshot.StartClock}  ·  {_snapshot.InteractionCount} notes saved",
        SessionPhase.Ended => $"本节课已结束，共 {_snapshot.InteractionCount} 条记录。需要总结时点 Summary。",
        SessionPhase.Summarizing => "已发给豆包。生成完成后按 Shift + Return 读取总结。",
        SessionPhase.SummaryReady => _detail ?? "总结已读取，可以预览或保存。",
        SessionPhase.Saved => _detail ?? "课堂笔记已经保存。",
        _ => ""
    };

    private void AddHeader(string text, string background, string border, Action action) =>
        HeaderActions.Children.Add(Button(text, background, border, action));

    private void AddFooter(string text, string background, Action action)
    {
        FooterActions.Visibility = Visibility.Visible;
        FooterActions.Children.Add(Button(text, background, "#32FFFFFF", action));
    }

    private System.Windows.Controls.Button Button(string text, string background, string border, Action action)
    {
        var button = new System.Windows.Controls.Button
        {
            Content = text,
            Background = (Brush)new BrushConverter().ConvertFromString(background)!,
            BorderBrush = (Brush)new BrushConverter().ConvertFromString(border)!,
            Style = (Style)FindResource("Pill")
        };
        button.Click += (_, _) => action();
        return button;
    }

    private void Expand()
    {
        if (_expanded) return;
        _expanded = true;
        var right = Left + Width;
        Width = ExpandedWidth;
        Height = ExpandedHeight;
        Left = right - Width;
        DetailScroller.Visibility = Visibility.Visible;
        FooterActions.Visibility = FooterActions.Children.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private void Collapse()
    {
        if (!_expanded) return;
        _expanded = false;
        var right = Left + Width;
        Width = CompactWidth;
        Height = CompactHeight;
        Left = right - Width;
        DetailScroller.Visibility = Visibility.Collapsed;
        FooterActions.Visibility = Visibility.Collapsed;
    }

    private void PositionAtTopRight()
    {
        var area = SystemParameters.WorkArea;
        Left = area.Right - Width - 20;
        Top = area.Top + 18;
    }

    private void ShowWithoutActivation()
    {
        Show();
        Topmost = true;
    }

    private void CloseClicked(object sender, RoutedEventArgs e)
    {
        if (_answerAction is not null && _snapshot.Phase == SessionPhase.Running)
        {
            _answerAction = null;
            _detail = null;
            ShowSession(_snapshot);
        }
        else ToggleHidden();
    }
}
