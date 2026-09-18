using System.Diagnostics;
using System.Text;
using System.Windows;
using LectureCopilot.Windows.Models;
using LectureCopilot.Windows.Views;
using Microsoft.Win32;

namespace LectureCopilot.Windows.Services;

public sealed class MainController : IDisposable
{
    private sealed record PendingRead(string Prompt, CopilotAction Action, DateTimeOffset ExpiresAt);

    private readonly HudWindow _hud;
    private readonly HotKeyService _hotKeys = new();
    private readonly TrayIconService _tray = new();
    private readonly ScreenshotService _screenshot = new();
    private readonly DoubaoService _doubao = new();
    private readonly ForegroundWindowService _foreground = new();
    private readonly PromptStore _prompts = new();
    private readonly AppSettings _settings = AppSettings.Load();
    private readonly ClassSessionStore _sessions;
    private readonly System.Windows.Threading.DispatcherTimer _sessionTimer;
    private PendingRead? _pendingRead;
    private Guid? _pendingInteraction;
    private DateTimeOffset? _lastExtractAt;
    private DateTimeOffset? _lastShiftUpAt;
    private int _shiftUpSequence;
    private bool _busy;

    public MainController(HudWindow hud)
    {
        _hud = hud;
        _sessions = new ClassSessionStore(_settings);
        _sessionTimer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _sessionTimer.Tick += (_, _) => { if (IsSessionRunning) _hud.Tick(_sessions.Snapshot()); };
        BindEvents();
    }

    private bool IsSessionRunning => _sessions.Session is { EndTime: null };
    private bool IsAwaitingSummary => _sessions.Session is { EndTime: not null, Summary: null, SavePath: null };
    private bool IsSummaryReady => !string.IsNullOrWhiteSpace(_sessions.Session?.Summary);

    public void Start()
    {
        _hotKeys.Start();
        PresentSession();
        RenderTray();
        _ = EnsureDoubaoAtLaunchAsync();
    }

    private void BindEvents()
    {
        _hotKeys.Pressed += HandleHotKey;
        _hud.StartClass += StartClass;
        _hud.EndClass += EndClass;
        _hud.SummarizeClass += SummarizeClass;
        _hud.ReviewNote += ReviewNote;
        _hud.SaveNote += SaveNote;
        _hud.NewClass += NewClass;
        _hud.OpenDoubao += () => _ = EnsureDoubaoAtLaunchAsync(true);
        _tray.ToggleClassMode += ToggleClassMode;
        _tray.RunAction += action => _ = RunActionAsync(action);
        _tray.ReadAnswer += () => _ = ReadPendingAsync();
        _tray.ToggleHud += _hud.ToggleHidden;
        _tray.StartClass += StartClass;
        _tray.EndClass += EndClass;
        _tray.SummarizeClass += SummarizeClass;
        _tray.SaveNote += SaveNote;
        _tray.NewClass += NewClass;
        _tray.ToggleRecordTranslate += ToggleRecordTranslate;
        _tray.ToggleReturnToPreviousApp += ToggleReturnToPreviousApp;
        _tray.OpenDoubao += () => _ = EnsureDoubaoAtLaunchAsync(true);
        _tray.OpenPrompts += () => ForegroundWindowService.OpenPath(_prompts.EnsureFile());
        _tray.OpenLastAnswer += () => { if (File.Exists(AppPaths.LastAnswer)) ForegroundWindowService.OpenPath(AppPaths.LastAnswer); };
        _tray.OpenNotesFolder += () => ForegroundWindowService.OpenPath(AppPaths.NotesDirectory);
        _tray.InspectDoubao += () => ForegroundWindowService.OpenPath(_doubao.InspectTree());
        _tray.TranslateLastCapture += () => _ = RunActionAsync(CopilotAction.Translate, true);
        _tray.ShowShortcuts += ShowShortcuts;
        _tray.Quit += () => Application.Current.Shutdown();
    }

    private async Task EnsureDoubaoAtLaunchAsync(bool activate = false)
    {
        if (_doubao.IsRunning)
        {
            Logger.Write("Doubao already running at launch");
            _hud.SetDoubaoReady(true);
            if (activate) await _doubao.EnsureRunningAsync(true);
            return;
        }

        Logger.Write("Doubao not running at launch; checking client");
        if (!activate) _foreground.RememberUnlessDoubao();
        _hud.SetDoubaoReady(false, launching: true);
        var ok = await _doubao.EnsureRunningAsync(activate);
        Logger.Write(ok
            ? "Doubao became available"
            : "Doubao was not available; HUD will show Open Doubao");
        _hud.SetDoubaoReady(ok);
        if (!activate)
        {
            await Task.Delay(250);
            _foreground.Restore();
        }
    }

