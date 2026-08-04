using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell;

public sealed partial class SettingsWindow : Window
{
    private readonly PresentationSettingsStore settingsStore;

    public SettingsWindow(
        PresentationSettingsStore settingsStore,
        WorkspacePresentationState workspaceState)
    {
        ArgumentNullException.ThrowIfNull(settingsStore);
        ArgumentNullException.ThrowIfNull(workspaceState);
        this.settingsStore = settingsStore;
        InitializeComponent();
        Title = AppResources.Get("commandSettings", "Value");

        SettingsView.Initialize(workspaceState);
        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.IsResizable = false;
            presenter.IsMaximizable = false;
        }

        AppWindow.Resize(WindowDpiSizing.LogicalToPhysical(
            this,
            ShellLayoutMetrics.SettingsWindowWidth,
            ShellLayoutMetrics.SettingsWindowHeight));
        ApplyAppearance(settingsStore.Current.Appearance);
        settingsStore.Changed += OnSettingsChanged;
        Closed += OnClosed;
    }

    private void OnSettingsChanged(object? sender, ShellPreferences preferences)
    {
        _ = sender;
        ApplyAppearance(preferences.Appearance);
    }

    private void ApplyAppearance(AppearanceMode appearance)
    {
        WindowRoot.RequestedTheme = appearance switch
        {
            AppearanceMode.Dark => ElementTheme.Dark,
            AppearanceMode.Light => ElementTheme.Light,
            _ => ElementTheme.Default,
        };
    }

    private void OnClosed(object sender, WindowEventArgs args)
    {
        _ = sender;
        _ = args;
        settingsStore.Changed -= OnSettingsChanged;
    }
}
