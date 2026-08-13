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

    /// <summary>
    /// 카드 크기는 macOS 와 같은 규칙입니다 — 폭 190·배율, 썸네일은 (폭 − 안쪽 여백) / 1.5,
    /// 그 아래 이름·필름 종류·별점이 고정 높이로 붙습니다.
    /// </summary>
    private void OnFrameContainerChanging(ListViewBase sender, ContainerContentChangingEventArgs args)
    {
        _ = sender;
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
                LibraryFrameListItems.Filter(allItems, LibrarySearchBox?.Text ?? string.Empty)),
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

    private void LocalizeControls()
    {
        SetNameAndTooltip(ImportRailButton, "importSection");
        SetNameAndTooltip(FilesRailButton, "libraryFiles");
        SetNameAndTooltip(CollectionsRailButton, "libraryCollections");
        string import = AppResources.Get("importSection", "Text");
        ImportHeaderText.Text = import;
        ImportSectionText.Text = import;
        CollectionsEmptyText.Text = AppResources.Get("libraryCollectionsEmpty", "Text");
        UpdateSourcePanel();
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
        FiltersText.Text = AppResources.Get("libraryFilters", "Content");
        AutomationProperties.SetName(FiltersButton, FiltersText.Text);
        SetToggleText(PickedFilterToggle, AppResources.Get("picked", "Text"));
        SetToggleText(RejectedFilterToggle, AppResources.Get("rejected", "Text"));
        SetToggleText(OfflineFilterToggle, AppResources.Get("libraryOffline", "Text"));
        SetToggleText(InfraredFilterToggle, AppResources.Get("filterInfrared", "Text"));
        SetToggleText(DefectRecipeFilterToggle, AppResources.Get("filterDefectRecipe", "Text"));
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
