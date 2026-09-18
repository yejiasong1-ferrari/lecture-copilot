using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Media;
using LectureCopilot.Windows.Models;

namespace LectureCopilot.Windows.Views;

// Presentation only: the original reply remains unchanged in the clipboard and session.
internal static class AnswerView
{
    private static readonly Regex Chinese = new(@"[\u3400-\u9fff]", RegexOptions.Compiled);
    private static readonly Regex Heading = new(@"^\s*#{1,6}\s+", RegexOptions.Compiled);
    private static readonly Regex Label = new(@"^(答案|回答|结论|原因|理由|其他选项|Answer|Reason|Explanation|Other options|[A-H]\s*错)\s*[:：]", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public static void Render(StackPanel target, string text, CopilotAction? action)
    {
        target.Children.Clear();
        StackPanel? pair = null;
        var previousEnglish = false;
        var gap = false;
        var accent = action switch
        {
            CopilotAction.Translate => "#A8E7CB",
            CopilotAction.Explain => "#ACCCFF",
            CopilotAction.DirectAnswer => "#FFD29A",
            CopilotAction.SayInClass => "#DCCAFF",
            _ => "#D8E2F0"
        };
        foreach (var original in text.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n'))
        {
            if (string.IsNullOrWhiteSpace(original)) { gap = true; continue; }
            var heading = Heading.IsMatch(original);
            var line = Heading.Replace(original, "");
            var plain = line.Replace("**", "");
            var chinese = Chinese.IsMatch(plain);
            var label = Label.Match(plain);
            var answer = label.Success && Regex.IsMatch(label.Value, @"^(答案|回答|结论|Answer)", RegexOptions.IgnoreCase);
            var speech = action == CopilotAction.SayInClass && !chinese && !heading;

            if (action == CopilotAction.Translate && !heading)
            {
                if (pair is null || !previousEnglish || !chinese || gap)
                {
                    pair = new StackPanel();
                    target.Children.Add(Card(pair, "#293F38", "#153027", 10));
                }
                var block = Paragraph(line, chinese ? accent : "#BAC6D6", chinese ? 15 : 14, accent, false);
                block.Margin = new Thickness(0, pair.Children.Count > 0 ? 5 : 0, 0, 0);
                pair.Children.Add(block);
                previousEnglish = !chinese;
            }
            else
            {
                pair = null;
                var color = heading || label.Success ? accent : "#E4EAF2";
                var secondaryEnglish = action == CopilotAction.DirectAnswer && !chinese && !heading;
                if (secondaryEnglish) color = "#BCC8D8";
                if (action == CopilotAction.SayInClass && chinese) color = "#B8C3D3";
                if (speech) color = accent;
                // Long explanation paragraphs get natural sentence breaks without rewriting.
                var chunks = action == CopilotAction.Explain && line.Length > 140 && !heading
                    ? Regex.Split(line, @"(?<=[。！？])(?=[^”’」』])") : new[] { line };
                foreach (var chunk in chunks.Where(c => c.Length > 0))
                {
                    var labelAccent = label.Success && Regex.IsMatch(label.Value, @"^(原因|理由|Reason|Explanation)", RegexOptions.IgnoreCase)
                        ? "#ACCCFF" : accent;
                    if (label.Success && Regex.IsMatch(label.Value, @"^(其他选项|Other options|[A-H]\s*错)", RegexOptions.IgnoreCase))
                        labelAccent = "#B6C3D6";
                    var block = Paragraph(chunk, color, speech ? 16 : secondaryEnglish ? 14 : 15, labelAccent, heading);
                    if (answer || speech)
                    {
                        block.Foreground = Brush(secondaryEnglish ? "#C6D0DD" : "#F1F3F8");
                        target.Children.Add(Card(block, speech ? "#62527D" : "#806248",
                            speech ? "#252132" : "#302820", 12));
                    }
                    else
                    {
                        // Only labels and explicit Markdown emphasis receive color/weight.
                        if (label.Success && !heading) block.Foreground = Brush("#E4EAF2");
                        block.Margin = new Thickness(0, gap ? 5 : 0, 0, heading ? 12 : 9);
                        target.Children.Add(block);
                    }
                    gap = false;
                }
                previousEnglish = false;
            }
            gap = false;
        }
    }

    private static Border Card(UIElement content, string edge, string background, double padding) => new()
    {
        Child = content, Background = Brush(background), BorderBrush = Brush(edge),
        BorderThickness = new Thickness(2, 0, 0, 0), CornerRadius = new CornerRadius(8),
        Padding = new Thickness(padding, 10, padding, 10), Margin = new Thickness(0, 0, 0, 12)
    };

    private static TextBlock Paragraph(string text, string color, double size, string accent, bool heading)
    {
        var block = new TextBlock
        {
            Foreground = Brush(color), FontSize = size, LineHeight = 25,
            TextWrapping = TextWrapping.Wrap, FontWeight = FontWeights.Normal,
            FontFamily = new FontFamily("Segoe UI, Microsoft YaHei UI")
        };
        var first = true;
        foreach (var piece in Regex.Split(text, @"(\*\*.+?\*\*)"))
        {
            if (piece.Length == 0) continue;
            var bold = piece.Length > 4 && piece.StartsWith("**") && piece.EndsWith("**");
            var value = bold ? piece[2..^2] : piece;
            var match = first ? Label.Match(value) : Match.Empty;
            if (match.Success)
            {
                block.Inlines.Add(new Run(match.Value) { Foreground = Brush(accent), FontWeight = FontWeights.SemiBold });
                value = value[match.Length..];
            }
            var run = new Run(value) { FontWeight = bold || heading ? FontWeights.SemiBold : FontWeights.Normal };
            if (bold || heading) run.Foreground = Brush(accent);
            block.Inlines.Add(run);
            first = false;
        }
        return block;
    }

    private static SolidColorBrush Brush(string color) => (SolidColorBrush)new BrushConverter().ConvertFromString(color)!;
}
