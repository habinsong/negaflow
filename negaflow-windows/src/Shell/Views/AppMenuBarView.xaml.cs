using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Shortcuts;

namespace Negaflow.Shell.Views;

/// <summary>
/// macOS <c>AppStandardMenuCommands</c> 의 앱 메뉴와 파일 메뉴입니다. Windows 에는 시스템
/// 앱 메뉴가 없어서 창 안 <see cref="MenuBar"/> 가 그 자리입니다.
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

    public event EventHandler<WorkflowShortcutAction>? FileCommandRequested;

    public void Localize()
    {
        string about = AppResources.Get("commandAboutNegaflow", "Text");
        AboutItem.Text = about;
        AutomationProperties.SetName(AboutItem, about);
        string settings = AppResources.Get("commandSettings", "Text");
        SettingsItem.Text = settings;
        AutomationProperties.SetName(SettingsItem, settings);
        AutomationProperties.SetName(AppMenu, "negaflow");

        string file = AppResources.Get("menuFile", "Text");
        FileMenu.Title = file;
        AutomationProperties.SetName(FileMenu, file);
        SetItem(ImportImagesItem, "shortcutImportImages");
        SetItem(ImportFolderItem, "shortcutImportFolder");
        SetItem(RefreshLibraryItem, "shortcutRefreshLibrary");
        SetItem(LoadScannerItem, "loadScanner");
        SetItem(QuickExportItem, "commandQuickExport");
        SetItem(ExportItem, "commandExport");
    }

    private static void SetItem(MenuFlyoutItem item, string key)
    {
        string text = AppResources.Get(key, "Text");
        item.Text = text;
        AutomationProperties.SetName(item, text);
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

    private void OnImportImagesClick(object sender, RoutedEventArgs args) =>
        RaiseFile(sender, args, WorkflowShortcutAction.ImportImages);

    private void OnImportFolderClick(object sender, RoutedEventArgs args) =>
        RaiseFile(sender, args, WorkflowShortcutAction.ImportFolder);

    private void OnRefreshLibraryClick(object sender, RoutedEventArgs args) =>
        RaiseFile(sender, args, WorkflowShortcutAction.RefreshLibrary);

    private void OnLoadScannerClick(object sender, RoutedEventArgs args) =>
        RaiseFile(sender, args, WorkflowShortcutAction.LoadScanner);

    private void OnQuickExportClick(object sender, RoutedEventArgs args) =>
        RaiseFile(sender, args, WorkflowShortcutAction.QuickExport);

    private void OnExportClick(object sender, RoutedEventArgs args) =>
        RaiseFile(sender, args, WorkflowShortcutAction.ExportPhoto);

    private void RaiseFile(object sender, RoutedEventArgs args, WorkflowShortcutAction action)
    {
        _ = sender;
        _ = args;
        FileCommandRequested?.Invoke(this, action);
    }
}
