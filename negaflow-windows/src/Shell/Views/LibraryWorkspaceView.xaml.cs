using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Negaflow.Catalog;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views;

public sealed partial class LibraryWorkspaceView : UserControl
{
    private WorkspacePresentationState? workspaceState;
    private LibraryHostService? libraryHost;
    private Microsoft.UI.WindowId? importWindowId;
    private bool isResizing;
    private double liveWidth = ShellLayoutMetrics.LibraryControlsDefaultWidth;
    private IReadOnlyList<LibraryFrameListItem> allItems = [];
    private LibraryBrowserViewMode viewMode = LibraryBrowserViewMode.Folders;
    private FilmType selectedFilmType = FilmType.ColorNegative;

    public LibraryWorkspaceView()
    {
        InitializeComponent();
        LocalizeControls();
    }

    public void Initialize(WorkspacePresentationState state)
    {
        ArgumentNullException.ThrowIfNull(state);
        workspaceState = state;
        state.Changed += OnStateChanged;
        SynchronizeWidth(state.Current.LibraryControlsWidth);
        Unloaded += OnUnloaded;
    }

    /// <summary>
    /// 라이브러리 내용을 보여 줍니다. **UI 스레드에서만** 부르십시오. WinUI 는 STA 이고
    /// 컨트롤은 그것을 만든 스레드가 소유합니다.
    /// </summary>
    public void ShowLibrary(LibraryHostService host, Microsoft.UI.WindowId windowId)
    {
        ArgumentNullException.ThrowIfNull(host);

        libraryHost = host;
        importWindowId = windowId;
        allItems = LibraryFrameListItems.From(host.Frames, host.SourceAvailabilityByFrameId);
        ShowFilteredItems();

        bool hasFrames = allItems.Count > 0;
        LibraryContentPanel.Visibility = hasFrames ? Visibility.Visible : Visibility.Collapsed;
        EmptyLibraryPanel.Visibility = hasFrames ? Visibility.Collapsed : Visibility.Visible;

        string? issueSummary = LibraryFrameListItems.IssueSummary(host.Issues);
        LibraryIssueBar.Message = issueSummary ?? string.Empty;
        LibraryIssueBar.IsOpen = issueSummary is not null;

        host.RefreshAvailability(() =>
        {
            if (!ReferenceEquals(libraryHost, host))
            {
                return;
            }
            allItems = LibraryFrameListItems.From(host.Frames, host.SourceAvailabilityByFrameId);
            ShowFilteredItems();
        });
    }

    private void OnLibrarySearchTextChanged(object sender, TextChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        ShowFilteredItems();
    }

    private void ShowFilteredItems()
    {
        IReadOnlyList<LibraryFrameListItem> items =
            LibraryFrameListItems.Filter(allItems, LibrarySearchBox?.Text ?? string.Empty);
        if (libraryHost is null)
        {
            FrameListView.ItemsSource = items;
            LibraryCountText.Text = items.Count.ToString(CultureInfo.CurrentCulture);
            return;
        }

        LibraryBrowserProjection projection = LibraryBrowserProjector.Create(
            items,
            libraryHost.Folders,
            libraryHost.FolderAvailabilityById,
            viewMode,
            selectedFilmType);
        if (viewMode is LibraryBrowserViewMode.Folders or LibraryBrowserViewMode.FilmType)
        {
            FolderGroupedItems.Source = projection.FolderSections;
            FrameListView.ItemsSource = FolderGroupedItems.View;
        }
        else
        {
            FolderGroupedItems.Source = null;
            FrameListView.ItemsSource = projection.Items;
        }
        LibraryCountText.Text = projection.MatchedCount.ToString(CultureInfo.CurrentCulture);
        UpdateViewModeControls();
    }

