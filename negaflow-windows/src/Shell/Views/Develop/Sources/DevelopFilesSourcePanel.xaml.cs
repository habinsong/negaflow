using Microsoft.UI.Xaml.Controls;

namespace Negaflow.Shell.Views.Develop.Sources;

/// <summary>
/// 라이브러리와 같은 폴더 트리입니다. 같은 투영을 쓰므로 두 화면이 서로 다른 폴더 목록을
/// 보여 주지 않습니다.
/// </summary>
public sealed partial class DevelopFilesSourcePanel : UserControl
{
    private LibraryHostService? libraryHost;

    public DevelopFilesSourcePanel() => InitializeComponent();

    /// <summary>트리에서 frame 을 누르면 올립니다. 선택은 뷰가 맡습니다.</summary>
    public event EventHandler<string>? FrameSelected;

    public void Bind(LibraryHostService host)
    {
        ArgumentNullException.ThrowIfNull(host);
        libraryHost = host;
    }

    public void Rebuild()
    {
        FilesTree.RootNodes.Clear();
        if (libraryHost is null)
        {
            return;
        }
        LibraryBrowserProjection projection = LibraryBrowserProjector.Create(
            LibraryFrameListItems.From(
                libraryHost.Frames,
                libraryHost.SourceAvailabilityByFrameId),
            libraryHost.Folders,
            libraryHost.FolderAvailabilityById,
            LibraryBrowserViewMode.Folders);
        DevelopSourceFolderTree.AddFolderNodes(FilesTree, projection.FolderSections);
    }

    private void OnFilesTreeItemInvoked(TreeView sender, TreeViewItemInvokedEventArgs args)
    {
        _ = sender;
        if (DevelopSourceFolderTree.TryGetFrameId(args, out string frameId))
        {
            FrameSelected?.Invoke(this, frameId);
        }
    }
}
