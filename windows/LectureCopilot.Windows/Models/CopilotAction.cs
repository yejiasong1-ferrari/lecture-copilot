namespace LectureCopilot.Windows.Models;

public enum CopilotAction
{
    Translate,
    Explain,
    DirectAnswer,
    SayInClass,
    BackToClass,
    ClassSummary
}

public static class CopilotActionExtensions
{
    public static string? PromptKey(this CopilotAction action) => action switch
    {
        CopilotAction.Translate => "translate",
        CopilotAction.Explain => "explain",
        CopilotAction.DirectAnswer => "directAnswer",
        CopilotAction.SayInClass => "sayInClass",
        CopilotAction.ClassSummary => "classSummary",
        _ => null
    };

    public static string DisplayName(this CopilotAction action) => action switch
    {
        CopilotAction.Translate => "Translate",
        CopilotAction.Explain => "Explain",
        CopilotAction.DirectAnswer => "Direct Answer",
        CopilotAction.SayInClass => "Say in Class",
        CopilotAction.BackToClass => "Back to Class",
        CopilotAction.ClassSummary => "Class Summary",
        _ => action.ToString()
    };

    public static string ChipTitle(this CopilotAction action) => action switch
    {
        CopilotAction.DirectAnswer => "Answer",
        CopilotAction.SayInClass => "Speak",
        CopilotAction.BackToClass => "Class",
        CopilotAction.ClassSummary => "Summary",
        _ => action.DisplayName()
    };
}

public enum HotKeyEvent
{
    ShiftLeft,
    ShiftRight,
    ShiftUp,
    ShiftDown,
    ShiftReturn,
    ToggleHud
}
