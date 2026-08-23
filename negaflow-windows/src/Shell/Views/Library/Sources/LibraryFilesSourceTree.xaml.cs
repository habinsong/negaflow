using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Library.Sources;

/// <summary>
/// 파일 소스 목록입니다. 격자와 같은 투영을 쓰므로 필터·검색이 걸리면 목록도 함께 줄어듭니다.
/// </summary>
public sealed partial class LibraryFilesSourceTree : UserControl
{
    internal LibraryHostService? libraryHost;
    internal readonly LibraryFilesSourceDrop drop;

    /// <summary>
    /// 로그에 붙는 이름입니다. 라이브러리 · 현상 · 인화가 <b>같은 컨트롤</b>을 쓰므로 어느
    /// 화면의 목록인지 이름 없이는 구별할 수 없습니다.
    /// </summary>
    public string TraceName
    {
        get => FilesTree.TraceName;
        set => FilesTree.TraceName = value;
    }

    public LibraryFilesSourceTree()
    {
        InitializeComponent();
        drop = new LibraryFilesSourceDrop(this);
        FilesTree.ShowsRemoveButton = true;
        FilesTree.FrameInvoked += (_, frameId) => FrameSelected?.Invoke(this, frameId);
        FilesTree.FolderRemoveRequested += OnFolderRemoveRequested;
        FilesTree.FolderContextRequested += OnFolderContextRequested;
        FilesTree.FolderDragOver = drop.OnDragOver;
        FilesTree.FolderDrop = drop.OnDrop;
    }

    /// <summary>
    /// 접기 상태를 셸 설정에 묶습니다. 세 화면이 같은 목록을 보므로 한 벌만 씁니다.
    /// </summary>
    public void AttachPresentation(WorkspacePresentationState state) =>
        LibraryFolderTreeBinding.Attach(FilesTree, state);

    /// <summary>목록에서 사진을 눌렀습니다. 현상·인화가 쓰던 이름과 같습니다.</summary>
    public event EventHandler<string>? FrameInvoked
    {
        add => FilesTree.FrameInvoked += value;
        remove => FilesTree.FrameInvoked -= value;
    }

    /// <summary>지금 열려 있는 사진입니다. 이 사진과 그 폴더가 파랗게 됩니다.</summary>
    public string? SelectedFrameId
    {
        get => FilesTree.SelectedFrameId;
        set => FilesTree.SelectedFrameId = value;
    }

    /// <summary>목록을 갈아 끼웁니다.</summary>
    public void SetSections(IReadOnlyList<LibraryBrowserFolderSection> value)
    {
        ArgumentNullException.ThrowIfNull(value);
        PreviewTrace.Write(
            $"files.set {TraceName} folders={value.Count} " +
            $"frames={value.Sum(section => section.Items.Count)}");
        FilesTree.SetSections(value);
    }

    /// <summary>목록에서 사진을 골랐을 때 격자 선택을 맞춥니다.</summary>
    public event EventHandler<string>? FrameSelected;

    /// <summary>원본을 옮긴 뒤 격자를 다시 그릴 때 올립니다.</summary>
    public event EventHandler? LibraryChanged;

    /// <summary>옮기기 실패 문구입니다. 성공이면 빈 문자열입니다.</summary>
    public event EventHandler<string>? StatusChanged;

    /// <summary>
    /// macOS <c>LibraryFolderTreeView</c> 의 "누락 폴더 찾기" 입니다. 폴더 경로를 실어 올립니다.
    /// </summary>
    public event EventHandler<string>? LocateFolderRequested;

    /// <summary>macOS <c>removeLibraryFolderSection</c> — 머리줄의 ✕ 입니다.</summary>
    public event EventHandler<string>? FolderRemoveRequested;

    public void Bind(LibraryHostService host)
    {
        ArgumentNullException.ThrowIfNull(host);
        libraryHost = host;
        PreviewTrace.Write(
            $"files.bind {TraceName} frames={host.Frames.Count} folders={host.Folders.Count}");
    }

    /// <summary>
    /// 사진을 담고 있는 폴더와 그 사진들을 다시 만듭니다. 맞은 장수를 돌려줍니다.
    /// </summary>
    public int Rebuild(
        IReadOnlyList<LibraryFrameListItem> allItems,
        string searchText,
        LibraryQuickFilterState filters)
    {
        if (libraryHost is null)
        {
            PreviewTrace.Write($"files.rebuild {TraceName} host=null");
            FilesTree.SetSections([]);
            return 0;
        }
        LibraryBrowserProjection projection = LibraryBrowserProjector.Create(
            filters.Apply(LibraryFrameListItems.Filter(allItems, searchText)),
            libraryHost.Folders,
            libraryHost.FolderAvailabilityById,
            LibraryBrowserViewMode.Folders,
            includeEmptyFolders: false);
        FilesTree.SelectedFrameId = libraryHost.ActiveFrameId;
        PreviewTrace.Write(
            $"files.rebuild {TraceName} host=ok items={allItems.Count} " +
            $"folders={projection.FolderSections.Count} matched={projection.MatchedCount}");
        FilesTree.SetSections(projection.FolderSections);
        return projection.MatchedCount;
    }

    internal void RaiseStatus(string text) => StatusChanged?.Invoke(this, text);

    internal void RaiseLibraryChanged() => LibraryChanged?.Invoke(this, EventArgs.Empty);

    private void OnFolderRemoveRequested(object? sender, string folderPath)
    {
        _ = sender;
        FolderRemoveRequested?.Invoke(this, folderPath);
    }

    /// <summary>
    /// macOS 는 이 메뉴를 <b>폴더가 실제로 사라졌을 때만</b> 냅니다
    /// (<c>if let folder = section.folder, !isFolderAvailable</c>). 멀쩡한 폴더에까지 띄우면
    /// 누를 일이 없는 항목이 늘 붙어 있게 됩니다.
    /// </summary>
    private void OnFolderContextRequested(object? sender, LibraryFolderContextRequest request)
    {
        _ = sender;
        if (request.Section is not { IsRegistered: true, IsAvailable: false })
        {
            return;
        }
        MenuFlyoutItem locate = new()
        {
            Text = AppResources.Get("libraryLocateFolder", "Content"),
        };
        locate.Click += (_, _) => LocateFolderRequested?.Invoke(this, request.Section.Id);
        MenuFlyout flyout = new();
        flyout.Items.Add(locate);
        flyout.ShowAt(
            request.Anchor,
            new FlyoutShowOptions { Position = request.Args.GetPosition(request.Anchor) });
    }
}
