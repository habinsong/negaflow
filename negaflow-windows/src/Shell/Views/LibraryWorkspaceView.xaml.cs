using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media.Imaging;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Shortcuts;
using Windows.ApplicationModel.DataTransfer;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views;

public sealed partial class LibraryWorkspaceView : UserControl
{
    private WorkspacePresentationState? workspaceState;
    private LibraryHostService? libraryHost;
    private ThumbnailService? thumbnails;
    private Microsoft.UI.WindowId? importWindowId;
    private bool isResizing;
    private double liveWidth = ShellLayoutMetrics.LibraryControlsDefaultWidth;
    private IReadOnlyList<LibraryFrameListItem> allItems = [];
    private LibraryBrowserViewMode viewMode = LibraryBrowserViewMode.Folders;
    private FilmType selectedFilmType = FilmType.ColorNegative;
    private LibrarySortKey sortKey = LibrarySortKey.InputOrder;
    private bool sortAscending = true;
    private LibraryQuickFilterState quickFilters = LibraryQuickFilterState.None;
    private LibrarySourceKind sourceKind = LibrarySourceKind.Importing;
    private bool isSynchronizingFilters;
    private bool isSynchronizingFrameSelection;

    public LibraryWorkspaceView()
    {
        InitializeComponent();
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
        FilesSourceTree.FrameSelected += OnFilesSourceFrameSelected;
        FilesSourceTree.LibraryChanged += OnEmbeddedLibraryChanged;
        FilesSourceTree.StatusChanged += (_, text) => ImportStatusText.Text = text;
        CollectionsPanel.FilterChanged += (_, _) => ShowFilteredItems();
        CollectionsPanel.StoredQueryApplied += (_, query) => ApplyStoredQuery(query);
        LocalizeControls();
        Loaded += OnLoaded;
    }

    public void Initialize(WorkspacePresentationState state)
    {
        ArgumentNullException.ThrowIfNull(state);
        workspaceState = state;
        state.Changed += OnStateChanged;
        ScanPanel.ApplyDefaultRotation(state.Current.DefaultScanRotation);
        SynchronizeWidth(state.Current.LibraryControlsWidth);
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
    /// 라이브러리 내용을 보여 줍니다. **UI 스레드에서만** 부르십시오. WinUI 는 STA 이고
    /// 컨트롤은 그것을 만든 스레드가 소유합니다.
    /// </summary>
    public void ShowLibrary(LibraryHostService host, Microsoft.UI.WindowId windowId)
    {
        ArgumentNullException.ThrowIfNull(host);

        libraryHost = host;
        importWindowId = windowId;
        ScanPanel.Bind(host);
        DevelopDefaultsPanel.Bind(host, ActionableFrameFromGrid);
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

    /// <summary>
    /// 카드 크기는 macOS 와 같은 규칙입니다 — 폭 190·배율, 썸네일은 (폭 − 안쪽 여백) / 1.5,
    /// 그 아래 이름·필름 종류·별점이 고정 높이로 붙습니다.
    /// </summary>
    private void OnFrameContainerChanging(ListViewBase sender, ContainerContentChangingEventArgs args)
    {
        _ = sender;
        // 재활용되는 카드의 비트맵은 놓아 줍니다. 놓지 않으면 스크롤한 만큼 디코드된 썸네일이
        // 계속 쌓입니다 — 1,500장에서 1.2GB 를 쓰던 원인이 이것이었습니다.
        if (args.InRecycleQueue)
        {
            if (args.Item is LibraryFrameListItem recycled)
            {
                recycled.Thumbnail = null;
            }
            return;
        }
        if (args.ItemContainer is not GridViewItem container)
        {
            return;
        }
        container.Width = LibraryCardMetrics.Width;
        container.Height = LibraryCardMetrics.Height;
        container.Margin = new Thickness(LibraryCardMetrics.Spacing / 2.0);
        container.Padding = new Thickness(0.0);
        container.CornerRadius = new CornerRadius(9.0);

        if (args.Item is LibraryFrameListItem item)
        {
            // realize 된 카드만 디코드하고, 아직 없는 것만 렌더를 요청합니다.
            RealizeThumbnail(item);
            thumbnails?.Request(item.Frame);
        }
    }

    /// <summary>
    /// 카드가 화면에 realize 될 때만 썸네일을 디코드합니다.
    /// </summary>
    /// <remarks>
    /// 예전에는 목록을 다시 만들 때마다 <b>전체</b> 항목을 디코드했습니다. 별점 하나만 바꿔도
    /// 그리드 전부가 다시 디코드됐고, 화면에 없는 카드의 비트맵까지 메모리에 남았습니다.
    /// 200장에서 이미 눈에 띄었으므로 수천 장이면 문제가 됩니다. 지금은 컨테이너가 만들어질 때
    /// 그 한 장만 디코드하고, 이미 디코드된 항목은 그대로 둡니다.
    /// </remarks>
    private void RealizeThumbnail(LibraryFrameListItem item)
    {
        if (thumbnails is null || item.HasThumbnail)
        {
            return;
        }
        if (thumbnails.TryGet(item.Id) is { } jpeg)
        {
            item.Thumbnail = DecodeThumbnail(jpeg);
        }
    }

    private void OnThumbnailReady(string frameId)
    {
        if (thumbnails?.TryGet(frameId) is not { } jpeg)
        {
            return;
        }
        foreach (LibraryFrameListItem item in allItems)
        {
            if (!string.Equals(item.Id, frameId, StringComparison.Ordinal))
            {
                continue;
            }
            item.Thumbnail = DecodeThumbnail(jpeg);
            return;
        }
    }

    /// <summary>
    /// JPEG 바이트를 그대로 <c>BitmapImage</c> 에 흘려 넣습니다. 디코드는 WinUI 가 필요할 때
    /// 하므로, 화면 밖 카드까지 미리 펼쳐 두지 않습니다.
    /// </summary>
    internal static BitmapImage? DecodeThumbnail(byte[] jpeg)
    {
        try
        {
            var stream = new Windows.Storage.Streams.InMemoryRandomAccessStream();
            using (var writer = new Windows.Storage.Streams.DataWriter(stream.GetOutputStreamAt(0UL)))
            {
                writer.WriteBytes(jpeg);
                _ = writer.StoreAsync().AsTask().GetAwaiter().GetResult();
            }
            var bitmap = new BitmapImage();
            stream.Seek(0UL);
            bitmap.SetSource(stream);
            return bitmap;
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            return null;
        }
    }

    /// <summary>
    /// 카드를 두 번 누르면 그 frame 을 들고 현상으로 넘어갑니다. macOS 와 같은 진입 방식이며,
    /// 두 화면이 각자 목록을 들고 있어 생기던 "어떤 사진을 보고 있었는지" 불일치를 없앱니다.
    /// </summary>
    private void OnFrameDoubleTapped(object sender, DoubleTappedRoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (FrameListView.SelectedItem is not LibraryFrameListItem item)
        {
            return;
        }
        FrameOpenRequested?.Invoke(this, item);
        workspaceState?.SelectWorkspace(WorkspaceModule.Develop);
    }

    /// <summary>
    /// 격자의 선택을 라이브러리에 알립니다. macOS 처럼 선택은 화면이 아니라 라이브러리가 들고
    /// 있으므로, 현상의 출력 패널이 같은 선택을 보고 "내보내기 (N)" 을 냅니다.
    /// </summary>
    private void OnFrameSelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        if (isSynchronizingFrameSelection)
        {
            return;
        }
        if (libraryHost is { } host)
        {
            // Grouped GridView에서는 SelectionChanged 시점의 SelectedItems가 이전 collection
            // snapshot을 돌려줄 수 있습니다. 이벤트가 보장하는 removed/added delta를 공유 선택에
            // 적용해야 화면의 선택과 Develop active frame이 같은 순간에 바뀝니다.
            List<string> next = [.. host.SelectedFrameIds];
            foreach (LibraryFrameListItem removed in args.RemovedItems.OfType<LibraryFrameListItem>())
            {
                next.RemoveAll(id => string.Equals(id, removed.Id, StringComparison.Ordinal));
            }
            LibraryFrameListItem[] added = [.. args.AddedItems.OfType<LibraryFrameListItem>()];
            foreach (LibraryFrameListItem item in added)
            {
                if (!next.Contains(item.Id, StringComparer.Ordinal))
                {
                    next.Add(item.Id);
                }
            }
            host.SetSelection(next, added.LastOrDefault()?.Id);
        }
        DevelopDefaultsPanel.Synchronize();
    }

    private LibraryFrameSnapshot? ActionableFrameFromGrid() =>
        FrameListView?.SelectedItem is LibraryFrameListItem item ? item.Frame : null;

    private void OnCullingModeClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        CullingSurface.ToggleFrom(sender);
        ShowFilteredItems();
    }

