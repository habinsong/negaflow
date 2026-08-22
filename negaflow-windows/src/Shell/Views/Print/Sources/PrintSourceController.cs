using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell;
using Negaflow.Shell.Library;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Library.Browser;
using Negaflow.Shell.Views;

namespace Negaflow.Shell.Views.Print.Sources;

/// <summary>
/// 인화 화면의 파일 트리·필름스트립·선택입니다. 미리보기 그리기와 다른 이유로 바뀝니다.
/// </summary>
internal sealed class PrintSourceController
{
    private readonly PrintSourceSurface surface;
    private readonly Action redraw;
    private int builtFrameCount;
    private IReadOnlyList<LibraryFrameListItem> filmstripItems = [];
    private LibraryHostService? libraryHost;
    private ThumbnailService? thumbnails;

    internal PrintSourceController(PrintSourceSurface surface, Action redraw)
    {
        this.surface = surface;
        this.redraw = redraw;
    }

    internal ThumbnailService? Thumbnails => thumbnails;

    /// <summary>
    /// 인화할 사진들입니다. 라이브러리에서 고른 것을 그대로 씁니다 — macOS 도 같은 선택을
    /// 봅니다.
    /// </summary>
    internal IReadOnlyList<LibraryFrameSnapshot> Sources =>
        libraryHost?.SelectedFrames is { Count: > 0 } selected
            ? selected
            : libraryHost?.Frames is { Count: > 0 } all
                ? [all[0]]
                : [];

    /// <summary>
    /// 썸네일이 도착하면 판을 다시 그립니다. 인화 화면은 라이브러리와 같은 캐시를 봅니다 —
    /// 같은 사진을 두 번 만들 이유가 없습니다.
    /// </summary>
    internal void AttachThumbnails(ThumbnailService service)
    {
        ArgumentNullException.ThrowIfNull(service);
        if (thumbnails is not null)
        {
            thumbnails.ThumbnailReady -= OnThumbnailReady;
        }
        thumbnails = service;
        thumbnails.ThumbnailReady += OnThumbnailReady;
    }

    internal void ShowLibrary(LibraryHostService host)
    {
        ArgumentNullException.ThrowIfNull(host);
        libraryHost = host;
        host.SelectionChanged += OnSelectionChanged;
        // 고른 사진의 썸네일이 아직 없을 수 있습니다. 미리보기가 그림 없이 시작하지 않도록
        // 여기서 한 번 청합니다.
        foreach (LibraryFrameSnapshot frame in Sources)
        {
            thumbnails?.Request(frame);
        }
        RebuildFilesTree();
        SynchronizeFilmstrip();
        SynchronizeSidebar();
        redraw();
    }

    internal void HandleTreeInvoked(object? sender, string frameId)
    {
        _ = sender;
        libraryHost?.SetSelection([frameId], frameId);
    }

    internal void HandleFilmstripSelected(object? sender, LibraryFrameListItem item)
    {
        _ = sender;
        libraryHost?.SetSelection([item.Id], item.Id);
    }

    private void OnThumbnailReady(string frameId)
    {
        if (thumbnails?.TryGet(frameId) is { } jpeg)
        {
            LibraryFrameListItem? item = filmstripItems.FirstOrDefault(candidate =>
                string.Equals(candidate.Id, frameId, StringComparison.Ordinal));
            if (item is not null)
            {
                item.Thumbnail = LibraryWorkspaceView.DecodeThumbnail(jpeg);
            }
        }
        redraw();
    }

    private void OnSelectionChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        SynchronizeFilmstrip();
        if (builtFrameCount != (libraryHost?.Frames.Count ?? 0))
        {
            RebuildFilesTree();
        }
        SynchronizeSidebar();
        redraw();
    }

    /// <summary>
    /// macOS PrintWorkspaceSidebar의 Files 탭과 같은 폴더/사진 트리입니다. Library와 같은
    /// 투영을 사용해 인화 화면만 별도의 파일 목록을 갖지 않게 합니다.
    /// </summary>
    private void RebuildFilesTree()
    {
        builtFrameCount = 0;
        if (libraryHost is null)
        {
            surface.FilesTree.SetSections([]);
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
        surface.FilesTree.SetSections(projection.FolderSections);
        builtFrameCount = projection.FolderSections.Sum(section => section.Items.Count);
    }

    private void SynchronizeSidebar()
    {
        string? activeFrameId = libraryHost?.ActiveFrameId;
        LibraryFrameSnapshot? activeFrame = activeFrameId is null
            ? null
            : libraryHost?.Frames.FirstOrDefault(frame =>
                string.Equals(frame.Id, activeFrameId, StringComparison.Ordinal));
        string title = activeFrame is null
            ? AppResources.Get("noFrame", "Text")
            : LibraryFrameNaming.DisplayName(activeFrame);
        surface.LeftHeader.Text = title;
        surface.RightHeader.Text = title;
        ToolTipService.SetToolTip(surface.LeftHeader, title);
        ToolTipService.SetToolTip(surface.RightHeader, title);

        surface.ApplySourcePane(libraryHost?.Frames.Count > 0);
        surface.FilesTree.SelectedFrameId = activeFrameId;
    }

    private void SynchronizeFilmstrip()
    {
        if (libraryHost is null)
        {
            surface.Filmstrip.ShowFrames([], -1);
            filmstripItems = [];
            return;
        }
        filmstripItems = LibraryFrameListItems.From(
            libraryHost.Frames,
            libraryHost.SourceAvailabilityByFrameId);
        int selectedIndex = 0;
        if (libraryHost.ActiveFrameId is { } activeFrameId)
        {
            int found = filmstripItems
                .Select((item, index) => (item, index))
                .FirstOrDefault(entry => string.Equals(
                    entry.item.Id,
                    activeFrameId,
                    StringComparison.Ordinal)).index;
            selectedIndex = found;
        }
        _ = LibraryThumbnailBinder.Hydrate(thumbnails, filmstripItems, "print");
        surface.Filmstrip.ShowFrames(filmstripItems, selectedIndex);
    }
}
