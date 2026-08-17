using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Library.Sources;

/// <summary>
/// 파일 소스 트리입니다. 격자와 같은 투영을 쓰므로 필터·검색이 걸리면 트리도 함께 줄어듭니다.
/// </summary>
public sealed partial class LibraryFilesSourceTree : UserControl
{
    internal LibraryHostService? libraryHost;
    internal readonly LibraryFilesSourceDrop drop;

    public LibraryFilesSourceTree()
    {
        InitializeComponent();
        drop = new LibraryFilesSourceDrop(this);
    }

    /// <summary>트리에서 사진을 골랐을 때 격자 선택을 맞춥니다.</summary>
    public event EventHandler<string>? FrameSelected;

    /// <summary>원본을 옮긴 뒤 격자를 다시 그릴 때 올립니다.</summary>
    public event EventHandler? LibraryChanged;

    /// <summary>옮기기 실패 문구입니다. 성공이면 빈 문자열입니다.</summary>
    public event EventHandler<string>? StatusChanged;

    public void Bind(LibraryHostService host)
    {
        ArgumentNullException.ThrowIfNull(host);
        libraryHost = host;
    }

    /// <summary>
    /// 폴더와 그 안의 frame 을 트리로 다시 만듭니다. 맞은 장수를 돌려줍니다.
    /// </summary>
    public int Rebuild(
        IReadOnlyList<LibraryFrameListItem> allItems,
        string searchText,
        LibraryQuickFilterState filters)
    {
        FilesTree.RootNodes.Clear();
        if (libraryHost is null)
        {
            return 0;
        }
        LibraryBrowserProjection projection = LibraryBrowserProjector.Create(
            filters.Apply(LibraryFrameListItems.Filter(allItems, searchText)),
            libraryHost.Folders,
            libraryHost.FolderAvailabilityById,
            LibraryBrowserViewMode.Folders);
        foreach (LibraryBrowserFolderSection section in projection.FolderSections)
        {
            var folder = new TreeViewNode
            {
                Content = LibrarySourceNode.Folder(
                    section.Title,
                    AppResources.FormatIntegers("libraryFolderFrameCount", "Text", section.Count),
                    section.Id),
            };
            foreach (LibraryFrameListItem item in section.Items)
            {
                folder.Children.Add(new TreeViewNode
                {
                    Content = LibrarySourceNode.Frame(item.DisplayName, item.Id),
                });
            }
            FilesTree.RootNodes.Add(folder);
        }
        return projection.MatchedCount;
    }

    internal void RaiseStatus(string text) => StatusChanged?.Invoke(this, text);

    internal void RaiseLibraryChanged() => LibraryChanged?.Invoke(this, EventArgs.Empty);

    private void OnSourceTreeItemInvoked(TreeView sender, TreeViewItemInvokedEventArgs args)
    {
        _ = sender;
        if (args.InvokedItem is TreeViewNode { Content: LibrarySourceNode { FrameId: { } frameId } })
        {
            FrameSelected?.Invoke(this, frameId);
        }
    }

    private void OnFolderDragOver(object sender, DragEventArgs args) => drop.OnDragOver(sender, args);

    private void OnFolderDrop(object sender, DragEventArgs args) => drop.OnDrop(sender, args);
}