    private bool ApplyCullingMode(LibraryCullingMode mode)
    {
        if (!CullingSurface.SetMode(mode))
        {
            return true;
        }
        ShowFilteredItems();
        return true;
    }

    private void SynchronizeCullingView(IReadOnlyList<LibraryFrameListItem> ordered)
    {
        CullingSurface.Synchronize(
            ordered,
            SelectedItems(),
            FrameListView.SelectedItem as LibraryFrameListItem);
        FrameListView.Visibility = CullingSurface.IsGrid
            ? Visibility.Visible
            : Visibility.Collapsed;
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

    /// <summary>사용자가 라이브러리에서 현상으로 넘기려는 frame 입니다.</summary>
    public event EventHandler<LibraryFrameListItem>? FrameOpenRequested;

    /// <summary>
    /// 공유 현상 사이드바의 스캐너 명령이 이 화면의 실제 스캔 세션을 엽니다. 별도 스캔 상태를
    /// 만들지 않고 Library와 Develop이 같은 컨트롤러와 catalog를 사용합니다.
    /// </summary>
    public void PresentScannerSetup()
    {
        sourceKind = LibrarySourceKind.Importing;
        UpdateSourcePanel();
        ImportScannerButton.IsChecked = true;
        ScanPanel.Open();
    }

    /// <summary>
    /// 단축키가 부른 명령입니다. 이 화면이 맡을 수 있으면 처리하고 true 를 돌려줍니다.
    /// </summary>
    /// <remarks>
    /// 고른 사진이 없으면 사진 명령은 조용히 지나갑니다 — 아무것도 고르지 않은 채 X 를 눌러
    /// 무엇이 제외됐는지 모르게 되는 편이 더 나쁩니다.
    /// </remarks>
    public bool InvokeShortcut(WorkflowShortcutAction action)
    {
        switch (action)
        {
            case WorkflowShortcutAction.ImportImages:
                OnImportClicked(this, new RoutedEventArgs());
                return true;
            case WorkflowShortcutAction.ImportFolder:
                OnImportFoldersClicked(this, new RoutedEventArgs());
                return true;
            case WorkflowShortcutAction.Undo:
                return UndoLibraryChange(redo: false);
            case WorkflowShortcutAction.Redo:
                return UndoLibraryChange(redo: true);
            case WorkflowShortcutAction.RefreshLibrary:
                if (libraryHost is { } host)
                {
                    ShowLibrary(host, importWindowId ?? default);
                }
                return true;
            case WorkflowShortcutAction.LibraryGrid:
                return ApplyCullingMode(LibraryCullingMode.Grid);
            case WorkflowShortcutAction.LibraryCompare:
                return ApplyCullingMode(LibraryCullingMode.Compare);
            case WorkflowShortcutAction.LibrarySurvey:
                return ApplyCullingMode(LibraryCullingMode.Survey);
            case WorkflowShortcutAction.PreviousPhoto:
                return MoveSelection(-1);
            case WorkflowShortcutAction.NextPhoto:
                return MoveSelection(1);
        }

        IReadOnlyList<LibraryFrameListItem> targets = SelectedItems();
        if (targets.Count == 0)
        {
            return false;
        }
        switch (action)
        {
            case WorkflowShortcutAction.PickPhoto:
                SetPickState(targets, FramePickState.Picked);
                return true;
            case WorkflowShortcutAction.ClearPick:
                SetPickState(targets, FramePickState.Unflagged);
                return true;
            case WorkflowShortcutAction.RejectPhoto:
                SetPickState(targets, FramePickState.Rejected);
                return true;
            case WorkflowShortcutAction.DeletePhoto:
                RemoveFromLibrary(targets);
                return true;
            case WorkflowShortcutAction.ProcessColorNegative:
            case WorkflowShortcutAction.ProcessColorPositive:
            case WorkflowShortcutAction.ProcessBwNegative:
            case WorkflowShortcutAction.ProcessBwPositive:
                DevelopDefaultsPanel.ApplyProcess(action);
                return true;
            case WorkflowShortcutAction.TargetMain:
                DevelopDefaultsPanel.ApplyTarget(DevelopTarget.Main);
                return true;
            case WorkflowShortcutAction.TargetPrint:
                DevelopDefaultsPanel.ApplyTarget(DevelopTarget.Print);
                return true;
            case WorkflowShortcutAction.TargetNoritsu:
                DevelopDefaultsPanel.ApplyTarget(DevelopTarget.Noritsu);
                return true;
            case WorkflowShortcutAction.TargetSp3000:
                DevelopDefaultsPanel.ApplyTarget(DevelopTarget.Sp3000);
                return true;
            case WorkflowShortcutAction.TargetF135:
                DevelopDefaultsPanel.ApplyTarget(DevelopTarget.F135);
                return true;
            case WorkflowShortcutAction.TargetHr:
                DevelopDefaultsPanel.ApplyTarget(DevelopTarget.Hr);
                return true;
            case WorkflowShortcutAction.TargetExpired:
                DevelopDefaultsPanel.ApplyTarget(DevelopTarget.Rescue);
                return true;
            case WorkflowShortcutAction.CreateVirtualCopy:
                // 사본은 한 장에 하나씩입니다. 여러 장을 골랐으면 macOS 처럼 활성 사진만
                // 복사합니다 — 한 번에 열 장을 복사하는 것은 되돌리기 어렵습니다.
                CreateVirtualCopy(targets[0]);
                return true;
            case WorkflowShortcutAction.RateZero:
            case WorkflowShortcutAction.RateOne:
            case WorkflowShortcutAction.RateTwo:
            case WorkflowShortcutAction.RateThree:
            case WorkflowShortcutAction.RateFour:
            case WorkflowShortcutAction.RateFive:
                SetRating(targets, action - WorkflowShortcutAction.RateZero);
                return true;
            default:
                return false;
        }
    }

    /// <summary>
    /// 남아 있는 카드에 묶음 배지를 답니다. 접힌 묶음은 대표 한 장만 남았고, 펼친 묶음은 모든
    /// 구성원이 남아 있으므로 전부에 답니다 — macOS 도 구성원마다 배지를 답니다.
    /// </summary>
    private void ApplyStackBadges(IReadOnlyList<LibraryFrameListItem> items)
    {
        if (libraryHost is not { } host)
        {
            return;
        }
        Dictionary<string, LibraryStackSnapshot> byFrameId = [];
        foreach (LibraryStackSnapshot stack in host.Stacks)
        {
            foreach (string frameId in stack.FrameIds)
            {
                byFrameId[frameId] = stack;
            }
        }
        foreach (LibraryFrameListItem item in items)
        {
            if (byFrameId.TryGetValue(item.Id, out LibraryStackSnapshot? stack))
            {
                item.IsStackCollapsed = stack.IsCollapsed;
                item.StackCount = stack.FrameIds.Count;
            }
            else
            {
                item.StackCount = 0;
            }
        }
    }

    /// <summary>
    /// 메뉴 맨 위의 묶음 명령입니다. macOS <c>LibraryStackMenu</c> 와 같이 셋 중 하나만 나옵니다 —
    /// 이미 묶여 있으면 접기/펼치기와 해제, 아니면 두 장 이상 골랐을 때만 묶기.
    /// </summary>
    private void AddStackCommands(
        MenuFlyout menu,
        LibraryFrameListItem item,
        IReadOnlyList<LibraryFrameListItem> targets)
    {
        if (libraryHost is not { } host)
        {
            return;
        }
        if (host.StackFor(item.Id) is { } stack)
        {
            menu.Items.Add(MenuItem(
                stack.IsCollapsed ? "libraryStackExpand" : "libraryStackCollapse",
                "Content",
                () =>
                {
                    if (host.ToggleStackCollapsed(stack.Id))
                    {
                        ShowFilteredItems();
                    }
                }));
            menu.Items.Add(MenuItem("libraryStackUngroup", "Content", () =>
            {
                if (host.UngroupStack(stack.Id))
                {
                    ShowFilteredItems();
                }
            }));
        }
        else if (targets.Count >= 2)
        {
            menu.Items.Add(MenuItem("libraryStackGroup", "Content", () =>
            {
                if (host.CreateStack(targets.Select(target => target.Id)) is not null)
                {
                    ShowFilteredItems();
                }
            }));
        }
        else
        {
            return;
        }
        menu.Items.Add(new MenuFlyoutSeparator());
    }

    /// <summary>
    /// 같은 원본을 가리키는 사진을 하나 더 만듭니다. 만든 사본을 바로 고릅니다 — macOS 도
    /// 그렇게 하며, 그래야 다음 조정이 사본에 걸립니다.
    /// </summary>
    private void CreateVirtualCopy(LibraryFrameListItem item)
    {
        if (libraryHost is not { } host || host.CreateVirtualCopy(item.Id) is not { } copyId)
        {
            return;
        }
        ShowLibrary(host, importWindowId ?? default);
        LibraryFrameListItem? created = FrameListView.Items
            .OfType<LibraryFrameListItem>()
            .FirstOrDefault(candidate => candidate.Id == copyId);
        if (created is not null)
        {
            FrameListView.SelectedItem = created;
            FrameListView.ScrollIntoView(created);
        }
    }

    private IReadOnlyList<LibraryFrameListItem> SelectedItems() =>
        [.. FrameListView.SelectedItems.OfType<LibraryFrameListItem>()];

    /// <summary>
    /// 격자에서 한 칸 옮깁니다. 고른 것이 없으면 첫 칸부터 시작합니다 — macOS 도 그렇게 하며,
    /// 그래야 마우스를 쓰지 않고 훑기를 시작할 수 있습니다.
    /// </summary>
    private bool MoveSelection(int offset)
    {
        if (FrameListView.Items.Count == 0)
        {
            return false;
        }
        int current = FrameListView.SelectedIndex;
        int next = current < 0
            ? (offset > 0 ? 0 : FrameListView.Items.Count - 1)
            : Math.Clamp(current + offset, 0, FrameListView.Items.Count - 1);
        FrameListView.SelectedIndex = next;
        FrameListView.ScrollIntoView(FrameListView.Items[next]);
        return true;
    }

    /// <summary>
    /// 카드의 오른쪽 단추 메뉴입니다. macOS <c>LibraryFrameContextMenu</c> 와 같은 차례로
    /// 냅니다 — 현상, 이름 변경, 별점, 깃발, 컬렉션, 그리고 원본 명령들입니다.
    /// </summary>
    /// <remarks>
    /// 메뉴를 XAML 의 <c>ContextFlyout</c> 으로 카드마다 붙이면 카드 한 장마다 메뉴 하나가
    /// 함께 만들어집니다. macOS 도 같은 이유로 메뉴를 별도 뷰로 감싸 열릴 때만 만듭니다.
    /// </remarks>
    private void OnFrameRightTapped(object sender, RightTappedRoutedEventArgs args)
    {
        if (sender is not FrameworkElement { Tag: LibraryFrameListItem item } card ||
            libraryHost is null)
        {
            return;
        }
        args.Handled = true;

        // 오른쪽 단추는 선택을 바꾸지 않는 것이 macOS 동작입니다. 다만 선택 **밖**의 카드를
        // 눌렀다면 그 카드 하나가 대상입니다 — 보이지 않는 선택에 명령이 가면 안 됩니다.
        IReadOnlyList<LibraryFrameListItem> targets = ContextTargets(item);

        MenuFlyout menu = new();
        AddStackCommands(menu, item, targets);
        menu.Items.Add(MenuItem("menuDevelop", "Content", () =>
        {
            FrameOpenRequested?.Invoke(this, item);
            workspaceState?.SelectWorkspace(WorkspaceModule.Develop);
        }));
        menu.Items.Add(MenuItem("libraryRenamePhoto", "Content", () => RenameFrame(item)));

        MenuFlyoutSubItem rating = new()
        {
            Text = AppResources.Get("libraryRating", "Text"),
        };
        rating.Items.Add(MenuItem("libraryClearRating", "Content", () => SetRating(targets, 0)));
        for (int stars = 1; stars <= 5; ++stars)
        {
            int value = stars;
            MenuFlyoutItem star = new()
            {
                Text = AppResources.FormatIntegers("libraryStarFormat", "Text", value),
            };
            star.Click += (_, _) => SetRating(targets, value);
            rating.Items.Add(star);
        }
        menu.Items.Add(rating);

        bool isPicked = item.Frame.PickState == FramePickState.Picked;
        bool isRejected = item.Frame.PickState == FramePickState.Rejected;
        menu.Items.Add(MenuItem(
            isPicked ? "libraryClearPick" : "libraryPick",
            "Content",
            () => SetPickState(
                targets,
                isPicked ? FramePickState.Unflagged : FramePickState.Picked)));
        menu.Items.Add(MenuItem(
            isRejected ? "libraryClearReject" : "libraryReject",
            "Content",
            () => SetPickState(
                targets,
                isRejected ? FramePickState.Unflagged : FramePickState.Rejected)));

        if (libraryHost.Collections.Count > 0)
        {
            MenuFlyoutSubItem collections = new()
            {
                Text = AppResources.Get("libraryAddToCollection", "Text"),
            };
            foreach (LibraryCollectionSnapshot collection in libraryHost.Collections)
            {
                string collectionId = collection.Id;
                MenuFlyoutItem entry = new() { Text = collection.Name };
                entry.Click += (_, _) => AddToCollection(collectionId, targets);
                collections.Items.Add(entry);
            }
            menu.Items.Add(collections);
            if (CollectionsPanel.SelectedCollectionId is { } activeCollectionId)
            {
                menu.Items.Add(MenuItem(
                    "libraryRemoveFromCollection",
                    "Content",
                    () => RemoveFromCollection(activeCollectionId, targets)));
            }
        }

        menu.Items.Add(new MenuFlyoutSeparator());
        menu.Items.Add(MenuItem("libraryVirtualCopy", "Content", () => CreateVirtualCopy(item)));
        menu.Items.Add(MenuItem(
            "libraryShowInExplorer",
            "Content",
            () => ShowInExplorer(item)));
        menu.Items.Add(MenuItem(
            "libraryRemoveFromLibrary",
            "Content",
            () => RemoveFromLibrary(targets)));

        menu.ShowAt(card, new FlyoutShowOptions { Position = args.GetPosition(card) });
    }

    /// <summary>
    /// 명령이 닿을 사진들입니다. 누른 카드가 선택 안에 있으면 선택 전체, 밖이면 그 카드
    /// 하나입니다 — macOS <c>framesForContextAction</c> 과 같은 규칙입니다.
    /// </summary>
    private IReadOnlyList<LibraryFrameListItem> ContextTargets(LibraryFrameListItem item)
    {
        LibraryFrameListItem[] selected = [.. FrameListView.SelectedItems
            .OfType<LibraryFrameListItem>()];
        return selected.Any(candidate =>
            string.Equals(candidate.Id, item.Id, StringComparison.Ordinal))
                ? selected
                : [item];
    }

    private static MenuFlyoutItem MenuItem(string key, string property, Action action)
    {
        MenuFlyoutItem item = new() { Text = AppResources.Get(key, property) };
        item.Click += (_, _) => action();
        return item;
    }

    private void SetRating(IReadOnlyList<LibraryFrameListItem> targets, int rating)
    {
        ApplyEdit(targets, frame =>
            new LibraryFrameEdit(frame.Tone, frame.ManualBase, Rating: rating));
    }

    private void SetPickState(
        IReadOnlyList<LibraryFrameListItem> targets,
        FramePickState pickState)
    {
        ApplyEdit(targets, frame =>
            new LibraryFrameEdit(frame.Tone, frame.ManualBase, PickState: pickState));
    }

    /// <summary>
    /// 여러 장에 같은 편집을 겁니다. 저장은 한 번만 합니다 — 200장을 고르고 별점을 주면
    /// catalog 를 200번 쓰게 되어 눈에 보이게 멈춥니다.
    /// </summary>
    private void ApplyEdit(
        IReadOnlyList<LibraryFrameListItem> targets,
        Func<LibraryFrameSnapshot, LibraryFrameEdit> makeEdit)
    {
        if (libraryHost is null || targets.Count == 0)
        {
            return;
        }
        bool changed = false;
        foreach (LibraryFrameListItem target in targets)
        {
            if (libraryHost.Edit(target.Frame.Id, makeEdit(target.Frame)) ==
                LibraryFrameError.None)
            {
                changed = true;
            }
        }
        if (changed && libraryHost.Save() == CatalogStoreError.None)
        {
            ShowLibrary(libraryHost, importWindowId ?? default);
        }
    }

    private void AddToCollection(
        string collectionId,
        IReadOnlyList<LibraryFrameListItem> targets)
    {
        if (libraryHost?.Collections.FirstOrDefault(collection =>
                string.Equals(collection.Id, collectionId, StringComparison.Ordinal))
            is not { } existing)
        {
            return;
        }
        // 이미 들어 있는 사진은 다시 넣지 않습니다. 넣으면 같은 사진이 두 번 보입니다.
        List<string> frameIds = [.. existing.FrameIds];
        var present = new HashSet<string>(frameIds, StringComparer.Ordinal);
        foreach (LibraryFrameListItem target in targets)
        {
            if (present.Add(target.Id))
            {
                frameIds.Add(target.Id);
            }
        }
        if (frameIds.Count == existing.FrameIds.Count)
        {
            return;
        }
        if (libraryHost.SetCollectionFrames(collectionId, frameIds))
        {
            CollectionsPanel.Rebuild();
            ShowFilteredItems();
        }
    }

    private void RemoveFromCollection(
        string collectionId,
        IReadOnlyList<LibraryFrameListItem> targets)
    {
        if (libraryHost?.Collections.FirstOrDefault(collection =>
                string.Equals(collection.Id, collectionId, StringComparison.Ordinal))
            is not { } existing)
        {
            return;
        }
        var removing = new HashSet<string>(
            targets.Select(target => target.Id),
            StringComparer.Ordinal);
        List<string> frameIds = [.. existing.FrameIds.Where(id => !removing.Contains(id))];
        if (frameIds.Count == existing.FrameIds.Count)
        {
            return;
        }
        if (libraryHost.SetCollectionFrames(collectionId, frameIds))
        {
            CollectionsPanel.Rebuild();
            ShowFilteredItems();
        }
    }

    /// <summary>
    /// 원본이 있는 폴더를 열고 그 파일을 고릅니다. macOS 의 "Finder 에서 보기" 와 같은 자리이며,
    /// **원본을 열지 않습니다** — 여는 것은 다른 프로그램의 일입니다.
    /// </summary>
    private static void ShowInExplorer(LibraryFrameListItem item)
    {
        string path = item.Frame.SourcePath;
        if (!File.Exists(path))
        {
            return;
        }
        _ = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
        {
            FileName = "explorer.exe",
            // 인용은 반드시 있어야 합니다. 공백이 든 경로가 인용 없이 가면 탐색기는 엉뚱한
            // 폴더를 열고 아무 말도 하지 않습니다.
            Arguments = $"/select,\"{path}\"",
            UseShellExecute = true,
        });
    }

