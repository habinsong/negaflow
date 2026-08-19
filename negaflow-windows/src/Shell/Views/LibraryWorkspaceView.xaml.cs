using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media.Imaging;
using Negaflow.Catalog;
using Negaflow.Shell.Library;
using Negaflow.Shell.Shortcuts;
using Negaflow.Shell.Views.Library.Browser;
using Negaflow.Shell.Views.Library.Host;

namespace Negaflow.Shell.Views;

public sealed partial class LibraryWorkspaceView : UserControl
{
    internal WorkspacePresentationState? workspaceState;
    internal LibraryHostService? libraryHost;
    internal ThumbnailService? thumbnails;
    internal Microsoft.UI.WindowId? importWindowId;
    internal bool isResizing;
    internal double liveWidth = ShellLayoutMetrics.LibraryControlsDefaultWidth;
    internal IReadOnlyList<LibraryFrameListItem> allItems = [];
    internal LibraryBrowserViewMode viewMode = LibraryBrowserViewMode.Folders;
    internal FilmType selectedFilmType = FilmType.ColorNegative;
    internal LibrarySortKey sortKey = LibrarySortKey.InputOrder;
    internal bool sortAscending = true;
    internal LibraryQuickFilterState quickFilters = LibraryQuickFilterState.None;
    internal LibrarySourceKind sourceKind = LibrarySourceKind.Importing;
    internal bool isSynchronizingFilters;
    internal bool isSynchronizingFrameSelection;
    internal readonly LibraryImportActions import;
    internal readonly LibraryBrowserFilters filters;
    internal readonly LibraryWorkspaceCopy copy;
    internal readonly LibraryThumbnails thumbs;
    internal readonly LibraryGridSelection selection;
    internal readonly LibraryGridProjection projection;
    internal readonly LibraryFrameActions actions;
    internal readonly LibraryFrameMenu menu;
    internal readonly LibraryShortcuts shortcuts;
    internal readonly LibrarySourceRail rail;
    internal readonly LibraryWorkspaceLayout layout;

    public LibraryWorkspaceView()
    {
        InitializeComponent();
        import = new LibraryImportActions(this);
        filters = new LibraryBrowserFilters(this);
        copy = new LibraryWorkspaceCopy(this);
        thumbs = new LibraryThumbnails(this);
        selection = new LibraryGridSelection(this);
        projection = new LibraryGridProjection(this);
        actions = new LibraryFrameActions(this);
        menu = new LibraryFrameMenu(this);
        shortcuts = new LibraryShortcuts(this);
        rail = new LibrarySourceRail(this);
        layout = new LibraryWorkspaceLayout(this);
        ScanPanel.IsWanted = () => ImportScannerButton.IsChecked == true;
        ScanPanel.ExpandRequested += (_, _) => ImportScannerButton.IsChecked = true;
        ScanPanel.LibraryChanged += OnEmbeddedLibraryChanged;
        DevelopDefaultsPanel.LibraryChanged += OnEmbeddedLibraryChanged;
        CullingSurface.AttachChrome(
            CullingGridButton,
            CullingSurveyButton,
            CullingCompareButton,
            CullingSelectionCountText);
        CullingSurface.Bind(item =>
        {
            FrameListView.SelectedItem = item;
            ShowFilteredItems();
        });
        FilesSourceTree.FrameSelected += (_, frameId) => selection.SelectFrame(frameId);
        FilesSourceTree.LibraryChanged += OnEmbeddedLibraryChanged;
        FilesSourceTree.StatusChanged += (_, text) => ImportStatusText.Text = text;
        CollectionsPanel.FilterChanged += (_, _) => ShowFilteredItems();
        CollectionsPanel.StoredQueryApplied += (_, query) => ApplyStoredQuery(query);
        copy.Localize();
        Loaded += OnLoaded;
    }

    /// <summary>언어가 바뀌면 문구를 다시 겁니다. macOS 는 model.appLanguage 하나로 됩니다.</summary>
    public void Localize()
    {
        copy.Localize();
        ScanPanel.Localize();
        DevelopDefaultsPanel.Localize();
        CollectionsPanel.Localize();
        CullingSurface.Localize();
    }

    public void Initialize(WorkspacePresentationState state)
    {
        ArgumentNullException.ThrowIfNull(state);
        workspaceState = state;
        state.Changed += layout.OnStateChanged;
        ScanPanel.ApplyDefaultRotation(state.Current.DefaultScanRotation);
        layout.SynchronizeWidth(state.Current.LibraryControlsWidth);
        Unloaded += OnUnloaded;
    }

    /// <summary>
    /// 카드 썸네일을 만들어 주는 서비스입니다. 앱 시작 때 한 번 연결하고, 준비되는 대로 카드가
    /// 그림만 바꿔 낍니다.
    /// </summary>
    public void AttachThumbnails(ThumbnailService service)
    {
        ArgumentNullException.ThrowIfNull(service);
        if (thumbnails is not null)
        {
            thumbnails.ThumbnailReady -= thumbs.OnReady;
        }
        thumbnails = service;
        thumbnails.ThumbnailReady += thumbs.OnReady;
    }

