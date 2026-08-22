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

    /// <summary>
    /// 필름스트립에서 사진을 눌렀습니다. Shift · Ctrl 을 함께 눌렀으면 여러 장이 남고, 그
    /// 여러 장이 그대로 인화할 사진이 됩니다 — macOS 도 같은 선택 하나를 봅니다.
    /// </summary>
    internal void HandleFilmstripSelected(object? sender, LibraryFrameListItem item)
    {
        _ = sender;
        libraryHost?.SelectFrame(
            item.Id,
            [.. filmstripItems.Select(candidate => candidate.Id)],
            LibraryModifierKeys.Current());
    }

    /// <summary>
    /// 썸네일이나 현상본이 새로 왔습니다. 판이 들고 있던 풀어 둔 그림을 버려야 새 그림이
    /// 보입니다 — 그때 말고는 버리지 않습니다(끌 때마다 다시 풀면 느려집니다).
    /// </summary>
    internal event EventHandler? PreviewImageArrived;

    /// <summary>사진마다 마지막으로 판을 다시 그린 때입니다.</summary>
    private readonly Dictionary<string, long> lastRedrawTicks = [];

    /// <summary>
    /// 같은 사진 때문에 판을 다시 그리는 최소 간격입니다.
    /// </summary>
    /// <remarks>
    /// 판을 그릴 때 현상본이 없으면 다시 현상을 청합니다. 그 현상이 끝나면 다시 이 알림이
    /// 오고, 그 알림이 또 판을 그립니다 — 실측 <b>초당 94회</b>가 돌아 UI 스레드가 화면을
    /// 합성하지 못하고 창이 검게 멈췄습니다. 같은 사진의 알림은 이 간격 안에서 한 번만
    /// 받아 고리를 끊습니다. 새 그림은 다음 알림에 반영되므로 잃는 것은 없습니다.
    /// </remarks>
    private const long RedrawIntervalTicks = TimeSpan.TicksPerMillisecond * 250;

    private void OnThumbnailReady(string frameId)
    {
        long now = Environment.TickCount64 * TimeSpan.TicksPerMillisecond;
        if (lastRedrawTicks.TryGetValue(frameId, out long last) &&
            now - last < RedrawIntervalTicks)
        {
            return;
        }
        lastRedrawTicks[frameId] = now;
        Negaflow.Shell.PreviewTrace.Write("print.thumb " + frameId);
        PreviewImageArrived?.Invoke(this, EventArgs.Empty);
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
        Negaflow.Shell.PreviewTrace.Write("print.selection");
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

    /// <summary>
    /// 언어가 바뀌면 사이드바 머리글("사진 없음")과 필름스트립 항목 이름을 다시 만듭니다.
    /// 둘 다 만들 때 문구가 정해지므로 다시 만들지 않으면 옛 언어로 남습니다.
    /// </summary>
    internal void Localize()
    {
        RebuildFilesTree();
        SynchronizeFilmstrip();
        SynchronizeSidebar();
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
        // 하단바가 정한 범위와 차례를 씁니다 - 현상뷰와 같은 하나입니다.
        filmstripItems = FilmstripPresentation.Project(libraryHost, surface.Presentation());
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
        // 고른 사진이 여러 장이면 스트립도 여러 장을 밝게 냅니다.
        surface.Filmstrip.SynchronizeSelection(
            libraryHost.SelectedFrameIds,
            libraryHost.ActiveFrameId);
    }
}