    /// <summary>
    /// 사진을 라이브러리에서 뺍니다. **묻지 않습니다** — macOS 처럼 곧바로 빼고 되돌릴 수 있다고
    /// 알립니다. 되돌리기가 붙기 전에는 물어봤지만, 물음은 되돌리기의 대용품이었을 뿐입니다.
    /// </summary>
    private void RemoveFromLibrary(IReadOnlyList<LibraryFrameListItem> targets)
    {
        if (libraryHost is not { } host || targets.Count == 0)
        {
            return;
        }
        int removed = host.RemoveFrames(targets.Select(target => target.Id));
        if (removed == 0)
        {
            return;
        }
        // 썸네일은 지우지 않습니다. 되돌리면 그 사진이 다시 오고, 그때 다시 만들게 하면
        // 되살아난 격자가 한동안 빈 칸으로 보입니다.
        CollectionsPanel.Rebuild();
        ShowLibrary(host, importWindowId ?? default);
        ImportStatusText.Text = AppResources.FormatIntegers(
            "libraryRemovalUndoFormat",
            "Text",
            removed);
    }

    /// <summary>
    /// 한 단계 되돌리고 무엇을 되돌렸는지 알립니다. 조용히 되돌리면 사용자는 무엇이 바뀌었는지
    /// 격자에서 찾아내야 합니다.
    /// </summary>
    private bool UndoLibraryChange(bool redo)
    {
        if (libraryHost is not { } host)
        {
            return false;
        }
        string? actionKey = redo ? host.Redo() : host.Undo();
        if (actionKey is null)
        {
            return false;
        }
        CollectionsPanel.Rebuild();
        ShowLibrary(host, importWindowId ?? default);
        ImportStatusText.Text = AppResources
            .Get("libraryUndoneFormat", "Text")
            .Replace("{0}", ActionDisplayName(actionKey), StringComparison.Ordinal);
        return true;
    }

