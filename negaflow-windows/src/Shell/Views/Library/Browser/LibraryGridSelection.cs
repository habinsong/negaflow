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
        view.DevelopDefaultsPanel.Synchronize();
    }

    internal LibraryFrameSnapshot? ActionableFrame() =>
        view.FrameListView?.SelectedItem is LibraryFrameListItem item ? item.Frame : null;

    internal IReadOnlyList<LibraryFrameListItem> SelectedItems() =>
        [.. view.FrameListView.SelectedItems.OfType<LibraryFrameListItem>()];

    /// <summary>
    /// 격자에서 한 칸 옮깁니다. 고른 것이 없으면 첫 칸부터 시작합니다 — macOS 도 그렇게 하며,
    /// 그래야 마우스를 쓰지 않고 훑기를 시작할 수 있습니다.
    /// </summary>
    internal bool Move(int offset)
    {
        if (view.FrameListView.Items.Count == 0)
        {
            return false;
        }
        int current = view.FrameListView.SelectedIndex;
        int next = current < 0
            ? (offset > 0 ? 0 : view.FrameListView.Items.Count - 1)
            : Math.Clamp(current + offset, 0, view.FrameListView.Items.Count - 1);
        view.FrameListView.SelectedIndex = next;
        view.FrameListView.ScrollIntoView(view.FrameListView.Items[next]);
        return true;
    }

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
                view.FrameListView.ScrollIntoView(active);
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
        foreach (object candidate in view.FrameListView.Items)
        {
            if (candidate is LibraryFrameListItem item &&
                string.Equals(item.Id, frameId, StringComparison.Ordinal))
            {
                view.FrameListView.SelectedItem = item;
                view.FrameListView.ScrollIntoView(item);
                return;
            }
        }
    }
}
