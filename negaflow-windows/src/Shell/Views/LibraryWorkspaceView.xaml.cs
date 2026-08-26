using System.IO;
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

    /// <summary>진단이 스캔 상태를 읽어 가는 자리입니다.</summary>
    internal Library.Scanner.LibraryScanPanel ScanPanelForDiagnostics => ControlsPanel.ScanPanel;
    internal LibraryHostService? libraryHost;
    internal ThumbnailService? thumbnails;
    internal Views.Library.Scanner.ScanSessionHost? scanSessionHost;
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
        using (Diagnostics.StartupTrace.Measure("LibraryWorkspaceView.xaml"))
        {
            InitializeComponent();
        }
        // 왼쪽 소스 패널 XAML 은 UserControl 로 옮겼습니다. 이벤트는 옮기기 전과 같은
        // 이 타입의 메서드로 돌아옵니다.
        ControlsPanel.Owner = this;
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
        Root.ActualThemeChanged += (_, _) => rail.Update();
        ControlsPanel.ScanPanel.IsWanted = () => ControlsPanel.ImportScannerButton.IsChecked == true;
        ControlsPanel.ScanPanel.ExpandRequested += (_, _) => ControlsPanel.ImportScannerButton.IsChecked = true;
        ControlsPanel.ImportScannerButton.Checked += OnImportScannerToggled;
        ControlsPanel.ImportScannerButton.Unchecked += OnImportScannerToggled;
        ControlsPanel.ScanPanel.LibraryChanged += OnEmbeddedLibraryChanged;
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
        ControlsPanel.FilesSourceTree.FrameSelected += (_, frameId) => selection.SelectFrame(frameId);
        ControlsPanel.FilesSourceTree.LibraryChanged += OnEmbeddedLibraryChanged;
        ControlsPanel.FilesSourceTree.StatusChanged += (_, text) => ControlsPanel.ImportStatusText.Text = text;
        ControlsPanel.FilesSourceTree.LocateFolderRequested += (_, folderPath) =>
            import.LocateFolder(folderPath);
        ControlsPanel.FilesSourceTree.FolderRemoveRequested += OnFolderRemoveRequested;
        ControlsPanel.CollectionsPanel.FilterChanged += (_, _) => ShowFilteredItems();
        ControlsPanel.CollectionsPanel.StoredQueryApplied += (_, query) => ApplyStoredQuery(query);
        copy.Localize();
        Loaded += OnLoaded;
    }

    /// <summary>
    /// 폴더 머리줄의 ✕ 입니다. macOS <c>removeLibraryFolderSection</c> 과 같은 뜻 — 그 폴더의
    /// 사진을 라이브러리에서 뺍니다. <b>파일은 지우지 않습니다.</b>
    /// </summary>
    /// <summary>
    /// 현상 · 인화의 "파일" 탭도 같은 컨트롤이라 같은 ✕ 를 냅니다. 그 ✕ 는 라이브러리와
    /// <b>같은 처리</b>로 와야 합니다 — 화면마다 다른 결과가 나면 공통 탭이 아닙니다.
    /// </summary>
    internal void RemoveFolderFromLibrary(string folderPath) =>
        OnFolderRemoveRequested(this, folderPath);

    /// <summary>맥락 메뉴의 "폴더에서 보기" 도 같은 처리로 옵니다.</summary>
    internal void LocateLibraryFolder(string folderPath) => import.LocateFolder(folderPath);

    private void OnFolderRemoveRequested(object? sender, string folderPath)
    {
        _ = sender;
        if (libraryHost is not { } host)
        {
            return;
        }
        IReadOnlyList<LibraryFrameListItem> inFolder =
            [.. allItems.Where(item => string.Equals(
                Path.GetDirectoryName(item.Frame.SourcePath),
                Path.TrimEndingDirectorySeparator(folderPath),
                StringComparison.OrdinalIgnoreCase))];
        _ = host;
        actions.RemoveFromLibrary(inFolder);
    }

    /// <summary>
    /// macOS 워크플로 메뉴의 프로세스 명령입니다. 좌측탭에는 이 구획이 없고(폴더 머리줄이
    /// 그 일을 합니다) 명령은 모델을 직접 고칩니다 — <c>AppModel.applyDevelopmentProcess</c>.
    /// </summary>
    internal void ApplyDevelopProcessShortcut(WorkflowShortcutAction action)
    {
        if (libraryHost is not { } host || selection.ActionableFrame() is not { } frame)
        {
            return;
        }
        if (DevelopDefaultsCommands.ApplyProcess(
                host,
                frame,
                DevelopDefaultsCommands.ProcessFor(action)) == LibraryFrameError.None)
        {
            OnEmbeddedLibraryChanged(this, EventArgs.Empty);
        }
    }

    /// <summary>macOS <c>AppModel.applyDevelopTarget</c> — 메뉴·단축키의 타깃 전환입니다.</summary>
    internal void ApplyDevelopTargetShortcut(DevelopTarget target)
    {
        if (libraryHost is not { } host || selection.ActionableFrame() is not { } frame)
        {
            return;
        }
        if (DevelopDefaultsCommands.ApplyTarget(host, frame, target) == LibraryFrameError.None)
        {
            OnEmbeddedLibraryChanged(this, EventArgs.Empty);
        }
    }

    /// <summary>언어가 바뀌면 문구를 다시 겁니다. macOS 는 model.appLanguage 하나로 됩니다.</summary>
    public void Localize()
    {
        copy.Localize();
        ControlsPanel.ScanPanel.Localize();
        ControlsPanel.CollectionsPanel.Localize();
        CullingSurface.Localize();
        // 카드 이름("사진 %d")과 필름 종류("컬러 네거티브")는 **항목을 만들 때** 정해집니다.
        // `copy.Localize()` 가 이름 서식을 새 언어로 갈아 끼운 **뒤에** 다시 만듭니다.
        if (libraryHost is { } host)
        {
            allItems = LibraryFrameListItems.From(host.Frames, host.SourceAvailabilityByFrameId);
        }
        ShowFilteredItems();
    }

    public void Initialize(WorkspacePresentationState state)
    {
        ArgumentNullException.ThrowIfNull(state);
        workspaceState = state;
        // 좌측 "파일" 탭의 접기 상태는 세 화면이 함께 봅니다.
        ControlsPanel.FilesSourceTree.AttachPresentation(state);
        state.Changed += layout.OnStateChanged;
        ControlsPanel.ScanPanel.ApplyDefaultRotation(state.Current.DefaultScanRotation);
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
            thumbnails.ThumbnailReady -= OnThumbnailReady;
        }
        thumbnails = service;
        thumbnails.ThumbnailReady += OnThumbnailReady;
    }

    /// <summary>
    /// 라이브러리 내용을 보여 줍니다. <b>UI 스레드에서만</b> 부르십시오. WinUI 는 STA 이고
    /// 컨트롤은 그것을 만든 스레드가 소유합니다.
    /// </summary>
    public void ShowLibrary(LibraryHostService host, Microsoft.UI.WindowId windowId)
    {
        ArgumentNullException.ThrowIfNull(host);

        if (libraryHost is { } previous)
        {
            previous.SelectionChanged -= OnHostSelectionChanged;
        }
        libraryHost = host;
        // 격자·현상·인화 어디서 골랐든 "파일" 탭의 파란 강조가 따라갑니다 — 인화뷰가 이미
        // 같은 신호를 쓰고 있으며, 목록을 다시 짓지 않고 강조만 옮깁니다.
        host.SelectionChanged += OnHostSelectionChanged;
        importWindowId = windowId;
        ControlsPanel.ScanPanel.Bind(host);
        ControlsPanel.ScanPanel.WindowId = windowId;
        ControlsPanel.FilesSourceTree.Bind(host);
        ControlsPanel.CollectionsPanel.Bind(
            host,
            () => FrameListView.SelectedItems.OfType<LibraryFrameListItem>().Select(item => item.Id),
            () => LibraryStoredQuery.From(quickFilters, LibrarySearchBox?.Text));
        allItems = LibraryFrameListItems.From(host.Frames, host.SourceAvailabilityByFrameId);
        ControlsPanel.CollectionsPanel.Rebuild();
        ShowFilteredItems();

        bool hasFrames = allItems.Count > 0;
        LibraryContentPanel.Visibility = hasFrames ? Visibility.Visible : Visibility.Collapsed;
        EmptyLibraryPanel.Visibility = hasFrames ? Visibility.Collapsed : Visibility.Visible;

        string? issueSummary = LibraryFrameListItems.IssueSummary(host.Issues);
        LibraryIssueBar.Message = issueSummary ?? string.Empty;
        LibraryIssueBar.IsOpen = issueSummary is not null;

        PreviewTrace.Write(
            $"files.availability ask frames={host.Frames.Count} folders={host.Folders.Count}");
        host.RefreshAvailability(() =>
        {
            if (!ReferenceEquals(libraryHost, host))
            {
                return;
            }
            PreviewTrace.Write(
                $"files.availability done frames={host.SourceAvailabilityByFrameId.Count} " +
                $"folders={host.FolderAvailabilityById.Count}");
            host.ReconcileActiveFrameAvailability();
            allItems = LibraryFrameListItems.From(host.Frames, host.SourceAvailabilityByFrameId);
            ShowFilteredItems();
        });
    }

    /// <summary>
    /// 별·깃발·제외만 바뀌었습니다. 격자를 다시 짓지 않고 그 값만 갈아 끼웁니다.
    /// </summary>
    /// <remarks>
    /// 예전에는 여기서 <see cref="ShowLibrary"/> 를 다시 불렀습니다. 그러면 별 하나에 사이드탭
    /// 전부가 다시 세워지고 원본 존재 확인이 사진 수만큼 다시 돌아, 별을 누를 때마다 눈에 보이게
    /// 멈췄습니다.
    /// </remarks>
    internal void RefreshFrameMarks()
    {
        if (libraryHost is not { } host)
        {
            return;
        }
        _ = LibraryFrameListItems.Refresh(allItems, host.Frames);
    }

    private void OnHostSelectionChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        ControlsPanel.FilesSourceTree.SelectedFrameId = libraryHost?.ActiveFrameId;
    }

    /// <summary>사용자가 라이브러리에서 현상으로 넘기려는 frame 입니다.</summary>
    public event EventHandler<LibraryFrameListItem>? FrameOpenRequested;

    internal void RaiseFrameOpenRequested(LibraryFrameListItem item) =>
        FrameOpenRequested?.Invoke(this, item);

    /// <summary>
    /// 폴더 머리줄의 적용 단추가 그 폴더의 사진을 통째로 바꿔 놓았을 때입니다.
    /// </summary>
    /// <remarks>
    /// macOS 는 <c>ScanFrame</c> 관찰로 현상뷰와 인화뷰가 저절로 따라오지만,
    /// WinUI 는 그런 관찰이 없어 바뀌었다는 것을 직접 알려 줘야 합니다.
    /// </remarks>
    public event EventHandler<IReadOnlyList<string>>? FolderDevelopmentApplied;

    internal void RaiseFolderDevelopmentApplied(IReadOnlyList<string> frameIds) =>
        FolderDevelopmentApplied?.Invoke(this, frameIds);

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
        // macOS `if !searchText.isEmpty` — 글자가 있을 때만 지우기가 나옵니다.
        LibraryClearSearchButton.Visibility = LibrarySearchBox.Text.Length == 0
            ? Visibility.Collapsed
            : Visibility.Visible;
        ShowFilteredItems();
    }

    /// <summary>macOS `onClearSearch` — 검색어를 지우고 목록을 되돌립니다.</summary>
    private void OnLibraryClearSearchClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        LibrarySearchBox.Text = string.Empty;
    }

    internal void OnSourceRailClicked(object sender, RoutedEventArgs args) =>
        rail.OnClicked(sender, args);

    private void OnFrameDragStarting(object sender, DragItemsStartingEventArgs args) =>
        selection.OnDragStarting(sender, args);

    private void OnFolderProcessChanged(object? sender, RoutedEventArgs args) =>
        rail.OnFolderProcessChanged(sender, args);

    private void OnFolderTargetChanged(object? sender, RoutedEventArgs args) =>
        rail.OnFolderTargetChanged(sender, args);

    private void OnFolderApplyClicked(object? sender, RoutedEventArgs args) =>
        rail.OnFolderApplyClicked(sender, args);

    private void OnFolderDisclosureClicked(object? sender, RoutedEventArgs args) =>
        rail.OnFolderDisclosureClicked(sender, args);

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
        await ControlsPanel.ScanPanel.DetectOnLoadAsync();
    }

    /// <summary>macOS 스캐너 메뉴가 읽는 값입니다.</summary>
    internal ScannerMenuState ScannerMenuState => ControlsPanel.ScanPanel.MenuState;

    internal bool HasScanner => ControlsPanel.ScanPanel.HasScanner;

    internal bool SupportsPreview => ControlsPanel.ScanPanel.SupportsPreview;

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