    /// <summary>
    /// 되돌린 동작의 이름입니다. 카탈로그 쪽은 리소스 키만 알고, 번역은 셸이 붙입니다.
    /// </summary>
    private static string ActionDisplayName(string actionKey) => actionKey switch
    {
        LibraryHostService.UndoActions.RemoveFrames =>
            AppResources.Get("libraryRemoveFromLibrary", "Content"),
        LibraryHostService.UndoActions.CreateCollection =>
            AppResources.Get("libraryNewCollection", "Content"),
        LibraryHostService.UndoActions.RenameCollection =>
            AppResources.Get("libraryRename", "Content"),
        LibraryHostService.UndoActions.EditCollection =>
            AppResources.Get("libraryAddToCollection", "Text"),
        LibraryHostService.UndoActions.DeleteCollection =>
            AppResources.Get("libraryDelete", "Content"),
        LibraryHostService.UndoActions.VirtualCopy =>
            AppResources.Get("libraryVirtualCopy", "Content"),
        LibraryHostService.UndoActions.CreateStack =>
            AppResources.Get("libraryStackGroup", "Content"),
        LibraryHostService.UndoActions.UngroupStack =>
            AppResources.Get("libraryStackUngroup", "Content"),
        _ => AppResources.Get("libraryStackCollapse", "Content"),
    };

