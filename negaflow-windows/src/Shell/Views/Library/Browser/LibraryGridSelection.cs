using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Negaflow.Catalog;
using Windows.ApplicationModel.DataTransfer;

namespace Negaflow.Shell.Views.Library.Browser;

/// <summary>격자 선택과 드래그입니다. 썸네일 디코드와 다른 이유입니다.</summary>
internal sealed class LibraryGridSelection
{
    /// <summary>
    /// 우리 카드에서 시작한 끌기인지 알아보는 표식입니다. 이것이 없으면 탐색기에서 끌어온
    /// 파일도 폴더 줄이 받아들입니다.
    /// </summary>
    internal const string FrameDragFormat = "negaflow.library-source";

    private readonly LibraryWorkspaceView view;

    internal LibraryGridSelection(LibraryWorkspaceView view) => this.view = view;

    /// <summary>
    /// 카드를 두 번 누르면 그 frame 을 들고 현상으로 넘어갑니다. macOS 와 같은 진입 방식이며,
    /// 두 화면이 각자 목록을 들고 있어 생기던 "어떤 사진을 보고 있었는지" 불일치를 없앱니다.
    /// </summary>
    internal void OnDoubleTapped(object sender, DoubleTappedRoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (view.FrameListView.SelectedItem is not LibraryFrameListItem item)
        {
            return;
        }
        view.RaiseFrameOpenRequested(item);
        view.workspaceState?.SelectWorkspace(WorkspaceModule.Develop);
    }

