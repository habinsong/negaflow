using Microsoft.UI.Xaml.Controls;

namespace Negaflow.Shell.Views.Develop.Sources;

/// <summary>
/// 라이브러리와 같은 폴더 목록입니다. 같은 투영을 쓰므로 두 화면이 서로 다른 폴더 목록을
/// 보여 주지 않습니다.
/// </summary>
public sealed partial class DevelopFilesSourcePanel : UserControl
{
    private LibraryHostService? libraryHost;

    public DevelopFilesSourcePanel()
    {
        InitializeComponent();
        FilesTree.FrameInvoked += (_, frameId) => FrameSelected?.Invoke(this, frameId);
    }

    /// <summary>목록에서 frame 을 누르면 올립니다. 선택은 뷰가 맡습니다.</summary>
    public event EventHandler<string>? FrameSelected;

    public void Bind(LibraryHostService host)
    {
        ArgumentNullException.ThrowIfNull(host);
        libraryHost = host;
    }

    public void Rebuild()
    {
        if (libraryHost is null)
        {
            FilesTree.SetSections([]);
            return;
        }
        LibraryBrowserProjection projection = LibraryBrowserProjector.Create(
            LibraryFrameListItems.From(
                libraryHost.Frames,
                libraryHost.SourceAvailabilityByFrameId),
            libraryHost.Folders,
            libraryHost.FolderAvailabilityById,
            LibraryBrowserViewMode.Folders,
            includeEmptyFolders: false);
        FilesTree.SelectedFrameId = libraryHost.ActiveFrameId;
        FilesTree.SetSections(projection.FolderSections);
    }
}