    /// <summary>
    /// 사진 번호를 바꿉니다. macOS 와 같이 이름이 아니라 **번호**를 받습니다 — 라이브러리의
    /// 이름은 폴더 안의 순번이기 때문입니다.
    /// </summary>
    private async void RenameFrame(LibraryFrameListItem item)
    {
        if (libraryHost is null)
        {
            return;
        }
        TextBox field = new()
        {
            PlaceholderText = AppResources.Get("libraryPhotoName", "Text"),
            Text = LibraryFrameNaming.EditableNumberText(item.Frame),
        };
        AutomationProperties.SetName(field, field.PlaceholderText);
        AutomationProperties.SetAutomationId(field, "negaflow.photo-number-field");
        // macOS 는 숫자가 아닌 글자를 입력 즉시 지웁니다. 확인 단추에서만 막으면 사용자는
        // 무엇이 잘못됐는지 모른 채 눌리지 않는 단추를 봅니다.
        field.TextChanged += (_, _) =>
        {
            string digits = new([.. field.Text.Where(char.IsAsciiDigit)]);
            if (!string.Equals(digits, field.Text, StringComparison.Ordinal))
            {
                int caret = field.SelectionStart;
                field.Text = digits;
                field.SelectionStart = Math.Min(caret, digits.Length);
            }
        };
        ContentDialog dialog = new()
        {
            XamlRoot = XamlRoot,
            Title = AppResources.Get("libraryRenamePhoto", "Content"),
            Content = field,
            PrimaryButtonText = AppResources.Get("libraryRename", "Content"),
            CloseButtonText = AppResources.Get("commonCancel", "Content"),
            DefaultButton = ContentDialogButton.Primary,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary)
        {
            return;
        }
        if (!int.TryParse(
                field.Text,
                NumberStyles.None,
                CultureInfo.InvariantCulture,
                out int number) ||
            !LibraryFrameNaming.IsNumberAvailable(libraryHost.Frames, item.Frame, number))
        {
            return;
        }
        // 같은 원본을 가리키는 사진들은 함께 번호가 바뀝니다 — macOS 도 원본 경로로 묶습니다.
        DisplayNameSelection selection = LibraryFrameNaming.NumberSelection(number);
        bool changed = false;
        foreach (LibraryFrameSnapshot frame in libraryHost.Frames)
        {
            if (!string.Equals(
                    frame.SourcePath,
                    item.Frame.SourcePath,
                    StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }
            if (libraryHost.Edit(
                    frame.Id,
                    new LibraryFrameEdit(
                        frame.Tone,
                        frame.ManualBase,
                        DisplayName: selection)) == LibraryFrameError.None)
            {
                changed = true;
            }
        }
        if (changed && libraryHost.Save() == CatalogStoreError.None)
        {
            ShowLibrary(libraryHost, importWindowId ?? default);
        }
    }

    private void OnRatingCommitted(object? sender, int rating)
    {
        if (libraryHost is null ||
            sender is not FrameRatingStars { Tag: LibraryFrameListItem item })
        {
            return;
        }
        LibraryFrameSnapshot frame = item.Frame;
        LibraryFrameError error = libraryHost.Edit(
            frame.Id,
            new LibraryFrameEdit(frame.Tone, frame.ManualBase, Rating: rating));
        if (error != LibraryFrameError.None || libraryHost.Save() != CatalogStoreError.None)
        {
            // 저장에 실패했으면 화면도 되돌립니다 — 다음 실행에서 사라질 값을 남기지 않습니다.
            ((FrameRatingStars)sender).Rating = frame.Rating;
            return;
        }
        ShowLibrary(libraryHost, importWindowId ?? default);
    }

    private void OnLibrarySearchTextChanged(object sender, TextChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        ShowFilteredItems();
    }

    private void ShowFilteredItems()
    {
        IReadOnlyList<LibraryFrameListItem> items = LibrarySorter.Sort(
            quickFilters.Apply(
                CollectionsPanel.Apply(
                    LibraryFrameListItems.Filter(
                        allItems,
                        LibrarySearchBox?.Text ?? string.Empty))),
            sortKey,
            sortAscending);
        // 접기는 **정렬 뒤**에 걸립니다. 대표로 남는 것이 화면 차례에서 가장 앞선 사진이어야
        // 정렬을 바꿀 때 대표도 따라 바뀝니다.
        if (libraryHost is not null)
        {
            items = LibraryStackProjection.Apply(items, libraryHost.Stacks);
            ApplyStackBadges(items);
        }
        UpdateSortControls();
        UpdateCardSizeControls();
        UpdateFilterControls();
        if (libraryHost is null)
        {
            FrameListView.ItemsSource = items;
            LibraryCountText.Text = items.Count.ToString(CultureInfo.CurrentCulture);
            SynchronizeCullingView(items);
            return;
        }

        LibraryBrowserProjection projection = LibraryBrowserProjector.Create(
            items,
            libraryHost.Folders,
            libraryHost.FolderAvailabilityById,
            viewMode,
            selectedFilmType);
        isSynchronizingFrameSelection = true;
        try
        {
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
            SynchronizeFrameSelection(projection.Items);
        }
        finally
        {
            isSynchronizingFrameSelection = false;
        }
        UpdateViewModeControls();
        DevelopDefaultsPanel.Synchronize();
        SynchronizeCullingView(items);
        if (sourceKind == LibrarySourceKind.Files)
        {
            RebuildFilesSourceTree();
        }
    }

    private void OnSourceRailClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (sender is not Button { Tag: string value } ||
            !Enum.TryParse(value, out LibrarySourceKind kind))
        {
            return;
        }
        sourceKind = kind;
        UpdateSourcePanel();
    }