    private void HandleHotKey(HotKeyEvent key)
    {
        Logger.Write($"Hotkey {key}");
        if (!_settings.ClassModeEnabled)
        {
            _settings.ClassModeEnabled = true;
            _settings.Save();
            RenderTray();
            _hud.Reveal();
            Logger.Write("Class mode was off; turned it on from the hotkey");
        }
        switch (key)
        {
            case HotKeyEvent.ShiftLeft: _ = RunActionAsync(CopilotAction.Translate); break;
            case HotKeyEvent.ShiftRight: _ = RunActionAsync(CopilotAction.Explain); break;
            case HotKeyEvent.ShiftUp: HandleShiftUp(); break;
            case HotKeyEvent.ShiftDown: _foreground.Restore(); break;
            case HotKeyEvent.ShiftReturn: _ = ReadPendingAsync(); break;
            case HotKeyEvent.ToggleHud: _hud.ToggleHidden(); break;
        }
    }

    private void HandleShiftUp()
    {
        var now = DateTimeOffset.UtcNow;
        var doublePress = _lastShiftUpAt is { } previous && now - previous <= TimeSpan.FromMilliseconds(600);
        _lastShiftUpAt = now;
        _shiftUpSequence++;
        var sequence = _shiftUpSequence;
        if (doublePress) _ = RunActionAsync(CopilotAction.SayInClass);
        else _ = Task.Run(async () =>
        {
            await Task.Delay(620);
            await Application.Current.Dispatcher.InvokeAsync(() =>
            {
                if (_shiftUpSequence == sequence && _lastShiftUpAt is { } last
                    && DateTimeOffset.UtcNow - last >= TimeSpan.FromMilliseconds(600))
                    _ = RunActionAsync(CopilotAction.DirectAnswer);
            });
        });
    }

    private async Task RunActionAsync(CopilotAction action, bool useLastCapture = false)
    {
        if (_busy)
        {
            Logger.Write($"Hotkey {action} ignored because a capture/send is already running");
            return;
        }
        if (!_settings.ClassModeEnabled) return;
        if (action == CopilotAction.BackToClass) { _foreground.Restore(); return; }
        var key = action.PromptKey();
        if (key is null) return;
        _busy = true;
        try
        {
            _foreground.RememberUnlessDoubao();
            var prompt = _prompts.Get(key);
            bool captured;
            if (useLastCapture)
                captured = await _screenshot.CopyLastCaptureAsync();
            else
                captured = await _screenshot.CaptureSelectionAsync(_doubao.ForceForeground);
            if (!captured)
            {
                _hud.ShowLoading("Screenshot was cancelled.", action);
                return;
            }

            _pendingRead = null;
            _hud.ShowLoading("Sending screenshot to Doubao…", action);
            var result = await _doubao.SendImageAndPromptAsync(prompt,
                _settings.ReturnToPreviousApp ? _foreground.Restore : null);
            if (!result.Success)
            {
                _hud.ShowAnswer(result.Message, action);
                return;
            }
            _pendingRead = new PendingRead(prompt, action, DateTimeOffset.UtcNow.AddMinutes(3));
            _pendingInteraction = _sessions.BeginInteraction(action);
            _hud.ShowLoading(_settings.ReturnToPreviousApp
                ? "已发送到豆包。生成完成后按 Shift + Return 读取。"
                : "已发送到豆包。生成完成后按 Shift + Return 读取，Shift + Down 回课堂。", action);
            Logger.Write(_settings.ReturnToPreviousApp
                ? "Classroom window restored immediately after submit"
                : "Keeping Doubao in front after send");
            RenderTray();
        }
        catch (Exception ex)
        {
            Logger.Write($"Run action failed: {ex}");
            _foreground.Restore();
            _hud.ShowAnswer($"操作失败：{ex.Message}", action);
        }
        finally { _busy = false; }
    }

    private async Task ReadPendingAsync()
    {
        if (_busy || _pendingRead is null || _pendingRead.ExpiresAt < DateTimeOffset.UtcNow) return;
        if (_lastExtractAt is { } last && DateTimeOffset.UtcNow - last < TimeSpan.FromSeconds(5))
        {
            Logger.Write("Shift+Enter ignored (5s cooldown)");
            return;
        }
        _lastExtractAt = DateTimeOffset.UtcNow;
        _busy = true;
        var pending = _pendingRead;
        try
        {
            _foreground.RememberUnlessDoubao();
            var answer = await _doubao.CopyLatestAnswerAsync(pending.Prompt);
            if (string.IsNullOrWhiteSpace(answer))
            {
                _hud.ShowLoading("豆包还在生成。已返回课堂。5 秒后再按一次 Shift+Enter。", pending.Action);
                return;
            }
            File.WriteAllText(AppPaths.LastAnswer, answer, Encoding.UTF8);
            _pendingRead = null;
            if (pending.Action == CopilotAction.ClassSummary)
            {
                _sessions.SetSummary(answer);
                _hud.ShowSession(_sessions.Snapshot(), answer);
            }
            else
            {
                if (_pendingInteraction is { } id) _sessions.FinishInteraction(id, answer);
                _hud.ShowAnswer(answer, pending.Action);
            }
            RenderTray();
        }
        catch (Exception ex)
        {
            Logger.Write($"Read answer failed: {ex}");
            _hud.ShowAnswer("Could not read answer\n\n读取失败，请稍后再按 Shift + Return。", pending.Action);
        }
        finally
        {
            _foreground.Restore();
            _busy = false;
        }
    }

