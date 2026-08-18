using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views;

/// <summary>
/// macOS <c>AppStandardMenuCommands</c> 의 앱 메뉴입니다. Windows 에는 시스템 앱 메뉴가
/// 없어서 창 안 <see cref="MenuBar"/> 첫 항목이 그 자리입니다.
/// </summary>
public sealed partial class AppMenuBarView : UserControl
{
    public AppMenuBarView()
    {
        InitializeComponent();
        Localize();
    }

    public event EventHandler? AboutRequested;

    public event EventHandler? SettingsRequested;

    public void Localize()
    {
        string about = AppResources.Get("commandAboutNegaflow", "Text");
        AboutItem.Text = about;
        AutomationProperties.SetName(AboutItem, about);
        string settings = AppResources.Get("commandSettings", "Text");
        SettingsItem.Text = settings;
        AutomationProperties.SetName(SettingsItem, settings);
        AutomationProperties.SetName(AppMenu, "negaflow");
    }

    private void OnAboutClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        AboutRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnSettingsClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        SettingsRequested?.Invoke(this, EventArgs.Empty);
    }
}