    /// <summary>
    /// 라이브러리 내용을 보여 줍니다. <b>UI 스레드에서만</b> 부르십시오. WinUI 는 STA 이고
    /// 컨트롤은 그것을 만든 스레드가 소유합니다.
    /// </summary>
    public void ShowLibrary(LibraryHostService host, Microsoft.UI.WindowId windowId)
    {
        ArgumentNullException.ThrowIfNull(host);

        libraryHost = host;
        importWindowId = windowId;
        ScanPanel.Bind(host);
        DevelopDefaultsPanel.Bind(host, selection.ActionableFrame);
        FilesSourceTree.Bind(host);
        CollectionsPanel.Bind(
            host,
            () => FrameListView.SelectedItems.OfType<LibraryFrameListItem>().Select(item => item.Id),
            () => LibraryStoredQuery.From(quickFilters, LibrarySearchBox?.Text));
        allItems = LibraryFrameListItems.From(host.Frames, host.SourceAvailabilityByFrameId);
        CollectionsPanel.Rebuild();
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
            host.ReconcileActiveFrameAvailability();
            allItems = LibraryFrameListItems.From(host.Frames, host.SourceAvailabilityByFrameId);
            ShowFilteredItems();
        });
    }

    /// <summary>사용자가 라이브러리에서 현상으로 넘기려는 frame 입니다.</summary>
    public event EventHandler<LibraryFrameListItem>? FrameOpenRequested;

    internal void RaiseFrameOpenRequested(LibraryFrameListItem item) =>
        FrameOpenRequested?.Invoke(this, item);

    public void PresentScannerSetup() => rail.PresentScanner();

    public bool InvokeShortcut(WorkflowShortcutAction action) => shortcuts.Invoke(action);

    /// <summary>
    /// JPEG 바이트를 그대로 <c>BitmapImage</c> 에 흘려 넣습니다. 디코드는 WinUI 가 필요할 때
    /// 하므로, 화면 밖 카드까지 미리 펼쳐 두지 않습니다.
    /// </summary>
    internal static BitmapImage? DecodeThumbnail(byte[] jpeg) => LibraryThumbnails.Decode(jpeg);

    internal void ShowFilteredItems() => projection.Show();

    internal IReadOnlyList<string> CurrentRollFrameIds()
    {
        if (libraryHost?.ActiveRollId is not { } activeRollId)
        {
            return [];
        }
        return libraryHost.Rolls.FirstOrDefault(roll =>
            string.Equals(roll.Id, activeRollId, StringComparison.Ordinal))?.FrameIds ?? [];
    }

    private void OnFrameContainerChanging(ListViewBase sender, ContainerContentChangingEventArgs args) =>
        thumbs.OnContainerChanging(sender, args);

    private void OnFrameDoubleTapped(object sender, DoubleTappedRoutedEventArgs args) =>
        selection.OnDoubleTapped(sender, args);

    internal void OnFrameSelectionChanged(object sender, SelectionChangedEventArgs args) =>
        selection.OnSelectionChanged(sender, args);

    private void OnCullingModeClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        CullingSurface.ToggleFrom(sender);
        ShowFilteredItems();
    }

    private void OnEmbeddedLibraryChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (libraryHost is { } host)
        {
            ShowLibrary(host, importWindowId ?? default);
        }
    }

    private void OnFrameRightTapped(object sender, RightTappedRoutedEventArgs args) =>
        menu.OnRightTapped(sender, args);

    private void OnRatingCommitted(object? sender, int rating) =>
        actions.OnRatingCommitted(sender, rating);

    private void OnLibrarySearchTextChanged(object sender, TextChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        ShowFilteredItems();
    }

    private void OnSourceRailClicked(object sender, RoutedEventArgs args) =>
        rail.OnClicked(sender, args);

    private void OnFrameDragStarting(object sender, DragItemsStartingEventArgs args) =>
        selection.OnDragStarting(sender, args);

    private void OnFolderProcessChanged(object sender, SelectionChangedEventArgs args) =>
        rail.OnFolderProcessChanged(sender, args);

    private void OnFiltersToggled(object sender, RoutedEventArgs args) =>
        filters.OnFiltersToggled(sender, args);

    private void OnQuickFilterToggled(object sender, RoutedEventArgs args) =>
        filters.OnQuickFilterToggled(sender, args);

    private void OnRatingFilterClicked(object sender, RoutedEventArgs args) =>
        filters.OnRatingFilterClicked(sender, args);

    private void OnClearFiltersClicked(object sender, RoutedEventArgs args) =>
        filters.OnClearFiltersClicked(sender, args);

    private void OnSortKeyClicked(object sender, RoutedEventArgs args) =>
        filters.OnSortKeyClicked(sender, args);

    private void OnSortDirectionClicked(object sender, RoutedEventArgs args) =>
        filters.OnSortDirectionClicked(sender, args);

    private void OnCardSizeDecreaseClicked(object sender, RoutedEventArgs args) =>
        filters.OnCardSizeDecreaseClicked(sender, args);

    private void OnCardSizeIncreaseClicked(object sender, RoutedEventArgs args) =>
        filters.OnCardSizeIncreaseClicked(sender, args);

    private void OnCardSizeResetClicked(object sender, RoutedEventArgs args) =>
        filters.OnCardSizeResetClicked(sender, args);

    private void OnAllModeClicked(object sender, RoutedEventArgs args) =>
        filters.OnAllModeClicked(sender, args);

    private void OnFoldersModeClicked(object sender, RoutedEventArgs args) =>
        filters.OnFoldersModeClicked(sender, args);

    private void OnOfflineModeClicked(object sender, RoutedEventArgs args) =>
        filters.OnOfflineModeClicked(sender, args);

    private void OnFilmTypeClicked(object sender, RoutedEventArgs args) =>
        filters.OnFilmTypeClicked(sender, args);

    internal void OnImportClicked(object sender, RoutedEventArgs args) =>
        import.OnImagesClicked(sender, args);

    internal void OnImportFoldersClicked(object sender, RoutedEventArgs args) =>
        import.OnFoldersClicked(sender, args);

    private void OnLocateOriginalClicked(object sender, RoutedEventArgs args) =>
        import.OnLocateOriginalClicked(sender, args);

    private void OnLocateFolderClicked(object sender, RoutedEventArgs args) =>
        import.OnLocateFolderClicked(sender, args);

    private void OnRootSizeChanged(object sender, SizeChangedEventArgs args) =>
        layout.OnRootSizeChanged(sender, args);

    private void OnResizeStarted(object sender, DragStartedEventArgs args) =>
        layout.OnResizeStarted(sender, args);

    private void OnResizeDelta(object sender, DragDeltaEventArgs args) =>
        layout.OnResizeDelta(sender, args);

    private void OnResizeCompleted(object sender, DragCompletedEventArgs args) =>
        layout.OnResizeCompleted(sender, args);

    private async void OnLoaded(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        await ScanPanel.DetectOnLoadAsync();
    }

    /// <summary>macOS 스캐너 메뉴가 읽는 값입니다.</summary>
    internal ScannerMenuState ScannerMenuState => ScanPanel.MenuState;

    /// <summary>스캔 세션 값이 바뀌면 메뉴막대가 따라오도록 셸에 알립니다.</summary>
    internal event EventHandler? ScannerMenuStateChanged
    {
        add => ScanPanel.MenuStateChanged += value;
        remove => ScanPanel.MenuStateChanged -= value;
    }

    /// <summary>macOS 스캐너 메뉴의 여섯 명령입니다. 패널 단추와 같은 길을 탑니다.</summary>
    internal bool InvokeScannerShortcut(WorkflowShortcutAction action)
    {
        switch (action)
        {
            case WorkflowShortcutAction.DetectScanners:
                _ = ScanPanel.DetectScannersFromMenuAsync();
                return true;
            case WorkflowShortcutAction.ToggleScannerSimulator:
                _ = ScanPanel.ToggleSimulatorFromMenuAsync();
                return true;
            case WorkflowShortcutAction.PreviewScan:
                _ = ScanPanel.PreviewScanFromMenuAsync();
                return true;
            case WorkflowShortcutAction.ScanFrame:
                _ = ScanPanel.ScanFrameFromMenuAsync();
                return true;
            case WorkflowShortcutAction.AddFlatbedFrame:
                ScanPanel.AddFlatbedFrameFromMenu();
                return true;
            case WorkflowShortcutAction.RemoveFlatbedFrame:
                ScanPanel.RemoveFlatbedFrameFromMenu();
                return true;
            default:
                return false;
        }
    }

    private void OnImportScannerClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        _ = ScanPanel.OpenAsync();
    }

    /// <summary>저장한 조건을 검색어와 빠른 필터에 되돌립니다.</summary>
    private void ApplyStoredQuery(LibraryStoredQuery query)
    {
        quickFilters = query.ToQuickFilters(CurrentRollFrameIds());
        isSynchronizingFilters = true;
        try
        {
            if (LibrarySearchBox is not null)
            {
                LibrarySearchBox.Text = query.SearchText;
            }
        }
        finally
        {
            isSynchronizingFilters = false;
        }
        ShowFilteredItems();
    }

    private void OnUnloaded(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (workspaceState is not null)
        {
            workspaceState.Changed -= layout.OnStateChanged;
        }
    }
}