    private void ToggleClassMode()
    {
        _settings.ClassModeEnabled = !_settings.ClassModeEnabled;
        _settings.Save();
        if (!_settings.ClassModeEnabled) _pendingRead = null;
        else PresentSession();
        RenderTray();
    }

    private void StartClass()
    {
        if (IsSessionRunning) return;
        if ((IsAwaitingSummary || IsSummaryReady) && MessageBox.Show("上一节课还没有完整处理。确定开始新课堂吗？",
            "Start a new class?", MessageBoxButton.OKCancel, MessageBoxImage.Warning) != MessageBoxResult.OK) return;
        _sessions.Start();
        _pendingInteraction = null;
        _sessionTimer.Start();
        PresentSession();
        RenderTray();
    }

    private void EndClass()
    {
        if (!IsSessionRunning) return;
        if (_busy) { _hud.ShowLoading("等当前操作结束后再结束这节课。", CopilotAction.ClassSummary); return; }
        if (MessageBox.Show("停止计时。需要总结时再点 Summary。", "End Class?",
            MessageBoxButton.OKCancel, MessageBoxImage.Question) != MessageBoxResult.OK) return;
        _sessions.End();
        _sessionTimer.Stop();
        PresentSession();
        RenderTray();
    }

    private async void SummarizeClass()
    {
        if (!IsAwaitingSummary || _busy) return;
        _busy = true;
        try
        {
            _foreground.RememberUnlessDoubao();
            var prompt = _prompts.Get("classSummary") + "\n\n" + _sessions.SummaryPayload();
            var snapshot = _sessions.Snapshot() with { Phase = SessionPhase.Summarizing };
            _hud.ShowSession(snapshot);
            var result = await _doubao.SendTextAsync(prompt, _foreground.Restore);
            if (!result.Success) { _hud.ShowAnswer(result.Message, CopilotAction.ClassSummary); return; }
            _pendingRead = new PendingRead(prompt, CopilotAction.ClassSummary, DateTimeOffset.UtcNow.AddMinutes(8));
            _hud.ShowLoading("已发给豆包做总结。生成完成后按 Shift + Return 读取。", CopilotAction.ClassSummary);
        }
        catch (Exception ex) { Logger.Write($"Summary failed: {ex}"); }
        finally { _busy = false; RenderTray(); }
    }

    private void ReviewNote() => ForegroundWindowService.OpenPath(_sessions.WritePreview());

    private void SaveNote()
    {
        var dialog = new SaveFileDialog
        {
            Title = "Save Class Note",
            Filter = "Markdown (*.md)|*.md",
            FileName = Path.GetFileName(_sessions.DefaultSavePath),
            InitialDirectory = AppPaths.NotesDirectory,
            AddExtension = true,
            DefaultExt = ".md"
        };
        if (dialog.ShowDialog() != true) return;
        try
        {
            _sessions.Save(dialog.FileName);
            _hud.ShowSession(_sessions.Snapshot(), $"已保存到\n{dialog.FileName}");
            RenderTray();
        }
        catch (Exception ex) { _hud.ShowLoading($"保存失败：{ex.Message}", CopilotAction.ClassSummary); }
    }

    private void NewClass()
    {
        if (IsSessionRunning) return;
        if ((IsAwaitingSummary || IsSummaryReady && _sessions.Session?.SavePath is null)
            && MessageBox.Show("上一节课还没有总结或保存。确定清除吗？", "New Class?",
                MessageBoxButton.OKCancel, MessageBoxImage.Warning) != MessageBoxResult.OK) return;
        _pendingRead = null;
        _pendingInteraction = null;
        _sessions.Clear();
        PresentSession();
        RenderTray();
    }

    private void ToggleRecordTranslate()
    {
        _sessions.RecordTranslate = !_sessions.RecordTranslate;
        RenderTray();
    }

    private void ToggleReturnToPreviousApp()
    {
        _settings.ReturnToPreviousApp = !_settings.ReturnToPreviousApp;
        _settings.Save();
        RenderTray();
    }

    private static void ShowShortcuts() => MessageBox.Show("""
        Class Mode ON 时可用：

        Translate: Shift + Left
        Explain: Shift + Right
        Direct Answer: Shift + Up
        Say in Class: Shift + Up, Up within 600ms
        Read Doubao Answer: Shift + Return
        Back to Class: Shift + Down
        Hide / Show HUD: double-tap Shift
        """, "Lecture Copilot Shortcuts", MessageBoxButton.OK, MessageBoxImage.Information);

    private void PresentSession()
    {
        _hud.ShowSession(_sessions.Snapshot());
        if (IsSessionRunning) _sessionTimer.Start();
    }

    private void RenderTray() => _tray.Update(new TrayState(_settings.ClassModeEnabled, IsSessionRunning,
        IsAwaitingSummary, IsSummaryReady, _sessions.RecordTranslate, _sessions.Session?.RecordedCount ?? 0,
        _settings.ReturnToPreviousApp));

    public void Dispose()
    {
        _sessionTimer.Stop();
        _hotKeys.Dispose();
        _tray.Dispose();
        _hud.Close();
    }
}
