using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Shortcuts;

namespace Negaflow.Shell.Views;

/// <summary>
/// macOS <c>AppStandardMenuCommands</c> 의 앱·파일·편집·보기 메뉴입니다. Windows 에는
/// 시스템 앱 메뉴가 없어서 창 안 <see cref="MenuBar"/> 가 그 자리입니다.
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

    public event EventHandler<WorkflowShortcutAction>? CommandRequested;

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
        SetItem(ImportImagesItem, "shortcutImportImages", WorkflowShortcutAction.ImportImages);
        SetItem(ImportFolderItem, "shortcutImportFolder", WorkflowShortcutAction.ImportFolder);
        SetItem(RefreshLibraryItem, "shortcutRefreshLibrary", WorkflowShortcutAction.RefreshLibrary);
        SetItem(LoadScannerItem, "loadScanner", WorkflowShortcutAction.LoadScanner);
        SetItem(QuickExportItem, "commandQuickExport", WorkflowShortcutAction.QuickExport);
        SetItem(ExportItem, "commandExport", WorkflowShortcutAction.ExportPhoto);

        string edit = AppResources.Get("menuEdit", "Text");
        EditMenu.Title = edit;
        AutomationProperties.SetName(EditMenu, edit);
        SetItem(UndoItem, "shortcutUndo", WorkflowShortcutAction.Undo);
        SetItem(RedoItem, "shortcutRedo", WorkflowShortcutAction.Redo);
        SetItem(CopyDevelopSettingsItem, "shortcutCopyDevelopSettings",
            WorkflowShortcutAction.CopyDevelopSettings);
        SetItem(PasteDevelopSettingsItem, "shortcutPasteDevelopSettings",
            WorkflowShortcutAction.PasteDevelopSettings);
        SetItem(PickItem, "shortcutPickPhoto", WorkflowShortcutAction.PickPhoto);
        SetItem(RejectItem, "shortcutRejectPhoto", WorkflowShortcutAction.RejectPhoto);
        SetItem(DeletePhotoItem, "shortcutDeletePhoto", WorkflowShortcutAction.DeletePhoto);

        string view = AppResources.Get("menuView", "Text");
        ViewMenu.Title = view;
        AutomationProperties.SetName(ViewMenu, view);
        SetItem(ShowHideSidebarItem, "shortcutShowHideSidebar",
            WorkflowShortcutAction.ShowHideSidebar);
        SetItem(ShowHideFilmstripItem, "shortcutShowHideFilmstrip",
            WorkflowShortcutAction.ShowHideFilmstrip);
        SetItem(ShowHideInspectorItem, "shortcutShowHideInspector",
            WorkflowShortcutAction.ShowHideInspector);
        SetItem(ToggleFullScreenItem, "commandToggleFullScreen",
            WorkflowShortcutAction.ToggleFullScreen);
        SetItem(OpenLibraryItem, "shortcutOpenLibrary",
            WorkflowShortcutAction.OpenLibraryWorkspace);
        SetItem(OpenDevelopItem, "shortcutOpenDevelop",
            WorkflowShortcutAction.OpenDevelopWorkspace);
        SetItem(OpenPrintItem, "menuPrint", WorkflowShortcutAction.OpenPrintWorkspace);
    }

    private static void SetItem(
        MenuFlyoutItem item,
        string key,
        WorkflowShortcutAction action)
    {
        string text = AppResources.Get(key, "Text");
        item.Text = text;
        AutomationProperties.SetName(item, text);
        item.KeyboardAcceleratorTextOverride =
            WorkflowShortcutActions.Default(action).Display();
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
        RaiseCommand(sender, args, WorkflowShortcutAction.ImportImages);

    private void OnImportFolderClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.ImportFolder);

    private void OnRefreshLibraryClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.RefreshLibrary);

    private void OnLoadScannerClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.LoadScanner);

    private void OnQuickExportClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.QuickExport);

    private void OnExportClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.ExportPhoto);

    private void OnUndoClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.Undo);

    private void OnRedoClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.Redo);

    private void OnCopyDevelopSettingsClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.CopyDevelopSettings);

    private void OnPasteDevelopSettingsClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.PasteDevelopSettings);

    private void OnPickClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.PickPhoto);

    private void OnRejectClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.RejectPhoto);

    private void OnDeletePhotoClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.DeletePhoto);

    private void OnShowHideSidebarClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.ShowHideSidebar);

    private void OnShowHideFilmstripClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.ShowHideFilmstrip);

    private void OnShowHideInspectorClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.ShowHideInspector);

    private void OnToggleFullScreenClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.ToggleFullScreen);

    private void OnOpenLibraryClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.OpenLibraryWorkspace);

    private void OnOpenDevelopClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.OpenDevelopWorkspace);

    private void OnOpenPrintClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.OpenPrintWorkspace);

    private void RaiseCommand(object sender, RoutedEventArgs args, WorkflowShortcutAction action)
    {
        _ = sender;
        _ = args;
        CommandRequested?.Invoke(this, action);
    }
}
