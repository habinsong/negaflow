using Microsoft.UI.Xaml;

namespace Negaflow.Shell;

public partial class App : Application
{
    private Window? mainWindow;

    public App()
    {
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _ = args;
        var settingsStore = new PresentationSettingsStore();
        var workspaceState = new WorkspacePresentationState(settingsStore);
        mainWindow = new MainWindow(
            settingsStore,
            workspaceState,
            new NativeEngineStatusService());
        mainWindow.Activate();
    }
}
