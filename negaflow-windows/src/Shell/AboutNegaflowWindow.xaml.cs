using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell;

public sealed partial class AboutNegaflowWindow : Window
{
    public AboutNegaflowWindow(PresentationSettingsStore settingsStore)
    {
        ArgumentNullException.ThrowIfNull(settingsStore);
        InitializeComponent();
        WindowIcon.Apply(AppWindow);
        LocalizedElement.Track(
            this,
            () => Title = AppResources.Get("commandAboutNegaflow", "Value"));
        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.IsResizable = false;
            presenter.IsMaximizable = false;
        }

        AppWindow.Resize(WindowDpiSizing.LogicalToPhysical(
            this,
            ShellLayoutMetrics.AboutWindowWidth,
            ShellLayoutMetrics.AboutWindowHeight));
        WindowRoot.RequestedTheme = settingsStore.Current.Appearance switch
        {
            AppearanceMode.Dark => ElementTheme.Dark,
            AppearanceMode.Light => ElementTheme.Light,
            _ => ElementTheme.Default,
        };
    }
}
