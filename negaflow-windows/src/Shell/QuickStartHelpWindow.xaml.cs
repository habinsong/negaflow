using Microsoft.UI.Xaml;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell;

/// <summary>
/// macOS <c>QuickStartHelpScene</c> 의 창입니다. macOS 는 <c>frame(minWidth: 560,
/// minHeight: 480)</c> 이라 사용자가 키울 수 있으므로 여기서도 크기를 잠그지 않습니다
/// (About 창은 macOS 가 고정이라 잠급니다).
/// </summary>
public sealed partial class QuickStartHelpWindow : Window
{
    public QuickStartHelpWindow(PresentationSettingsStore settingsStore)
    {
        ArgumentNullException.ThrowIfNull(settingsStore);
        InitializeComponent();
        WindowIcon.Apply(AppWindow);
        Title = AppResources.Get("commandNegaflowHelp", "Text");
        AppWindow.Resize(WindowDpiSizing.LogicalToPhysical(
            this,
            ShellLayoutMetrics.QuickStartWindowWidth,
            ShellLayoutMetrics.QuickStartWindowHeight));
        WindowRoot.RequestedTheme = settingsStore.Current.Appearance switch
        {
            AppearanceMode.Dark => ElementTheme.Dark,
            AppearanceMode.Light => ElementTheme.Light,
            _ => ElementTheme.Default,
        };
    }
}
