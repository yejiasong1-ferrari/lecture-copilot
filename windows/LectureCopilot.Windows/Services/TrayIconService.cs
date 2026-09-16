using System.Drawing;
using System.Windows;
using System.Windows.Resources;
using LectureCopilot.Windows.Models;
using WinForms = System.Windows.Forms;

namespace LectureCopilot.Windows.Services;

public sealed record TrayState(bool ClassMode, bool Running, bool AwaitingSummary, bool SummaryReady,
    bool RecordTranslate, int NoteCount);

public sealed class TrayIconService : IDisposable
{
    private readonly WinForms.NotifyIcon _icon;
    private TrayState _state = new(true, false, false, false, false, 0);

    public event Action? ToggleClassMode;
    public event Action<CopilotAction>? RunAction;
    public event Action? ReadAnswer;
    public event Action? ToggleHud;
    public event Action? StartClass;
    public event Action? EndClass;
    public event Action? SummarizeClass;
    public event Action? SaveNote;
    public event Action? NewClass;
    public event Action? ToggleRecordTranslate;
    public event Action? OpenDoubao;
    public event Action? OpenPrompts;
    public event Action? OpenLastAnswer;
    public event Action? OpenNotesFolder;
    public event Action? InspectDoubao;
    public event Action? TranslateLastCapture;
    public event Action? ShowShortcuts;
    public event Action? Quit;

    public TrayIconService()
    {
        _icon = new WinForms.NotifyIcon
        {
            Text = "Lecture Copilot",
            Visible = true,
            Icon = LoadIcon()
        };
        _icon.MouseClick += (_, e) => { if (e.Button == WinForms.MouseButtons.Left) ToggleHud?.Invoke(); };
        _icon.ContextMenuStrip = new WinForms.ContextMenuStrip();
        _icon.ContextMenuStrip.Opening += (_, _) => BuildMenu();
        BuildMenu();
    }

    public void Update(TrayState state)
    {
        _state = state;
        _icon.Text = state.ClassMode ? "Lecture Copilot · Class Mode ON" : "Lecture Copilot";
    }

    private void BuildMenu()
    {
        var menu = _icon.ContextMenuStrip!;
        menu.Items.Clear();
        menu.Items.Add(Header("Lecture Copilot"));
        menu.Items.Add(Item("Class Mode", ToggleClassMode, true, _state.ClassMode));
        menu.Items.Add(new WinForms.ToolStripSeparator());
        menu.Items.Add(Header("Class Session"));
        if (_state.Running)
        {
            menu.Items.Add(Item("End Class", EndClass));
            menu.Items.Add(Header($"{_state.NoteCount} notes saved"));
        }
        else if (_state.AwaitingSummary)
        {
            menu.Items.Add(Item("Summary", SummarizeClass));
            menu.Items.Add(Item("New Class", NewClass));
        }
        else if (_state.SummaryReady)
        {
            menu.Items.Add(Item("Save", SaveNote));
            menu.Items.Add(Item("New Class", NewClass));
        }
        else menu.Items.Add(Item("Start Class", StartClass));
        menu.Items.Add(Item("Record Translate", ToggleRecordTranslate, true, _state.RecordTranslate));
        menu.Items.Add(Item("Notes Folder", OpenNotesFolder));
        menu.Items.Add(new WinForms.ToolStripSeparator());
        menu.Items.Add(Header("Actions"));
        menu.Items.Add(ActionItem("Translate\tShift + ←", CopilotAction.Translate));
        menu.Items.Add(ActionItem("Explain\tShift + →", CopilotAction.Explain));
        menu.Items.Add(ActionItem("Direct Answer\tShift + ↑", CopilotAction.DirectAnswer));
        menu.Items.Add(ActionItem("Say in Class\tShift + ↑ ↑", CopilotAction.SayInClass));
        menu.Items.Add(Item("Read Doubao Answer\tShift + Return", ReadAnswer));
        menu.Items.Add(ActionItem("Back to Class\tShift + ↓", CopilotAction.BackToClass));
        menu.Items.Add(Item("Hide / Show HUD\tShift Shift", ToggleHud));
        menu.Items.Add(new WinForms.ToolStripSeparator());
        menu.Items.Add(Header("Settings"));
        menu.Items.Add(Item("Doubao", OpenDoubao));
        menu.Items.Add(Item("Prompts", OpenPrompts));
        menu.Items.Add(Item("Shortcuts", ShowShortcuts));
        menu.Items.Add(Item("Last Answer", OpenLastAnswer));
        menu.Items.Add(Item("Translate Last Capture", TranslateLastCapture));
        menu.Items.Add(Item("Inspect Doubao", InspectDoubao));
        menu.Items.Add(new WinForms.ToolStripSeparator());
        menu.Items.Add(Item("Quit", Quit));
    }

    private WinForms.ToolStripMenuItem ActionItem(string text, CopilotAction action) =>
        Item(text, () => RunAction?.Invoke(action));

    private static WinForms.ToolStripMenuItem Header(string text) => new(text) { Enabled = false };

    private static WinForms.ToolStripMenuItem Item(string text, Action? action, bool checkable = false, bool isChecked = false)
    {
        var item = new WinForms.ToolStripMenuItem(text) { CheckOnClick = checkable, Checked = isChecked };
        if (action is not null) item.Click += (_, _) => action();
        return item;
    }

    private static Icon LoadIcon()
    {
        try
        {
            StreamResourceInfo resource = Application.GetResourceStream(new Uri("pack://application:,,,/Assets/AppIcon.png"));
            using var bitmap = new Bitmap(resource.Stream);
            return Icon.FromHandle(bitmap.GetHicon());
        }
        catch
        {
            return SystemIcons.Application;
        }
    }

    public void Dispose()
    {
        _icon.Visible = false;
        _icon.Dispose();
    }
}
