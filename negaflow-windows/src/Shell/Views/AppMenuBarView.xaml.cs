using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Shortcuts;

namespace Negaflow.Shell.Views;

/// <summary>
/// macOS <c>AppStandardMenuCommands</c> 와 <c>AppWorkflowMenuCommands</c> 의
/// 앱·파일·편집·보기·라이브러리·사진 메뉴입니다. Windows 에는 시스템 앱 메뉴가 없어서 창 안
/// <see cref="MenuBar"/> 가 그 자리입니다.
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

        string library = AppResources.Get("menuLibrary", "Text");
        LibraryMenu.Title = library;
        AutomationProperties.SetName(LibraryMenu, library);
        SetItem(LibraryImportImagesItem, "shortcutImportImages", WorkflowShortcutAction.ImportImages);
        SetItem(LibraryImportFolderItem, "shortcutImportFolder", WorkflowShortcutAction.ImportFolder);
        SetItem(LibraryRefreshItem, "shortcutRefreshLibrary", WorkflowShortcutAction.RefreshLibrary);
        SetItem(LibraryLoadScannerItem, "loadScanner", WorkflowShortcutAction.LoadScanner);
        SetItem(LibraryGridItem, "libraryCullingGrid", WorkflowShortcutAction.LibraryGrid);
        SetItem(LibraryCompareItem, "libraryCullingCompare", WorkflowShortcutAction.LibraryCompare);
        SetItem(LibrarySurveyItem, "libraryCullingSurvey", WorkflowShortcutAction.LibrarySurvey);

        string photo = AppResources.Get("shortcutGroupPhoto", "Text");
        PhotoMenu.Title = photo;
        AutomationProperties.SetName(PhotoMenu, photo);
        SetItem(PreviousPhotoItem, "shortcutPreviousPhoto", WorkflowShortcutAction.PreviousPhoto);
        SetItem(NextPhotoItem, "shortcutNextPhoto", WorkflowShortcutAction.NextPhoto);
        SetItem(PhotoPickItem, "shortcutPickPhoto", WorkflowShortcutAction.PickPhoto);
        SetItem(ClearPickItem, "shortcutClearPick", WorkflowShortcutAction.ClearPick);
        SetItem(PhotoRejectItem, "shortcutRejectPhoto", WorkflowShortcutAction.RejectPhoto);
        SetItem(PhotoDeleteItem, "shortcutDeletePhoto", WorkflowShortcutAction.DeletePhoto);
        SetItem(RateZeroItem, "shortcutRateZero", WorkflowShortcutAction.RateZero);
        SetStarItem(RateOneItem, 1, WorkflowShortcutAction.RateOne);
        SetStarItem(RateTwoItem, 2, WorkflowShortcutAction.RateTwo);
        SetStarItem(RateThreeItem, 3, WorkflowShortcutAction.RateThree);
        SetStarItem(RateFourItem, 4, WorkflowShortcutAction.RateFour);
        SetStarItem(RateFiveItem, 5, WorkflowShortcutAction.RateFive);
        SetCaption(VirtualCopyItem, AppResources.Get("libraryVirtualCopy", "Content"),
            WorkflowShortcutAction.CreateVirtualCopy);
        SetItem(PhotoCopyDevelopItem, "shortcutCopyDevelopSettings",
            WorkflowShortcutAction.CopyDevelopSettings);
        SetItem(PhotoPasteDevelopItem, "shortcutPasteDevelopSettings",
            WorkflowShortcutAction.PasteDevelopSettings);
        SetItem(RotateLeftItem, "shortcutRotateLeft", WorkflowShortcutAction.RotateLeft);
        SetItem(RotateRightItem, "shortcutRotateRight", WorkflowShortcutAction.RotateRight);
        SetItem(FlipHorizontalItem, "shortcutFlipHorizontal",
            WorkflowShortcutAction.FlipHorizontal);
        SetItem(FlipVerticalItem, "shortcutFlipVertical", WorkflowShortcutAction.FlipVertical);
    }

    private static void SetItem(
        MenuFlyoutItem item,
        string key,
        WorkflowShortcutAction action) =>
        SetCaption(item, AppResources.Get(key, "Text"), action);

    private static void SetStarItem(
        MenuFlyoutItem item,
        int value,
        WorkflowShortcutAction action) =>
        SetCaption(item, AppResources.FormatIntegers("libraryStarFormat", "Text", value), action);

    private static void SetCaption(
        MenuFlyoutItem item,
        string text,
        WorkflowShortcutAction action)
    {
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

    private void OnLibraryGridClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.LibraryGrid);

    private void OnLibraryCompareClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.LibraryCompare);

    private void OnLibrarySurveyClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.LibrarySurvey);

    private void OnPreviousPhotoClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.PreviousPhoto);

    private void OnNextPhotoClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.NextPhoto);

    private void OnClearPickClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.ClearPick);

    private void OnRateZeroClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.RateZero);

    private void OnRateOneClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.RateOne);

    private void OnRateTwoClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.RateTwo);

    private void OnRateThreeClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.RateThree);

    private void OnRateFourClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.RateFour);

    private void OnRateFiveClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.RateFive);

    private void OnVirtualCopyClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.CreateVirtualCopy);

    private void OnRotateLeftClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.RotateLeft);

    private void OnRotateRightClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.RotateRight);

    private void OnFlipHorizontalClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.FlipHorizontal);

    private void OnFlipVerticalClick(object sender, RoutedEventArgs args) =>
        RaiseCommand(sender, args, WorkflowShortcutAction.FlipVertical);

    private void RaiseCommand(object sender, RoutedEventArgs args, WorkflowShortcutAction action)
    {
        _ = sender;
        _ = args;
        CommandRequested?.Invoke(this, action);
    }
}