    /// <summary>
    /// 격자의 선택을 라이브러리에 알립니다. macOS 처럼 선택은 화면이 아니라 라이브러리가 들고
    /// 있으므로, 현상의 출력 패널이 같은 선택을 보고 "내보내기 (N)" 을 냅니다.
    /// </summary>
    internal void OnSelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        if (view.isSynchronizingFrameSelection)
        {
            return;
        }
        if (view.libraryHost is { } host)
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
    }

    internal LibraryFrameSnapshot? ActionableFrame() =>
        view.FrameListView?.SelectedItem is LibraryFrameListItem item ? item.Frame : null;

    internal IReadOnlyList<LibraryFrameListItem> SelectedItems()
    {
        LibraryFrameListItem[] fromView =
            [.. view.FrameListView.SelectedItems.OfType<LibraryFrameListItem>()];
        if (fromView.Length > 0)
        {
            return fromView;
        }
        // MenuBar 클릭이 Grouped GridView 선택을 비울 수 있습니다. catalog 선택이 남으면
        // 그 사진에 메뉴 명령을 겁니다 — macOS 는 메뉴를 열어도 actionableFrame 이 유지됩니다.
        if (view.libraryHost is not { } host)
        {
            return [];
        }
        HashSet<string> ids = [.. host.SelectedFrameIds];
        if (host.ActiveFrameId is { } active)
        {
            ids.Add(active);
        }
        if (ids.Count == 0)
        {
            return [];
        }
        return [.. view.allItems.Where(item => ids.Contains(item.Id))];
    }

    /// <summary>
    /// 격자에서 한 칸 옮깁니다. 고른 것이 없으면 첫 칸부터 시작합니다 — macOS 도 그렇게 하며,
    /// 그래야 마우스를 쓰지 않고 훑기를 시작할 수 있습니다.
    /// </summary>
    internal bool Move(int offset)
    {
        IReadOnlyList<LibraryFrameListItem> order = VisibleGridItems();
        if (order.Count == 0)
        {
            return false;
        }
        string? currentId = (view.FrameListView.SelectedItem as LibraryFrameListItem)?.Id
            ?? view.libraryHost?.ActiveFrameId;
        int current = -1;
        if (currentId is not null)
        {
            for (int index = 0; index < order.Count; ++index)
            {
                if (string.Equals(order[index].Id, currentId, StringComparison.Ordinal))
                {
                    current = index;
                    break;
                }
            }
        }
        int next = current < 0
            ? (offset > 0 ? 0 : order.Count - 1)
            : Math.Clamp(current + offset, 0, order.Count - 1);
        SelectFrame(order[next].Id);
        return true;
    }

    /// <summary>
    /// 폴더/필름 묶음 GridView 는 <see cref="GridView.Items"/> 가 그룹이라 사진을 펼칩니다.
    /// macOS <c>interactionFrameIDs</c> 와 같은 훑기 순서입니다.
    /// </summary>
    private List<LibraryFrameListItem> VisibleGridItems()
    {
        List<LibraryFrameListItem> items = [];
        CollectVisible(view.FrameListView.Items, items);
        return items;
    }

    private static void CollectVisible(
        System.Collections.IEnumerable source,
        List<LibraryFrameListItem> items)
    {
        foreach (object candidate in source)
        {
            switch (candidate)
            {
                case LibraryFrameListItem item:
                    items.Add(item);
                    break;
                case IEnumerable<LibraryFrameListItem> section:
                    items.AddRange(section);
                    break;
                case Microsoft.UI.Xaml.Data.ICollectionViewGroup group:
                    CollectVisible(group.GroupItems, items);
                    break;
            }
        }
    }

    /// <summary>마지막으로 화면을 옮겨 준 사진입니다. 같은 사진이면 다시 옮기지 않습니다.</summary>
    private string? scrolledToFrameId;

    /// <summary>
    /// 공유 선택이 <b>다른 화면에서</b> 바뀌었습니다. 격자를 다시 짓지 않고 강조만 그 사진으로
    /// 옮깁니다.
    /// </summary>
    /// <remarks>
    /// macOS 는 선택이 <c>AppModel</c> 하나에 있어 라이브러리·현상·인화가 같은 값을 봅니다.
    /// WinUI 는 격자가 자기 선택을 따로 들고 있어서, 현상이나 인화에서 사진을 바꿔도
    /// <see cref="Synchronize"/> 를 부르는 <c>LibraryGridProjection.Show</c> 가 돌기 전까지
    /// 격자는 옛 사진에 강조를 남겼습니다 — 라이브러리로 돌아오면 방금 본 사진이 아니라
    /// 예전 사진이 골라져 있었습니다.
    /// </remarks>
    internal void SynchronizeFromHost() => Synchronize(VisibleGridItems());

    internal void Synchronize(IReadOnlyList<LibraryFrameListItem> visibleItems)
    {
        if (view.libraryHost is null)
        {
            return;
        }
        Dictionary<string, LibraryFrameListItem> byId = visibleItems.ToDictionary(
            item => item.Id,
            StringComparer.Ordinal);
        view.FrameListView.SelectionChanged -= view.OnFrameSelectionChanged;
        try
        {
            view.FrameListView.SelectedItems.Clear();
            foreach (string frameId in view.libraryHost.SelectedFrameIds.Where(id =>
                         !string.Equals(id, view.libraryHost.ActiveFrameId, StringComparison.Ordinal)))
            {
                if (byId.TryGetValue(frameId, out LibraryFrameListItem? item))
                {
                    view.FrameListView.SelectedItems.Add(item);
                }
            }
            if (view.libraryHost.ActiveFrameId is { } activeFrameId &&
                byId.TryGetValue(activeFrameId, out LibraryFrameListItem? active))
            {
                // 마지막에 넣은 항목이 WinUI의 active item이 되므로 multi-selection도 보존됩니다.
                view.FrameListView.SelectedItems.Add(active);
                // **고른 사진이 바뀌었을 때만 그 자리로 옮깁니다.**
                //
                // 앞 판은 격자를 다시 그릴 때마다 옮겼습니다. 폴더를 접거나 펴면 목록이 다시
                // 지어지고 선택도 다시 맞춰지는데, 그때마다 화면이 고른 사진 자리로 뛰었습니다 -
                // 사용자는 접기만 눌렀는데 보던 자리를 잃습니다. 선택이 그대로면 보던 자리도
                // 그대로여야 합니다.
                if (!string.Equals(scrolledToFrameId, activeFrameId, StringComparison.Ordinal))
                {
                    scrolledToFrameId = activeFrameId;
                    view.FrameListView.ScrollIntoView(active);
                }
            }
        }
        finally
        {
            view.FrameListView.SelectionChanged += view.OnFrameSelectionChanged;
        }
    }

    /// <summary>
    /// 격자에서 카드를 끌기 시작합니다. 담는 것은 frame id 뿐입니다 — 파일 경로를 담으면
    /// 탐색기로 끌어 놓았을 때 원본이 딸려 나갑니다.
    /// </summary>
    internal void OnDragStarting(object sender, DragItemsStartingEventArgs args)
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

    /// <summary>트리에서 frame 을 누르면 격자의 선택도 따라갑니다.</summary>
    internal void SelectFrame(string frameId)
    {
        foreach (LibraryFrameListItem item in VisibleGridItems())
        {
            if (string.Equals(item.Id, frameId, StringComparison.Ordinal))
            {
                view.FrameListView.SelectedItem = item;
                view.FrameListView.ScrollIntoView(item);
                return;
            }
        }
    }
}
