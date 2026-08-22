using System.Globalization;
using Microsoft.UI.Xaml;

namespace Negaflow.Shell.Views.Library.Browser;

/// <summary>필터·정렬된 격자를 다시 그립니다. 선택 동기화와 다른 이유입니다.</summary>
internal sealed class LibraryGridProjection
{
    private readonly LibraryWorkspaceView view;

    internal LibraryGridProjection(LibraryWorkspaceView view) => this.view = view;

    internal void Show()
    {
        IReadOnlyList<LibraryFrameListItem> items = LibrarySorter.Sort(
            view.quickFilters.Apply(
                view.ControlsPanel.CollectionsPanel.Apply(
                    LibraryFrameListItems.Filter(
                        view.allItems,
                        view.LibrarySearchBox?.Text ?? string.Empty))),
            view.sortKey,
            view.sortAscending);
        // 접기는 **정렬 뒤**에 걸립니다. 대표로 남는 것이 화면 차례에서 가장 앞선 사진이어야
        // 정렬을 바꿀 때 대표도 따라 바뀝니다.
        if (view.libraryHost is not null)
        {
            items = LibraryStackProjection.Apply(items, view.libraryHost.Stacks);
            ApplyStackBadges(items);
        }
        view.filters.UpdateSortControls();
        view.filters.UpdateCardSizeControls();
        view.filters.UpdateFilterControls();
        if (view.libraryHost is null)
        {
            view.FrameListView.ItemsSource = items;
            view.LibraryCountText.Text = items.Count.ToString(CultureInfo.CurrentCulture);
            SynchronizeCulling(items);
            return;
        }

        LibraryBrowserProjection projection = LibraryBrowserProjector.Create(
            items,
            view.libraryHost.Folders,
            view.libraryHost.FolderAvailabilityById,
            view.viewMode,
            view.selectedFilmType,
            view.rail.folderDrafts,
            view.rail.collapsedFolders);
        view.isSynchronizingFrameSelection = true;
        try
        {
            if (view.viewMode is LibraryBrowserViewMode.Folders or LibraryBrowserViewMode.FilmType)
            {
                view.FolderGroupedItems.Source = projection.FolderSections;
                view.FrameListView.ItemsSource = view.FolderGroupedItems.View;
            }
            else
            {
                view.FolderGroupedItems.Source = null;
                view.FrameListView.ItemsSource = projection.Items;
            }
            view.LibraryCountText.Text = projection.MatchedCount.ToString(CultureInfo.CurrentCulture);
            view.selection.Synchronize(projection.Items);
        }
        finally
        {
            view.isSynchronizingFrameSelection = false;
        }
        view.filters.UpdateViewModeControls();
        SynchronizeCulling(items);
        if (view.sourceKind == LibrarySourceKind.Files)
        {
            view.rail.RebuildFilesSourceTree();
        }
    }

    /// <summary>
    /// 남아 있는 카드에 묶음 배지를 답니다. 접힌 묶음은 대표 한 장만 남았고, 펼친 묶음은 모든
    /// 구성원이 남아 있으므로 전부에 답니다 — macOS 도 구성원마다 배지를 답니다.
    /// </summary>
    internal void ApplyStackBadges(IReadOnlyList<LibraryFrameListItem> items)
    {
        if (view.libraryHost is not { } host)
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

    internal void SynchronizeCulling(IReadOnlyList<LibraryFrameListItem> ordered)
    {
        view.CullingSurface.Synchronize(
            ordered,
            view.selection.SelectedItems(),
            view.FrameListView.SelectedItem as LibraryFrameListItem);
        view.FrameListView.Visibility = view.CullingSurface.IsGrid
            ? Visibility.Visible
            : Visibility.Collapsed;
        view.SyncFlatbedOverlay();
    }
}
