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
        allItems = LibraryFrameListItems.From(host.Frames);
        ShowFilteredItems();

        bool hasFrames = allItems.Count > 0;
        LibraryContentPanel.Visibility = hasFrames ? Visibility.Visible : Visibility.Collapsed;
        EmptyLibraryPanel.Visibility = hasFrames ? Visibility.Collapsed : Visibility.Visible;

        string? issueSummary = LibraryFrameListItems.IssueSummary(host.Issues);
        LibraryIssueBar.Message = issueSummary ?? string.Empty;
        LibraryIssueBar.IsOpen = issueSummary is not null;
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
        FrameListView.ItemsSource = items;
        LibraryCountText.Text = items.Count.ToString(CultureInfo.CurrentCulture);
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

        ImportImagesButton.IsEnabled = false;
        EmptyImportImagesButton.IsEnabled = false;
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
