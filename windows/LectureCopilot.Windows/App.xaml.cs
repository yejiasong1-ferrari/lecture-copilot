using System.Threading;
using System.Windows;
using LectureCopilot.Windows.Services;
using LectureCopilot.Windows.Views;

namespace LectureCopilot.Windows;

public partial class App : System.Windows.Application
{
    private Mutex? _singleInstance;
    private MainController? _controller;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        if (e.Args.Contains("--self-test", StringComparer.OrdinalIgnoreCase))
        {
            Environment.Exit(SelfTest.Run());
            return;
        }
        _singleInstance = new Mutex(true, "LectureCopilot.Windows.SingleInstance", out var created);
        if (!created)
        {
            MessageBox.Show("Lecture Copilot is already running.", "Lecture Copilot");
            Shutdown();
            return;
        }

        AppPaths.EnsureDirectories();
        Logger.Write("Lecture Copilot Windows starting");
        var hud = new HudWindow();
        _controller = new MainController(hud);
        _controller.Start();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _controller?.Dispose();
        _singleInstance?.Dispose();
        base.OnExit(e);
    }
}
