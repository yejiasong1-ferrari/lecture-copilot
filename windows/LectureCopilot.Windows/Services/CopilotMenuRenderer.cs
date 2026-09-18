using System.Drawing;
using System.Drawing.Drawing2D;
using WinForms = System.Windows.Forms;

namespace LectureCopilot.Windows.Services;

internal sealed class CopilotMenuRenderer : WinForms.ToolStripProfessionalRenderer
{
    public CopilotMenuRenderer() : base(new MenuColors()) { RoundedEdges = false; }

    protected override void OnRenderMenuItemBackground(WinForms.ToolStripItemRenderEventArgs e)
    {
        if (!e.Item.Selected || !e.Item.Enabled) return;
        var rect = new Rectangle(2, 1, e.Item.Width - 4, e.Item.Height - 2);
        using var path = new GraphicsPath();
        const int diameter = 10;
        path.AddArc(rect.Left, rect.Top, diameter, diameter, 180, 90);
        path.AddArc(rect.Right - diameter, rect.Top, diameter, diameter, 270, 90);
        path.AddArc(rect.Right - diameter, rect.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(rect.Left, rect.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        using var fill = new SolidBrush(Color.FromArgb(48, 62, 79));
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.FillPath(fill, path);
    }

    protected override void OnRenderItemText(WinForms.ToolStripItemTextRenderEventArgs e)
    {
        e.TextColor = !e.Item.Enabled ? Color.FromArgb(139, 154, 174)
            : e.Text == (e.Item as WinForms.ToolStripMenuItem)?.ShortcutKeyDisplayString
                ? Color.FromArgb(154, 170, 191) : Color.FromArgb(236, 241, 248);
        WinForms.TextRenderer.DrawText(e.Graphics, e.Text, e.TextFont, e.TextRectangle, e.TextColor, e.TextFormat);
    }

    protected override void OnRenderArrow(WinForms.ToolStripArrowRenderEventArgs e)
    {
        e.ArrowColor = Color.FromArgb(154, 170, 191);
        base.OnRenderArrow(e);
    }

    protected override void OnRenderItemCheck(WinForms.ToolStripItemImageRenderEventArgs e)
    {
        var r = e.ImageRectangle;
        using var pen = new Pen(Color.FromArgb(107, 219, 176), 2);
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.DrawLines(pen, new[] {
            new Point(r.Left + 3, r.Top + r.Height / 2),
            new Point(r.Left + 6, r.Bottom - 4),
            new Point(r.Right - 2, r.Top + 3) });
    }

    private sealed class MenuColors : WinForms.ProfessionalColorTable
    {
        public override Color ToolStripDropDownBackground => Color.FromArgb(28, 32, 42);
        public override Color ImageMarginGradientBegin => ToolStripDropDownBackground;
        public override Color ImageMarginGradientMiddle => ToolStripDropDownBackground;
        public override Color ImageMarginGradientEnd => ToolStripDropDownBackground;
        public override Color MenuBorder => Color.FromArgb(67, 77, 93);
        public override Color SeparatorDark => Color.FromArgb(53, 62, 76);
        public override Color SeparatorLight => ToolStripDropDownBackground;
    }
}
