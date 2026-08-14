using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media.Imaging;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views;

public sealed partial class LibraryWorkspaceView : UserControl
{
    private WorkspacePresentationState? workspaceState;
    private LibraryHostService? libraryHost;
    private ScanSessionController? scanSession;
    private ScannerPluginTrustStore? scannerTrust;
    private bool isSynchronizingScan;
    /// <summary>마지막 프리뷰 스캔의 밝기 값입니다. 자동 프레임 찾기가 이것으로 셉니다.</summary>
    private PreviewLuminance flatbedPreview = PreviewLuminance.None;
    private bool isSynchronizingCollections;
    private string? selectedCollectionId;
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
        allItems = LibraryFrameListItems.From(host.Frames, host.SourceAvailabilityByFrameId);
        RebuildCollections();
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
        _ = args;
        libraryHost?.SetSelection(FrameListView.SelectedItems
            .OfType<LibraryFrameListItem>()
            .Select(item => item.Id));
    }

    /// <summary>사용자가 라이브러리에서 현상으로 넘기려는 frame 입니다.</summary>
    public event EventHandler<LibraryFrameListItem>? FrameOpenRequested;

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
                ApplyCollection(
                    LibraryFrameListItems.Filter(
                        allItems,
                        LibrarySearchBox?.Text ?? string.Empty))),
            sortKey,
            sortAscending);
        UpdateSortControls();
        UpdateCardSizeControls();
        UpdateFilterControls();
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
        CollectionsSourcePanel.Visibility = sourceKind == LibrarySourceKind.Collections
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
        FilesSourceTree.RootNodes.Clear();
        if (libraryHost is null)
        {
            return;
        }
        LibraryBrowserProjection projection = LibraryBrowserProjector.Create(
            quickFilters.Apply(
                LibraryFrameListItems.Filter(allItems, LibrarySearchBox?.Text ?? string.Empty)),
            libraryHost.Folders,
            libraryHost.FolderAvailabilityById,
            LibraryBrowserViewMode.Folders);
        foreach (LibraryBrowserFolderSection section in projection.FolderSections)
        {
            var folder = new TreeViewNode
            {
                Content = LibrarySourceNode.Folder(
                    section.Title,
                    AppResources.FormatIntegers("libraryFolderFrameCount", "Text", section.Count)),
            };
            foreach (LibraryFrameListItem item in section.Items)
            {
                folder.Children.Add(new TreeViewNode
                {
                    Content = LibrarySourceNode.Frame(item.DisplayName, item.Id),
                });
            }
            FilesSourceTree.RootNodes.Add(folder);
        }
        SourceHeaderCountText.Text = AppResources.FormatIntegers(
            "libraryFolderFrameCount",
            "Text",
            projection.MatchedCount);
    }

    /// <summary>트리에서 frame 을 누르면 격자의 선택도 따라갑니다.</summary>
    private void OnSourceTreeItemInvoked(TreeView sender, TreeViewItemInvokedEventArgs args)
    {
        _ = sender;
        if (args.InvokedItem is not TreeViewNode { Content: LibrarySourceNode node } ||
            node.FrameId is not { } frameId)
        {
            return;
        }
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

    // MARK: - 스캔 절
    //
    // macOS ScannerControlsSection 과 같은 구성입니다. 플러그인 경계와 카탈로그 게시는
    // ScanSessionController 가 들고 있고, 여기서는 그 상태를 컨트롤에 옮기기만 합니다.

    private void EnsureScanSession()
    {
        if (scanSession is not null)
        {
            return;
        }
        if (DispatcherQueueUiDispatcher.CaptureForCurrentThread() is not { } uiDispatcher)
        {
            return;
        }
        scannerTrust = new ScannerPluginTrustStore();
        scanSession = new ScanSessionController(
            new ScannerPluginGateway(),
            scannerTrust,
            uiDispatcher);
        scanSession.Changed += OnScanSessionChanged;
    }

    private void OnScanSessionChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (DispatcherQueue.HasThreadAccess)
        {
            RenderScanSection();
            return;
        }
        _ = DispatcherQueue.TryEnqueue(RenderScanSection);
    }

    private async void OnImportScannerClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        EnsureScanSession();
        if (scanSession is null || ImportScannerButton.IsChecked != true)
        {
            RenderScanSection();
            return;
        }
        // 열 때마다 플러그인 목록을 다시 읽습니다 — 방금 설치한 플러그인이 보여야 합니다.
        scanSession.Refresh();
        if (scanSession.State is ScanSessionState.NoDevice)
        {
            await scanSession.RefreshDevicesAsync();
        }
    }

    private void OnScanApprovePluginClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (scanSession?.PluginsRequiringApproval is not { Count: > 0 } pending)
        {
            return;
        }
        foreach (InstalledScannerPlugin plugin in pending)
        {
            scanSession.Approve(plugin);
        }
    }

    /// <summary>
    /// 하드웨어 없이 스캔 흐름을 돌립니다. 켜면 가상 장치가 나타나고, 스캔은 합성 네거티브를
    /// 실제와 같은 게시 경로로 카탈로그에 올립니다.
    /// </summary>
    private async void OnScanSimulatorToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingScan || scanSession is null)
        {
            return;
        }
        scanSession.SetSimulatorEnabled(ScanSimulatorToggle.IsOn);
        if (scanSession.State is ScanSessionState.NoDevice)
        {
            await scanSession.RefreshDevicesAsync();
        }
    }

    private async void OnScanRescanClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (scanSession is not null)
        {
            await scanSession.RefreshDevicesAsync();
        }
    }

    private async void OnScanDeviceChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingScan ||
            scanSession is null ||
            ScanDeviceSelector.SelectedItem is not ComboBoxItem { Tag: string deviceId })
        {
            return;
        }
        await scanSession.SelectDeviceAsync(deviceId);
    }

    private void OnScanFilmChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingScan ||
            ScanFilmSelector.SelectedItem is not ComboBoxItem { Tag: FilmType filmType })
        {
            return;
        }
        scanSession?.UpdateOptions(options => options with { FilmType = filmType });
    }

    private void OnScanFolderNameChanged(object sender, TextChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingScan)
        {
            return;
        }
        scanSession?.UpdateOptions(options => options with { FolderName = ScanFolderNameBox.Text });
    }

    private void OnScanResolutionChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingScan ||
            ScanResolutionSelector.SelectedItem is not ComboBoxItem { Tag: int dpi })
        {
            return;
        }
        scanSession?.UpdateOptions(options => options with { ResolutionDpi = dpi });
    }

    private void OnScanColorModeChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingScan ||
            ScanColorModeSelector.SelectedItem is not ComboBoxItem { Tag: string mode })
        {
            return;
        }
        scanSession?.UpdateOptions(options => options with { ColorMode = mode });
    }

    private void OnScanBitDepthChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingScan ||
            ScanBitDepthSelector.SelectedItem is not ComboBoxItem { Tag: int depth })
        {
            return;
        }
        scanSession?.UpdateOptions(options => options with { BitDepth = depth });
    }

    private void OnScanFrameCountChanged(NumberBox sender, NumberBoxValueChangedEventArgs args)
    {
        _ = sender;
        if (isSynchronizingScan || double.IsNaN(args.NewValue))
        {
            return;
        }
        scanSession?.UpdateOptions(options => options with { BatchCount = (int)args.NewValue });
    }

    private void OnScanInfraredToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingScan)
        {
            return;
        }
        scanSession?.UpdateOptions(options => options with { Infrared = ScanInfraredToggle.IsOn });
    }

    private void OnScanFrameFormatChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingScan ||
            ScanFrameFormatSelector.SelectedItem is not ComboBoxItem { Tag: FlatbedFrameFormat format })
        {
            return;
        }
        scanSession?.UpdateOptions(options => options with { FrameFormat = format });
    }

    private void OnScanDetectionModeChecked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingScan || scanSession is null)
        {
            return;
        }
        scanSession.UpdateOptions(options => options with
        {
            FrameDetectionMode = ScanDetectionManualButton.IsChecked == true
                ? FlatbedFrameDetectionMode.Manual
                : FlatbedFrameDetectionMode.Automatic,
        });
    }

    /// <summary>
    /// 자동이면 프리뷰에서 다시 찾고, 수동이면 지우고 규격 프레임 하나를 놓아 다시 시작할 자리를
    /// 만듭니다 — macOS 새로고침과 같은 규칙입니다.
    /// </summary>
    private void OnScanRefreshFramesClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (scanSession is null)
        {
            return;
        }
        // 프리뷰 픽셀이 아직 없으면 찾을 근거가 없습니다. macOS 도 프리뷰 전에는 잠급니다.
        _ = scanSession.RefreshRegions(
            flatbedPreview.Values,
            flatbedPreview.Width,
            flatbedPreview.Height);
        RenderScanSection();
    }

    private void OnScanAddFrameClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        _ = scanSession?.AddRegion();
        RenderScanSection();
    }

    private void OnScanRemoveFrameClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        _ = scanSession?.DeleteSelectedRegion();
        RenderScanSection();
    }

    private void OnScanCopyFrameClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        _ = scanSession?.CopySelectedRegion();
        RenderScanSection();
    }

    private void OnScanPasteFrameClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        _ = scanSession?.PasteRegion();
        RenderScanSection();
    }

    private async void OnScanPreviewClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        await RunScanAsync(preview: true);
    }

    private async void OnScanStartClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        await RunScanAsync(preview: false);
    }

    /// <summary>
    /// 스캔해서 카탈로그에 게시하고 격자를 다시 그립니다. 목적지는 매 장마다 새로 고르므로
    /// 이어서 뜨는 배치가 서로를 덮지 않습니다.
    /// </summary>
    private async Task RunScanAsync(bool preview)
    {
        if (scanSession is null || libraryHost is null)
        {
            return;
        }
        if (libraryHost.StorageRoots is not { } roots)
        {
            ScanStatusText.Text = AppResources.Get("libraryImportFailed", "Text");
            return;
        }

        string rollName = string.IsNullOrWhiteSpace(scanSession.Options.FolderName)
            ? AppResources.Get("scanUntitledFilm", "Text")
            : scanSession.Options.FolderName;
        string stem = ScanStorageLayout.ScannerAbbreviation(
            scanSession.SelectedDevice?.DisplayName);
        string directory;
        try
        {
            directory = ScanStorageLayout.EnsureRollDirectory(
                Path.Combine(roots.LibraryRoot, "Scans"),
                scanSession.Options.FilmType,
                rollName,
                DateTime.Now);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            ScanStatusText.Text = AppResources.Get("libraryImportFailed", "Text");
            return;
        }

        ScanStatusText.Text = AppResources.Get("scanSection", "Text");
        ScanRunOutcome outcome = await scanSession.RunAsync(
            libraryHost,
            _ => ScanStorageLayout.NextAvailablePath(directory, stem),
            preview);
        ScanStatusText.Text = DescribeScanOutcome(outcome);
        if (preview)
        {
            // 프리뷰는 카탈로그에 올리지 않습니다. 그림만 읽어 두었다가 프레임 찾기에 넘깁니다.
            flatbedPreview = scanSession.LastPreviewPath is { } previewPath
                ? await PreviewLuminanceReader.ReadAsync(previewPath)
                : PreviewLuminance.None;
            if (!flatbedPreview.IsEmpty &&
                scanSession.Options.FrameDetectionMode == FlatbedFrameDetectionMode.Automatic)
            {
                _ = scanSession.RefreshRegions(
                    flatbedPreview.Values,
                    flatbedPreview.Width,
                    flatbedPreview.Height);
            }
            RenderScanSection();
            return;
        }
        if (importWindowId is { } windowId)
        {
            ShowLibrary(libraryHost, windowId);
        }
    }

    private string DescribeScanOutcome(ScanRunOutcome outcome)
    {
        if (outcome.IsSuccess)
        {
            return AppResources.FormatIntegers(
                "libraryFolderImportResult",
                "Text",
                outcome.Published,
                1);
        }
        // 실패는 어느 단계에서 멈췄는지를 남깁니다. "스캔 실패" 만으로는 다시 시도하는 것 말고
        // 사용자가 할 수 있는 일이 없습니다.
        string reason = scanSession?.LastFailureName ??
            outcome.LastScanStatus?.ToString() ??
            "unavailable";
        return AppResources.Get("libraryImportFailed", "Text") + " — " + reason;
    }

    /// <summary>
    /// 세션 상태를 컨트롤에 옮깁니다. macOS 와 같은 세 갈래(플러그인 없음 · 승인 필요 ·
    /// 연결 대기)를 그대로 냅니다.
    /// </summary>
    private void RenderScanSection()
    {
        if (ScanSectionCard is null)
        {
            return;
        }
        bool wanted = ImportScannerButton.IsChecked == true;
        ScanSessionState state = scanSession?.State ?? ScanSessionState.NoPlugin;
        ScanSectionText.Visibility = wanted ? Visibility.Visible : Visibility.Collapsed;
        ScanSectionCard.Visibility = ScanSectionText.Visibility;
        if (!wanted || scanSession is null)
        {
            return;
        }

        bool ready = state is ScanSessionState.Ready or ScanSessionState.Scanning;
        ScanControls.Visibility = ready ? Visibility.Visible : Visibility.Collapsed;
        ScanApprovePluginButton.Visibility = state == ScanSessionState.NeedsApproval
            ? Visibility.Visible
            : Visibility.Collapsed;
        ScanStateText.Text = state switch
        {
            ScanSessionState.NoPlugin => AppResources.Get("scanPluginMissingTitle", "Text") + "\n" +
                AppResources.Get("scanPluginMissingBody", "Text"),
            ScanSessionState.NeedsApproval => AppResources.Get("scanPluginApprovalTitle", "Text"),
            ScanSessionState.Searching => AppResources.Get("scanSearching", "Text"),
            ScanSessionState.NoDevice => AppResources.Get("scanWaitingStatus", "Text"),
            _ => string.Empty,
        };
        isSynchronizingScan = true;
        try
        {
            ScanSimulatorToggle.IsOn = scanSession.SimulatorEnabled;
        }
        finally
        {
            isSynchronizingScan = false;
        }
        ScanStateText.Visibility = ScanStateText.Text.Length == 0
            ? Visibility.Collapsed
            : Visibility.Visible;
        if (!ready)
        {
            return;
        }

        isSynchronizingScan = true;
        try
        {
            FillTagged(
                ScanDeviceSelector,
                [.. scanSession.Devices.Select(device =>
                    ((object)device.DisplayName, (object)device.Id))],
                scanSession.SelectedDevice?.Id);
            FillTagged(
                ScanFilmSelector,
                [.. FilmTypes.Select(film =>
                    ((object)FilmTypeNameConverter.Name(film), (object)film))],
                scanSession.Options.FilmType);
            FillTagged(
                ScanResolutionSelector,
                [.. scanSession.Resolutions.Select(dpi =>
                    ((object)string.Create(CultureInfo.CurrentCulture, $"{dpi} dpi"), (object)dpi))],
                scanSession.Options.ResolutionDpi);
            FillTagged(
                ScanColorModeSelector,
                [.. scanSession.ColorModes.Select(mode =>
                    ((object)ColorModeLabel(mode), (object)mode))],
                scanSession.Options.ColorMode);
            int channels = string.Equals(
                scanSession.Options.ColorMode,
                ScanSessionController.ColorModeGray,
                StringComparison.Ordinal) ? 1 : 3;
            FillTagged(
                ScanBitDepthSelector,
                [.. scanSession.BitDepths.Select(depth => ((object)string.Create(
                    CultureInfo.CurrentCulture,
                    $"{depth}-bit/ch ({depth * channels}-bit)"), (object)depth))],
                scanSession.Options.BitDepth);
            if (ScanFolderNameBox.Text != scanSession.Options.FolderName)
            {
                ScanFolderNameBox.Text = scanSession.Options.FolderName;
            }
            ScanFrameCountBox.Value = scanSession.Options.BatchCount;
            FillTagged(
                ScanFrameFormatSelector,
                [.. scanSession.AvailableFrameFormats.Select(format =>
                    ((object)FilmFrameFormats.DisplayName(format), (object)format))],
                scanSession.Options.FrameFormat);
            ScanDetectionAutomaticButton.IsChecked =
                scanSession.Options.FrameDetectionMode == FlatbedFrameDetectionMode.Automatic;
            ScanDetectionManualButton.IsChecked =
                scanSession.Options.FrameDetectionMode == FlatbedFrameDetectionMode.Manual;
            ScanInfraredToggle.IsOn = scanSession.Options.Infrared;
        }
        finally
        {
            isSynchronizingScan = false;
        }

        bool flatbed = scanSession.UsesFlatbedRegionWorkflow;
        ScanFrameFormatRow.Visibility = scanSession.AvailableFrameFormats.Count > 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        ScanDetectionModeRow.Visibility = flatbed ? Visibility.Visible : Visibility.Collapsed;
        ScanRegionsRow.Visibility = ScanDetectionModeRow.Visibility;
        // 평판에서는 판 위에 놓인 프레임 수가 곧 스캔 수이므로 사진 수 줄이 없습니다.
        ScanFrameCountRow.Visibility = flatbed ? Visibility.Collapsed : Visibility.Visible;
        ScanRegionsLabel.Text = AppResources.FormatInteger(
            "scanFlatbedFramesFormat",
            "Text",
            scanSession.Regions.Count);
        bool hasSelectedRegion = scanSession.SelectedRegionId is not null;
        ScanCopyFrameButton.IsEnabled = hasSelectedRegion;
        ScanRemoveFrameButton.IsEnabled = hasSelectedRegion;
        ScanPasteFrameButton.IsEnabled = scanSession.CopiedRegion is not null;
        // 프리뷰 픽셀이 없으면 찾을 근거가 없습니다.
        ScanRefreshFramesButton.IsEnabled = !flatbedPreview.IsEmpty ||
            scanSession.Options.FrameDetectionMode == FlatbedFrameDetectionMode.Manual;

        bool hasDepths = scanSession.BitDepths.Count > 0;
        ScanBitDepthRow.Visibility = hasDepths ? Visibility.Visible : Visibility.Collapsed;
        ScanBitDepthUnavailableText.Visibility = hasDepths
            ? Visibility.Collapsed
            : Visibility.Visible;
        ScanInfraredToggle.Visibility = scanSession.Capabilities?.SupportsInfrared == true
            ? Visibility.Visible
            : Visibility.Collapsed;
        ScanInfraredToggle.IsEnabled = scanSession.CanUseInfrared;
        ScanPreviewButton.Visibility = scanSession.Capabilities?.SupportsPreview == true
            ? Visibility.Visible
            : Visibility.Collapsed;
        ScanPreviewButton.IsEnabled = scanSession.CanPreview;
        ScanStartButton.IsEnabled = scanSession.CanScan;
        ScanRescanButton.IsEnabled = !scanSession.IsDetecting && !scanSession.IsScanning;
        ScanControls.IsHitTestVisible = !scanSession.IsScanning;
        SetButtonText(
            ScanStartButton,
            scanSession.Options.BatchCount > 1
                ? AppResources.FormatInteger("scanCountFormat", "Text", scanSession.Options.BatchCount)
                : AppResources.Get("scanStart", "Content"));
        ScanFrameCountLabel.Text = AppResources.FormatInteger(
            "scanFramesFormat",
            "Text",
            scanSession.Options.BatchCount);
    }

    /// <summary>macOS 스캔 절의 필름 목록 순서입니다.</summary>
    private static IReadOnlyList<FilmType> FilmTypes { get; } =
    [
        FilmType.ColorNegative,
        FilmType.ColorPositive,
        FilmType.BlackAndWhiteNegative,
        FilmType.BlackAndWhitePositive,
    ];

    private static string ColorModeLabel(string mode) =>
        mode.Length == 0 ? mode : char.ToUpperInvariant(mode[0]) + mode[1..];

    /// <summary>
    /// 목록을 갈아 끼우고 고른 값을 다시 잡습니다. 목록을 지우면 선택이 풀리므로 항상 짝으로
    /// 해야 합니다.
    /// </summary>
    private static void FillTagged(
        ComboBox selector,
        IReadOnlyList<(object Text, object Tag)> items,
        object? selectedTag)
    {
        selector.Items.Clear();
        foreach ((object text, object tag) in items)
        {
            selector.Items.Add(new ComboBoxItem { Content = text, Tag = tag });
        }
        foreach (object item in selector.Items)
        {
            if (item is ComboBoxItem candidate && Equals(candidate.Tag, selectedTag))
            {
                selector.SelectedItem = candidate;
                return;
            }
        }
    }

    private void LocalizeScanSection()
    {
        SetButtonText(ImportImagesButton, AppResources.Get("libraryImportImageShort", "Content"));
        SetButtonText(ImportFoldersButton, AppResources.Get("libraryImportFolderShort", "Content"));
        SetToggleButtonText(
            ImportScannerButton,
            AppResources.Get("libraryScannerLabel", "Content"));
        ScanSectionText.Text = AppResources.Get("scanSection", "Text");
        ScanDeviceLabel.Text = AppResources.Get("libraryScannerLabel", "Content");
        AutomationProperties.SetName(ScanDeviceSelector, ScanDeviceLabel.Text);
        SetButtonText(ScanApprovePluginButton, AppResources.Get("scanPluginApprove", "Content"));
        string simulator = AppResources.Get("scanSimulator", "Content");
        ScanSimulatorToggle.Header = simulator;
        ScanSimulatorToggle.OnContent = simulator;
        ScanSimulatorToggle.OffContent = simulator;
        AutomationProperties.SetName(ScanSimulatorToggle, simulator);
        ToolTipService.SetToolTip(
            ScanSimulatorToggle,
            AppResources.Get("scanSimulatorHelp", "Text"));
        string rescan = AppResources.Get("scanDetectScanners", "Text");
        AutomationProperties.SetName(ScanRescanButton, rescan);
        ToolTipService.SetToolTip(ScanRescanButton, rescan);
        ScanFilmLabel.Text = AppResources.Get("scanFilm", "Text");
        AutomationProperties.SetName(ScanFilmSelector, ScanFilmLabel.Text);
        ScanFolderNameLabel.Text = AppResources.Get("scanFolderName", "Text");
        ScanFolderNameBox.PlaceholderText = AppResources.Get("scanUntitledFilm", "Text");
        AutomationProperties.SetName(ScanFolderNameBox, ScanFolderNameLabel.Text);
        AutomationProperties.SetName(
            ScanResolutionSelector,
            AppResources.Get("scanResolution", "Text"));
        AutomationProperties.SetName(
            ScanColorModeSelector,
            AppResources.Get("scanColorMode", "Text"));
        ScanBitDepthLabel.Text = AppResources.Get("scanBitDepth", "Text");
        AutomationProperties.SetName(ScanBitDepthSelector, ScanBitDepthLabel.Text);
        ScanBitDepthUnavailableText.Text = AppResources.Get("scanBitDepthUnavailable", "Text");
        ScanFrameFormatLabel.Text = AppResources.Get("scanFrameFormat", "Text");
        AutomationProperties.SetName(ScanFrameFormatSelector, ScanFrameFormatLabel.Text);
        ScanDetectionModeLabel.Text = AppResources.Get("scanDetectionMode", "Text");
        SetRadioText(
            ScanDetectionAutomaticButton,
            AppResources.Get("scanDetectionAutomatic", "Content"));
        SetRadioText(
            ScanDetectionManualButton,
            AppResources.Get("scanDetectionManual", "Content"));
        SetIconButtonName(ScanRefreshFramesButton, "scanRefreshFrames");
        SetIconButtonName(ScanCopyFrameButton, "scanCopyFrame");
        SetIconButtonName(ScanPasteFrameButton, "scanPasteFrame");
        SetIconButtonName(ScanAddFrameButton, "scanAddFrame");
        SetIconButtonName(ScanRemoveFrameButton, "scanRemoveFrame");
        ScanFrameCountLabel.Text = AppResources.FormatInteger("scanFramesFormat", "Text", 1);
        AutomationProperties.SetName(ScanFrameCountBox, ScanFrameCountLabel.Text);
        string infrared = AppResources.Get("scanInfrared", "Content");
        ScanInfraredToggle.Header = infrared;
        ScanInfraredToggle.OnContent = infrared;
        ScanInfraredToggle.OffContent = infrared;
        AutomationProperties.SetName(ScanInfraredToggle, infrared);
        SetButtonText(ScanPreviewButton, AppResources.Get("scanPreview", "Content"));
        SetButtonText(ScanStartButton, AppResources.Get("scanStart", "Content"));
    }

    /// <summary>글리프만 있는 단추의 이름입니다. 이름이 없으면 화면 낭독기가 읽지 못합니다.</summary>
    private static void SetIconButtonName(Button button, string resourceKey)
    {
        string text = AppResources.Get(resourceKey, "Text");
        AutomationProperties.SetName(button, text);
        ToolTipService.SetToolTip(button, text);
    }

    private static void SetRadioText(RadioButton radio, string text)
    {
        radio.Content = text;
        AutomationProperties.SetName(radio, text);
    }

    private static void SetToggleButtonText(ToggleButton toggle, string text)
    {
        toggle.Content = text;
        AutomationProperties.SetName(toggle, text);
        ToolTipService.SetToolTip(toggle, text);
    }

    // MARK: - 컬렉션
    //
    // macOS 처럼 "전체 보기" 가 늘 맨 위에 있고 그 아래 사용자가 만든 묶음이 옵니다. 고른 묶음이
    // 격자를 좁히며, 새 묶음은 지금 격자에서 고른 사진으로 만듭니다.

    /// <summary>목록 한 줄입니다. 이름을 한 곳에서만 만들어야 줄마다 말이 달라지지 않습니다.</summary>
    private sealed record CollectionRow(string? Id, string Name, string CountText, string Glyph);

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

    private void RebuildCollections()
    {
        if (CollectionsList is null || libraryHost is null)
        {
            return;
        }
        var rows = new List<CollectionRow>
        {
            new(
                null,
                AppResources.Get("libraryAllPhotos", "Text"),
                libraryHost.Frames.Count.ToString(CultureInfo.CurrentCulture),
                "\uE91B"),
        };
        foreach (LibraryCollectionSnapshot collection in libraryHost.Collections)
        {
            rows.Add(new CollectionRow(
                collection.Id,
                collection.Name,
                collection.FrameIds.Count.ToString(CultureInfo.CurrentCulture),
                "\uE8B7"));
        }
        isSynchronizingCollections = true;
        try
        {
            CollectionsList.ItemsSource = rows;
            CollectionsList.SelectedItem = rows.FirstOrDefault(row =>
                string.Equals(row.Id, selectedCollectionId, StringComparison.Ordinal))
                ?? rows[0];
        }
        finally
        {
            isSynchronizingCollections = false;
        }
        bool hasSelection = selectedCollectionId is not null;
        CollectionRenameButton.IsEnabled = hasSelection;
        CollectionDeleteButton.IsEnabled = hasSelection;
    }

    private void OnCollectionSelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingCollections ||
            CollectionsList.SelectedItem is not CollectionRow row)
        {
            return;
        }
        selectedCollectionId = row.Id;
        CollectionRenameButton.IsEnabled = row.Id is not null;
        CollectionDeleteButton.IsEnabled = row.Id is not null;
        if (row.Id is not null)
        {
            CollectionNameBox.Text = row.Name;
        }
        ShowFilteredItems();
    }

    private void OnCreateCollectionClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (libraryHost is null)
        {
            return;
        }
        // macOS 와 같이 지금 고른 사진으로 만듭니다. 고른 것이 없으면 빈 묶음입니다.
        string name = CollectionNameBox.Text;
        if (string.IsNullOrWhiteSpace(name))
        {
            name = AppResources.Get("libraryNewCollection", "Content");
        }
        selectedCollectionId = libraryHost.CreateCollection(
            name,
            FrameListView.SelectedItems.OfType<LibraryFrameListItem>().Select(item => item.Id));
        CollectionNameBox.Text = string.Empty;
        RebuildCollections();
        ShowFilteredItems();
    }

    private void OnRenameCollectionClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (libraryHost is null || selectedCollectionId is not { } collectionId)
        {
            return;
        }
        _ = libraryHost.RenameCollection(collectionId, CollectionNameBox.Text);
        RebuildCollections();
    }

    private void OnDeleteCollectionClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (libraryHost is null || selectedCollectionId is not { } collectionId)
        {
            return;
        }
        _ = libraryHost.DeleteCollection(collectionId);
        selectedCollectionId = null;
        CollectionNameBox.Text = string.Empty;
        RebuildCollections();
        ShowFilteredItems();
    }

    /// <summary>고른 묶음이 격자를 좁힙니다. "전체 보기" 는 좁히지 않습니다.</summary>
    private IReadOnlyList<LibraryFrameListItem> ApplyCollection(
        IReadOnlyList<LibraryFrameListItem> items)
    {
        if (selectedCollectionId is not { } collectionId || libraryHost is null)
        {
            return items;
        }
        if (libraryHost.Collections.FirstOrDefault(collection =>
                string.Equals(collection.Id, collectionId, StringComparison.Ordinal))
            is not { } selected)
        {
            return items;
        }
        var member = new HashSet<string>(selected.FrameIds, StringComparer.Ordinal);
        return [.. items.Where(item => member.Contains(item.Id))];
    }

    private void LocalizeCollections()
    {
        SetButtonText(CollectionRenameButton, AppResources.Get("libraryRename", "Content"));
        SetButtonText(CollectionDeleteButton, AppResources.Get("libraryDelete", "Content"));
        string name = AppResources.Get("libraryCollectionName", "Text");
        CollectionNameBox.PlaceholderText = name;
        AutomationProperties.SetName(CollectionNameBox, name);
        string create = AppResources.Get("libraryNewCollection", "Content");
        AutomationProperties.SetName(CollectionsAddButton, create);
        ToolTipService.SetToolTip(CollectionsAddButton, create);
    }

    private void LocalizeControls()
    {
        SetNameAndTooltip(ImportRailButton, "importSection");
        SetNameAndTooltip(FilesRailButton, "libraryFiles");
        SetNameAndTooltip(CollectionsRailButton, "libraryCollections");
        string import = AppResources.Get("importSection", "Text");
        ImportHeaderText.Text = import;
        ImportSectionText.Text = import;
        LocalizeCollections();
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