    private void OnAllModeClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        viewMode = LibraryBrowserViewMode.All;
        ShowFilteredItems();
    }

    private void OnFoldersModeClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        viewMode = LibraryBrowserViewMode.Folders;
        ShowFilteredItems();
    }

    private void OnOfflineModeClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        viewMode = LibraryBrowserViewMode.Offline;
        ShowFilteredItems();
    }

    private void OnFilmTypeClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (sender is not MenuFlyoutItem { Tag: string value } ||
            !Enum.TryParse(value, out FilmType filmType))
        {
            return;
        }
        selectedFilmType = filmType;
        viewMode = LibraryBrowserViewMode.FilmType;
        ShowFilteredItems();
    }

    private async void OnImportClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (libraryHost is null || importWindowId is null)
        {
            return;
        }

        Microsoft.Windows.Storage.Pickers.FileOpenPicker picker = new(importWindowId.Value)
        {
            CommitButtonText = AppResources.Get("importSection", "Value"),
        };
        picker.FileTypeFilter.Add(".tif");
        picker.FileTypeFilter.Add(".tiff");
        picker.FileTypeFilter.Add(".jpg");
        picker.FileTypeFilter.Add(".jpeg");
        picker.FileTypeFilter.Add(".png");

        ImportImagesButton.IsEnabled = false;
        EmptyImportImagesButton.IsEnabled = false;
        ImportFoldersButton.IsEnabled = false;
        ImportStatusText.Text = string.Empty;
        try
        {
            IReadOnlyList<Microsoft.Windows.Storage.Pickers.PickFileResult> picked =
                await picker.PickMultipleFilesAsync();
            List<string> paths = [];
            foreach (Microsoft.Windows.Storage.Pickers.PickFileResult file in picked)
            {
                paths.Add(file.Path);
            }
            _ = libraryHost.Import(paths, DevelopmentProcess.C41);
            ShowLibrary(libraryHost, importWindowId.Value);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or ArgumentException or PathTooLongException)
        {
            ImportStatusText.Text = AppResources.Get("libraryImportFailed", "Text");
        }
        finally
        {
            ImportImagesButton.IsEnabled = true;
            EmptyImportImagesButton.IsEnabled = true;
            ImportFoldersButton.IsEnabled = true;
        }
    }

    private async void OnImportFoldersClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (libraryHost is null || importWindowId is null)
        {
            return;
        }

        Microsoft.Windows.Storage.Pickers.FolderPicker picker = new(importWindowId.Value)
        {
            CommitButtonText = AppResources.Get("importFolder", "Content"),
        };

        ImportImagesButton.IsEnabled = false;
        EmptyImportImagesButton.IsEnabled = false;
        ImportFoldersButton.IsEnabled = false;
        ImportStatusText.Text = string.Empty;
        try
        {
            Microsoft.Windows.Storage.Pickers.PickFolderResult? picked =
                await picker.PickSingleFolderAsync();
            if (picked is null)
            {
                return;
            }

            FolderImportResult imported = libraryHost.ImportFolders(
                [picked.Path],
                DevelopmentProcess.C41);
            if (!imported.IsSuccess)
            {
                ImportStatusText.Text = AppResources.Get("libraryImportFailed", "Text");
                return;
            }
            ImportStatusText.Text = AppResources.FormatIntegers(
                "libraryFolderImportResult",
                "Text",
                imported.AddedFrameCount,
                imported.AddedFolderCount);
            ShowLibrary(libraryHost, importWindowId.Value);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or ArgumentException or PathTooLongException)
        {
            ImportStatusText.Text = AppResources.Get("libraryImportFailed", "Text");
        }
        finally
        {
            ImportImagesButton.IsEnabled = true;
            EmptyImportImagesButton.IsEnabled = true;
            ImportFoldersButton.IsEnabled = true;
        }
    }

    private async void OnLocateOriginalClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (libraryHost is null || importWindowId is null ||
            sender is not Button { Tag: LibraryFrameListItem item })
        {
            return;
        }

        Microsoft.Windows.Storage.Pickers.FileOpenPicker picker = new(importWindowId.Value)
        {
            CommitButtonText = AppResources.Get("libraryLocateOriginal", "Content"),
        };
        picker.FileTypeFilter.Add(".tif");
        picker.FileTypeFilter.Add(".tiff");
        picker.FileTypeFilter.Add(".jpg");
        picker.FileTypeFilter.Add(".jpeg");
        picker.FileTypeFilter.Add(".png");

        try
        {
            Microsoft.Windows.Storage.Pickers.PickFileResult? picked = await picker.PickSingleFileAsync();
            if (picked is null)
            {
                return;
            }
            SourceRelinkPlan? plan = SourceRelinkPlanner.FilePlan(item.Frame.SourcePath, picked.Path);
            if (plan is null || !libraryHost.Relink(plan).IsSuccess)
            {
                ImportStatusText.Text = AppResources.Get("libraryRelinkFailed", "Text");
                return;
            }
            ShowLibrary(libraryHost, importWindowId.Value);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or ArgumentException or PathTooLongException)
        {
            ImportStatusText.Text = AppResources.Get("libraryRelinkFailed", "Text");
        }
    }

    private async void OnLocateFolderClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (libraryHost is null || importWindowId is null ||
            sender is not Button { Tag: LibraryBrowserFolderSection { IsRegistered: true } section })
        {
            return;
        }

        Microsoft.Windows.Storage.Pickers.FolderPicker picker = new(importWindowId.Value)
        {
            CommitButtonText = AppResources.Get("libraryLocateFolder", "Content"),
        };
        try
        {
            Microsoft.Windows.Storage.Pickers.PickFolderResult? picked =
                await picker.PickSingleFolderAsync();
            if (picked is null)
            {
                return;
            }

            SourceRelinkPlan plan = SourceRelinkPlanner.FolderPlan(
                section.Id,
                picked.Path,
                libraryHost.Frames);
            if (!libraryHost.Relink(plan).IsSuccess)
            {
                ImportStatusText.Text = AppResources.Get("libraryFolderRelinkFailed", "Text");
                return;
            }
            ShowLibrary(libraryHost, importWindowId.Value);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or ArgumentException or PathTooLongException)
        {
            ImportStatusText.Text = AppResources.Get("libraryFolderRelinkFailed", "Text");
        }
    }

    private void OnRootSizeChanged(object sender, SizeChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (!isResizing && workspaceState is not null)
        {
            SynchronizeWidth(workspaceState.Current.LibraryControlsWidth);
        }
    }

    private void OnResizeStarted(object sender, DragStartedEventArgs args)
    {
        _ = sender;
        _ = args;
        isResizing = true;
    }

    private void OnResizeDelta(object sender, DragDeltaEventArgs args)
    {
        _ = sender;
        WorkspaceLayout layout = WorkspaceLayoutCalculator.Calculate(Root.ActualWidth);
        liveWidth = layout.ClampLibraryControlsWidth(liveWidth + args.HorizontalChange);
        ControlsPanel.Width = liveWidth;
    }

    private void OnResizeCompleted(object sender, DragCompletedEventArgs args)
    {
        _ = sender;
        _ = args;
        isResizing = false;
        workspaceState?.SetLibraryControlsWidth(liveWidth);
    }

    private void OnStateChanged(object? sender, ShellPreferences preferences)
    {
        _ = sender;
        if (!isResizing)
        {
            SynchronizeWidth(preferences.LibraryControlsWidth);
        }
    }

    private void SynchronizeWidth(double storedWidth)
    {
        liveWidth = WorkspaceLayoutCalculator.Calculate(Root.ActualWidth)
            .ClampLibraryControlsWidth(storedWidth);
        ControlsPanel.Width = liveWidth;
    }

    private void LocalizeControls()
    {
        SetNameAndTooltip(ImportRailButton, "importSection");
        SetNameAndTooltip(FilesRailButton, "libraryFiles");
        SetNameAndTooltip(CollectionsRailButton, "libraryCollections");
        string import = AppResources.Get("importSection", "Text");
        ImportHeaderText.Text = import;
        ImportSectionText.Text = import;
        string importImages = AppResources.Get("importImages", "Content");
        SetButtonText(ImportImagesButton, importImages);
        SetButtonText(EmptyImportImagesButton, importImages);
        SetButtonText(ImportFoldersButton, AppResources.Get("importFolder", "Content"));
        SetButtonText(AllModeButton, AppResources.Get("libraryAllShort", "Text"));
        SetButtonText(FoldersModeButton, AppResources.Get("libraryFolders", "Text"));
        SetDropDownText(FilmTypeModeButton, AppResources.Get("libraryFilmType", "Text"));
        SetButtonText(OfflineModeButton, AppResources.Get("libraryOffline", "Text"));
        SetMenuItemText(ColorNegativeFilmTypeItem, AppResources.Get("filmTypeColorNegative", "Text"));
        SetMenuItemText(ColorPositiveFilmTypeItem, AppResources.Get("filmTypeColorPositive", "Text"));
        SetMenuItemText(BlackAndWhiteNegativeFilmTypeItem, AppResources.Get("filmTypeBlackAndWhiteNegative", "Text"));
        SetMenuItemText(BlackAndWhitePositiveFilmTypeItem, AppResources.Get("filmTypeBlackAndWhitePositive", "Text"));
        UpdateViewModeControls();
        LibraryCountText.Text = AppResources.FormatIntegers(
            "libraryResultCountFormat",
            "Value",
            0,
            0);
    }

    private static void SetNameAndTooltip(Button button, string resourceKey)
    {
        string text = AppResources.Get(resourceKey, "Value");
        AutomationProperties.SetName(button, text);
        ToolTipService.SetToolTip(button, text);
    }

    private static void SetButtonText(Button button, string text)
    {
        button.Content = text;
        AutomationProperties.SetName(button, text);
    }

    private static void SetDropDownText(DropDownButton button, string text)
    {
        button.Content = text;
        AutomationProperties.SetName(button, text);
        ToolTipService.SetToolTip(button, text);
    }

    private static void SetMenuItemText(MenuFlyoutItem item, string text)
    {
        item.Text = text;
        AutomationProperties.SetName(item, text);
    }

    private void UpdateViewModeControls()
    {
        SetModeAppearance(AllModeButton, viewMode == LibraryBrowserViewMode.All);
        SetModeAppearance(FoldersModeButton, viewMode == LibraryBrowserViewMode.Folders);
        SetModeAppearance(FilmTypeModeButton, viewMode == LibraryBrowserViewMode.FilmType);
        SetModeAppearance(OfflineModeButton, viewMode == LibraryBrowserViewMode.Offline);
    }

    private static void SetModeAppearance(Control control, bool selected)
    {
        control.Background = selected
            ? (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["NegaflowSelectionBrush"]
            : (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["NegaflowSubtleFillBrush"];
        AutomationProperties.SetItemStatus(
            control,
            AppResources.Get(selected ? "selected" : "notSelected", "Value"));
    }

    private void OnUnloaded(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (workspaceState is not null)
        {
            workspaceState.Changed -= OnStateChanged;
        }
    }
}