    /// <summary>
    /// 왼쪽 소스를 바꿉니다. 가져오기·파일·컬렉션이 같은 자리를 나눠 쓰므로 셋 중 하나만
    /// 보입니다 — macOS 도 이 자리를 겹쳐 씁니다.
    /// </summary>
    private void UpdateSourcePanel()
    {
        ImportSourcePanel.Visibility = sourceKind == LibrarySourceKind.Importing
            ? Visibility.Visible
            : Visibility.Collapsed;
        FilesSourceTree.Visibility = sourceKind == LibrarySourceKind.Files
            ? Visibility.Visible
            : Visibility.Collapsed;
        CollectionsPanel.Visibility = sourceKind == LibrarySourceKind.Collections
            ? Visibility.Visible
            : Visibility.Collapsed;

        (string headerKey, string glyph) = sourceKind switch
        {
            LibrarySourceKind.Files => ("libraryFiles", ""),
            LibrarySourceKind.Collections => ("libraryCollections", ""),
            _ => ("importSection", ""),
        };
        ImportHeaderText.Text = AppResources.Get(headerKey, headerKey == "importSection" ? "Text" : "Value");
        SourceHeaderIcon.Glyph = glyph;
        foreach ((Button button, FontIcon icon, LibrarySourceKind kind) in SourceRailButtons())
        {
            bool selected = kind == sourceKind;
            button.Background = selected
                ? (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["NegaflowSelectionBrush"]
                : new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Transparent);
            icon.Foreground = selected
                ? (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["AccentTextFillColorPrimaryBrush"]
                : (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["TextFillColorPrimaryBrush"];
            AutomationProperties.SetItemStatus(
                button,
                AppResources.Get(selected ? "selected" : "notSelected", "Value"));
        }
        if (sourceKind == LibrarySourceKind.Files)
        {
            RebuildFilesSourceTree();
        }
    }

    private IEnumerable<(Button Button, FontIcon Icon, LibrarySourceKind Kind)> SourceRailButtons()
    {
        yield return (ImportRailButton, ImportRailIcon, LibrarySourceKind.Importing);
        yield return (FilesRailButton, FilesRailIcon, LibrarySourceKind.Files);
        yield return (CollectionsRailButton, CollectionsRailIcon, LibrarySourceKind.Collections);
    }

    /// <summary>
    /// 폴더와 그 안의 frame 을 트리로 다시 만듭니다. 격자와 같은 투영을 쓰므로 필터·검색이
    /// 걸리면 트리도 함께 줄어듭니다.
    /// </summary>
    private void RebuildFilesSourceTree()
    {
        int matched = FilesSourceTree.Rebuild(
            allItems,
            LibrarySearchBox?.Text ?? string.Empty,
            quickFilters);
        SourceHeaderCountText.Text = AppResources.FormatIntegers(
            "libraryFolderFrameCount",
            "Text",
            matched);
    }

    /// <summary>
    /// 격자에서 카드를 끌기 시작합니다. 담는 것은 frame id 뿐입니다 — 파일 경로를 담으면
    /// 탐색기로 끌어 놓았을 때 원본이 딸려 나갑니다.
    /// </summary>
    private void OnFrameDragStarting(object sender, DragItemsStartingEventArgs args)
    {
        _ = sender;
        string[] frameIds = [.. args.Items.OfType<LibraryFrameListItem>().Select(item => item.Id)];
        if (frameIds.Length == 0)
        {
            args.Cancel = true;
            return;
        }
        args.Data.SetText(string.Join('\n', frameIds));
        args.Data.Properties.Title = FrameDragFormat;
        args.Data.RequestedOperation = DataPackageOperation.Move;
    }

    /// <summary>
    /// 우리 카드에서 시작한 끌기인지 알아보는 표식입니다. 이것이 없으면 탐색기에서 끌어온
    /// 파일도 폴더 줄이 받아들입니다.
    /// </summary>
    private const string FrameDragFormat = "negaflow.library-source";

    /// <summary>트리에서 frame 을 누르면 격자의 선택도 따라갑니다.</summary>
    private void OnFilesSourceFrameSelected(object? sender, string frameId)
    {
        _ = sender;
        foreach (object candidate in FrameListView.Items)
        {
            if (candidate is LibraryFrameListItem item &&
                string.Equals(item.Id, frameId, StringComparison.Ordinal))
            {
                FrameListView.SelectedItem = item;
                FrameListView.ScrollIntoView(item);
                return;
            }
        }
    }

    /// <summary>
    /// 폴더 머리줄에서 현상 프로세스를 고르면 그 폴더의 frame 전부에 적용합니다. 지금까지는
    /// 가져오기가 전부 C-41 로 고정돼 있어 슬라이드·흑백·디지털 경로에 아예 닿을 수 없었습니다.
    /// </summary>
    private void OnFolderProcessChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = args;
        if (libraryHost is null ||
            sender is not ComboBox
            {
                Tag: LibraryBrowserFolderSection section,
                SelectedItem: DevelopProcessChoice choice,
            })
        {
            return;
        }
        // 이미 그 프로세스면 아무 것도 쓰지 않습니다 — 목록을 다시 그릴 때마다 저장하지
        // 않으려는 것입니다.
        if (section.Items.Count == 0 ||
            DevelopProcesses.From(
                section.Items[0].Frame.Route.FilmType,
                section.Items[0].Frame.Route.IsDigitalSource) == choice.Process)
        {
            return;
        }

        foreach (LibraryFrameListItem item in section.Items)
        {
            LibraryFrameSnapshot frame = item.Frame;
            _ = libraryHost.EditRoute(
                frame.Id,
                DevelopRouteSelection.FromProcess(
                    choice.Process,
                    frame.Route.FilmEmulation,
                    frame.Route.FilmEmulationIntensity));
        }
        if (libraryHost.Save() != CatalogStoreError.None)
        {
            ImportStatusText.Text = AppResources.Get("libraryProcessApplyFailed", "Text");
        }
        ShowLibrary(libraryHost, importWindowId ?? default);
    }

    private void OnFiltersToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        FilterBar.Visibility = FiltersButton.IsChecked == true
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private void OnQuickFilterToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingFilters)
        {
            return;
        }
        quickFilters = quickFilters with
        {
            Picked = PickedFilterToggle.IsChecked == true,
            Rejected = RejectedFilterToggle.IsChecked == true,
            Offline = OfflineFilterToggle.IsChecked == true,
            Infrared = InfraredFilterToggle.IsChecked == true,
            DefectRecipe = DefectRecipeFilterToggle.IsChecked == true,
            MetadataUnknown = MetadataUnknownFilterToggle.IsChecked == true,
            UnvalidatedProfile = UnvalidatedProfileFilterToggle.IsChecked == true,
            CurrentRoll = CurrentRollFilterToggle.IsChecked == true,
            CurrentRollFrameIds = CurrentRollFrameIds(),
        };
        ShowFilteredItems();
    }

    private void OnRatingFilterClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (sender is not MenuFlyoutItem { Tag: string value } ||
            !int.TryParse(value, CultureInfo.InvariantCulture, out int minimum))
        {
            return;
        }
        quickFilters = quickFilters with { MinimumRating = minimum == 0 ? null : minimum };
        ShowFilteredItems();
    }

    private void OnClearFiltersClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        quickFilters = LibraryQuickFilterState.None;
        LibrarySearchBox.Text = string.Empty;
        ShowFilteredItems();
    }

    private void UpdateFilterControls()
    {
        isSynchronizingFilters = true;
        try
        {
            PickedFilterToggle.IsChecked = quickFilters.Picked;
            RejectedFilterToggle.IsChecked = quickFilters.Rejected;
            OfflineFilterToggle.IsChecked = quickFilters.Offline;
            InfraredFilterToggle.IsChecked = quickFilters.Infrared;
            DefectRecipeFilterToggle.IsChecked = quickFilters.DefectRecipe;
            MetadataUnknownFilterToggle.IsChecked = quickFilters.MetadataUnknown;
            UnvalidatedProfileFilterToggle.IsChecked = quickFilters.UnvalidatedProfile;
        }
        finally
        {
            isSynchronizingFilters = false;
        }
        RatingFilterButton.Content = quickFilters.MinimumRating is { } minimum
            ? AppResources.FormatIntegers("filterMinimumRating", "Text", minimum)
            : AppResources.Get("rating", "Value");
        // 필터가 걸려 있으면 헤더 버튼이 강조됩니다 — 접힌 상태에서도 걸린 줄 알 수 있어야 합니다.
        FiltersIcon.Foreground = quickFilters.IsActive
            ? (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["AccentTextFillColorPrimaryBrush"]
            : (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["TextFillColorSecondaryBrush"];
        // 오프라인 보기에서는 이미 오프라인만 남으므로 macOS 와 같이 토글을 잠급니다.
        OfflineFilterToggle.IsEnabled = viewMode != LibraryBrowserViewMode.Offline;
    }

    private void OnSortKeyClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (sender is not MenuFlyoutItem { Tag: string value } ||
            !Enum.TryParse(value, out LibrarySortKey key))
        {
            return;
        }
        sortKey = key;
        ShowFilteredItems();
    }

    private void OnSortDirectionClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (sender is not MenuFlyoutItem { Tag: string value })
        {
            return;
        }
        sortAscending = string.Equals(value, "Ascending", StringComparison.Ordinal);
        ShowFilteredItems();
    }

    private void OnCardSizeDecreaseClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        SetCardScale(LibraryCardMetrics.Scale - LibraryCardMetrics.ScaleStep);
    }

    private void OnCardSizeIncreaseClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        SetCardScale(LibraryCardMetrics.Scale + LibraryCardMetrics.ScaleStep);
    }

    /// <summary>퍼센트를 누르면 100% 로 돌아갑니다 — macOS 와 같습니다.</summary>
    private void OnCardSizeResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        SetCardScale(1.0);
    }

    private void SetCardScale(double scale)
    {
        LibraryCardMetrics.Scale = scale;
        UpdateCardSizeControls();
        // 카드 크기는 컨테이너에서 정해지므로 항목을 다시 붙여야 새 크기로 재어집니다.
        ShowFilteredItems();
    }

    private void UpdateCardSizeControls()
    {
        double scale = LibraryCardMetrics.Scale;
        CardSizeResetButton.Content = string.Create(
            CultureInfo.CurrentCulture,
            $"{(int)Math.Round(scale * 100.0)}%");
        CardSizeDecreaseButton.IsEnabled = scale > LibraryCardMetrics.MinimumScale;
        CardSizeIncreaseButton.IsEnabled = scale < LibraryCardMetrics.MaximumScale;
    }

    private void UpdateSortControls()
    {
        SortKeyText.Text = SortKeyName(sortKey);
        SortDirectionIcon.Glyph = sortAscending ? "" : "";
        AutomationProperties.SetName(SortButton, SortKeyText.Text);
        foreach ((MenuFlyoutItem item, LibrarySortKey key) in SortMenuItems())
        {
            AutomationProperties.SetItemStatus(
                item,
                AppResources.Get(key == sortKey ? "selected" : "notSelected", "Value"));
        }
        AutomationProperties.SetItemStatus(
            SortAscendingItem,
            AppResources.Get(sortAscending ? "selected" : "notSelected", "Value"));
        AutomationProperties.SetItemStatus(
            SortDescendingItem,
            AppResources.Get(sortAscending ? "notSelected" : "selected", "Value"));
    }

    private IEnumerable<(MenuFlyoutItem Item, LibrarySortKey Key)> SortMenuItems()
    {
        yield return (SortInputOrderItem, LibrarySortKey.InputOrder);
        yield return (SortTimeItem, LibrarySortKey.Time);
        yield return (SortNameItem, LibrarySortKey.Name);
        yield return (SortFlagItem, LibrarySortKey.Flag);
        yield return (SortRatingItem, LibrarySortKey.Rating);
        yield return (SortFileSizeItem, LibrarySortKey.FileSize);
    }

    private static string SortKeyName(LibrarySortKey key) => AppResources.Get(
        key switch
        {
            LibrarySortKey.Time => "sortTime",
            LibrarySortKey.Name => "sortName",
            LibrarySortKey.Flag => "sortFlag",
            LibrarySortKey.Rating => "sortRating",
            LibrarySortKey.FileSize => "sortFileSize",
            _ => "sortInputOrder",
        },
        "Text");

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
        foreach (string extension in ImageSourcePaths.SupportedImportExtensions)
        {
            picker.FileTypeFilter.Add(extension);
        }

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
        foreach (string extension in ImageSourcePaths.SupportedImportExtensions)
        {
            picker.FileTypeFilter.Add(extension);
        }

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
        // 설정에서 고른 기본 스캔 회전을 스캔 흐름에 꽂습니다. Shell.Core 는 설정 파일을
        // 읽지 않으므로 여기가 유일한 연결점입니다.
        ScanPanel.ApplyDefaultRotation(preferences.DefaultScanRotation);
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

    private void SynchronizeFrameSelection(IReadOnlyList<LibraryFrameListItem> visibleItems)
    {
        if (libraryHost is null)
        {
            return;
        }
        Dictionary<string, LibraryFrameListItem> byId = visibleItems.ToDictionary(
            item => item.Id,
            StringComparer.Ordinal);
        FrameListView.SelectionChanged -= OnFrameSelectionChanged;
        try
        {
            FrameListView.SelectedItems.Clear();
            foreach (string frameId in libraryHost.SelectedFrameIds.Where(id =>
                         !string.Equals(id, libraryHost.ActiveFrameId, StringComparison.Ordinal)))
            {
                if (byId.TryGetValue(frameId, out LibraryFrameListItem? item))
                {
                    FrameListView.SelectedItems.Add(item);
                }
            }
            if (libraryHost.ActiveFrameId is { } activeFrameId &&
                byId.TryGetValue(activeFrameId, out LibraryFrameListItem? active))
            {
                // 마지막에 넣은 항목이 WinUI의 active item이 되므로 multi-selection도 보존됩니다.
                FrameListView.SelectedItems.Add(active);
                FrameListView.ScrollIntoView(active);
            }
        }
        finally
        {
            FrameListView.SelectionChanged += OnFrameSelectionChanged;
        }
    }

    private async void OnLoaded(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        await ScanPanel.DetectOnLoadAsync();
    }

    private void OnImportScannerClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        _ = ScanPanel.OpenAsync();
    }

    private void LocalizeScanSection()
    {
        SetButtonText(ImportImagesButton, AppResources.Get("libraryImportImageShort", "Content"));
        SetButtonText(ImportFoldersButton, AppResources.Get("libraryImportFolderShort", "Content"));
        SetToggleButtonText(
            ImportScannerButton,
            AppResources.Get("libraryScannerLabel", "Content"));
        ScanPanel.Localize();
    }

    private static void SetToggleButtonText(ToggleButton toggle, string text)
    {
        toggle.Content = text;
        AutomationProperties.SetName(toggle, text);
        ToolTipService.SetToolTip(toggle, text);
    }

    /// <summary>
    /// 지금 스캔 중인 롤의 사진들입니다. 활성 롤이 없으면 빈 목록이고, 그러면 이 축은 꺼진
    /// 것과 같이 동작합니다.
    /// </summary>
    private IReadOnlyList<string> CurrentRollFrameIds()
    {
        if (libraryHost?.ActiveRollId is not { } activeRollId)
        {
            return [];
        }
        return libraryHost.Rolls.FirstOrDefault(roll =>
            string.Equals(roll.Id, activeRollId, StringComparison.Ordinal))?.FrameIds ?? [];
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

    private void LocalizeControls()
    {
        // 사진 이름은 Shell.Core 가 짓지만 문구는 여기에 있습니다. 꽂아 두지 않으면 카드가
        // 영어 기본값으로 불립니다.
        LibraryFrameNaming.NumberFormat = static number =>
            AppResources.FormatIntegers("frameDisplayFormat", "Text", number);
        LibraryFrameNaming.CopyFormat = static (number, copy) =>
            AppResources.FormatIntegers("frameCopyDisplayFormat", "Text", number, copy);
        // 이름 자리는 macOS 가 %@ 로 두는 곳입니다. .NET 리소스에서는 {0} 으로 두고 여기서
        // 갈아 끼웁니다 — 숫자 치환기가 %d 만 알기 때문입니다.
        LibraryFrameNaming.NamedCopyFormat = static (name, copy) =>
            AppResources.FormatIntegers("namedFrameCopyDisplayFormat", "Text", copy)
                .Replace("{0}", name, StringComparison.Ordinal);
        SetNameAndTooltip(ImportRailButton, "importSection");
        SetNameAndTooltip(FilesRailButton, "libraryFiles");
        SetNameAndTooltip(CollectionsRailButton, "libraryCollections");
        string import = AppResources.Get("importSection", "Text");
        ImportHeaderText.Text = import;
        ImportSectionText.Text = import;
        CollectionsPanel.Localize();
        DevelopDefaultsPanel.Localize();
        CullingSurface.Localize();
        UpdateSourcePanel();
        string importImages = AppResources.Get("importImages", "Content");
        SetButtonText(ImportImagesButton, importImages);
        SetButtonText(EmptyImportImagesButton, importImages);
        LocalizeScanSection();
        SetButtonText(AllModeButton, AppResources.Get("libraryAllShort", "Text"));
        SetButtonText(FoldersModeButton, AppResources.Get("libraryFolders", "Text"));
        SetDropDownText(FilmTypeModeButton, AppResources.Get("libraryFilmType", "Text"));
        SetButtonText(OfflineModeButton, AppResources.Get("libraryOffline", "Text"));
        SetMenuItemText(ColorNegativeFilmTypeItem, AppResources.Get("filmTypeColorNegative", "Text"));
        SetMenuItemText(ColorPositiveFilmTypeItem, AppResources.Get("filmTypeColorPositive", "Text"));
        SetMenuItemText(BlackAndWhiteNegativeFilmTypeItem, AppResources.Get("filmTypeBlackAndWhiteNegative", "Text"));
        SetMenuItemText(BlackAndWhitePositiveFilmTypeItem, AppResources.Get("filmTypeBlackAndWhitePositive", "Text"));
        FiltersText.Text = AppResources.Get("libraryFilters", "Content");
        AutomationProperties.SetName(FiltersButton, FiltersText.Text);
        SetToggleText(PickedFilterToggle, AppResources.Get("picked", "Text"));
        SetToggleText(RejectedFilterToggle, AppResources.Get("rejected", "Text"));
        SetToggleText(OfflineFilterToggle, AppResources.Get("libraryOffline", "Text"));
        SetToggleText(InfraredFilterToggle, AppResources.Get("filterInfrared", "Text"));
        SetToggleText(DefectRecipeFilterToggle, AppResources.Get("filterDefectRecipe", "Text"));
        SetToggleText(
            CurrentRollFilterToggle,
            AppResources.Get("filterCurrentRoll", "Text"));
        SetToggleText(
            MetadataUnknownFilterToggle,
            AppResources.Get("libraryFilterMetadataUnknown", "Content"));
        SetToggleText(
            UnvalidatedProfileFilterToggle,
            AppResources.Get("libraryFilterUnvalidatedProfile", "Content"));
        SetButtonText(ClearFiltersButton, AppResources.Get("clearFilters", "Text"));
        SetMenuItemText(RatingFilterAnyItem, AppResources.Get("filterAll", "Text"));
        for (int rating = 1; rating <= 5; ++rating)
        {
            SetMenuItemText(
                RatingFilterItem(rating),
                AppResources.FormatIntegers("filterMinimumRating", "Text", rating));
        }
        SetMenuItemText(SortInputOrderItem, AppResources.Get("sortInputOrder", "Text"));
        SetMenuItemText(SortTimeItem, AppResources.Get("sortTime", "Text"));
        SetMenuItemText(SortNameItem, AppResources.Get("sortName", "Text"));
        SetMenuItemText(SortFlagItem, AppResources.Get("sortFlag", "Text"));
        SetMenuItemText(SortRatingItem, AppResources.Get("sortRating", "Text"));
        SetMenuItemText(SortFileSizeItem, AppResources.Get("sortFileSize", "Text"));
        SetMenuItemText(SortAscendingItem, AppResources.Get("sortAscending", "Text"));
        SetMenuItemText(SortDescendingItem, AppResources.Get("sortDescending", "Text"));
        string cardSizeHelp = AppResources.Get("frameCardSizeHelp", "Value");
        foreach (Button button in new[] { CardSizeDecreaseButton, CardSizeResetButton, CardSizeIncreaseButton })
        {
            AutomationProperties.SetName(button, cardSizeHelp);
            ToolTipService.SetToolTip(button, cardSizeHelp);
        }
        UpdateSortControls();
        UpdateCardSizeControls();
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

    private MenuFlyoutItem RatingFilterItem(int rating) => rating switch
    {
        1 => RatingFilterOneItem,
        2 => RatingFilterTwoItem,
        3 => RatingFilterThreeItem,
        4 => RatingFilterFourItem,
        _ => RatingFilterFiveItem,
    };

    private static void SetToggleText(ToggleButton toggle, string text)
    {
        toggle.Content = text;
        AutomationProperties.SetName(toggle, text);
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
