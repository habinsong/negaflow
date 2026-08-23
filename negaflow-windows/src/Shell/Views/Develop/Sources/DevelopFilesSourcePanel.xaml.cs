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
        FilesPanel.TraceName = "develop";
        FilesPanel.FrameInvoked += (_, frameId) => FrameSelected?.Invoke(this, frameId);
    }

    /// <summary>
    /// 접기 상태를 셸 설정에 묶습니다. 라이브러리 · 인화와 같은 한 벌입니다.
    /// </summary>
    public void AttachPresentation(WorkspacePresentationState state) =>
        FilesPanel.AttachPresentation(state);

    /// <summary>공통 "파일" 탭입니다. 셸이 ✕ 와 맥락 메뉴를 라이브러리로 잇습니다.</summary>
    internal Negaflow.Shell.Views.Library.Sources.LibraryFilesSourceTree FilesTab => FilesPanel;

    /// <summary>목록에서 frame 을 누르면 올립니다. 선택은 뷰가 맡습니다.</summary>
    public event EventHandler<string>? FrameSelected;

    /// <summary>고른 사진만 바꿉니다. 목록을 다시 짓지 않습니다.</summary>
    public void SynchronizeSelection(string? frameId) => FilesPanel.SelectedFrameId = frameId;

    public void Bind(LibraryHostService host)
    {
        ArgumentNullException.ThrowIfNull(host);
        libraryHost = host;
    }

    public void Rebuild()
    {
        if (libraryHost is null)
        {
            Negaflow.Shell.PreviewTrace.Write("files.develop.rebuild host=null");
            FilesPanel.SetSections([]);
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
        Negaflow.Shell.PreviewTrace.Write(
            $"files.develop.rebuild host=ok frames={libraryHost.Frames.Count} " +
            $"folders={libraryHost.Folders.Count} sections={projection.FolderSections.Count}");
        FilesPanel.SelectedFrameId = libraryHost.ActiveFrameId;
        FilesPanel.SetSections(projection.FolderSections);
    }
}
