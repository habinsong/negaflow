using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>
/// 필름스트립에 무엇까지 보일지입니다. macOS <c>FilmstripScope</c> 와 같은 넷입니다.
/// </summary>
public enum FilmstripScope
{
    All,
    Folder,
    Process,
    Target,
}

/// <summary>
/// 지금 보고 있는 사진을 기준으로 필름스트립을 좁힙니다.
/// </summary>
/// <remarks>
/// 기준 사진은 언제나 자기 범위에 들어가므로, 범위를 좁혀도 지금 고른 사진이 목록 밖으로
/// 밀려나지 않습니다 — macOS 주석과 같은 이유입니다.
/// </remarks>
public static class FilmstripScopes
{
    public static IReadOnlyList<FilmstripScope> All { get; } =
    [
        FilmstripScope.All,
        FilmstripScope.Folder,
        FilmstripScope.Process,
        FilmstripScope.Target,
    ];

    /// <summary>범위 이름의 리소스 키입니다.</summary>
    public static string ResourceKey(FilmstripScope scope) => scope switch
    {
        FilmstripScope.All => "libraryAllShort",
        FilmstripScope.Folder => "filmstripScopeFolder",
        FilmstripScope.Process => "process",
        FilmstripScope.Target => "target",
        _ => "filmstripScopeFolder",
    };

    public static IReadOnlyList<LibraryFrameSnapshot> Filtered(
        FilmstripScope scope,
        IReadOnlyList<LibraryFrameSnapshot> frames,
        LibraryFrameSnapshot? reference)
    {
        ArgumentNullException.ThrowIfNull(frames);
        if (reference is null || scope == FilmstripScope.All)
        {
            return frames;
        }
        return scope switch
        {
            FilmstripScope.Folder => [.. frames.Where(frame =>
                string.Equals(FolderPath(frame), FolderPath(reference), StringComparison.OrdinalIgnoreCase))],
            // macOS `DevelopmentProcess(filmType:isDigitalSource:)` 와 같은 짝입니다.
            FilmstripScope.Process => [.. frames.Where(frame =>
                frame.Route.FilmType == reference.Route.FilmType &&
                frame.Route.IsDigitalSource == reference.Route.IsDigitalSource)],
            FilmstripScope.Target => [.. frames.Where(frame =>
                frame.DevelopTarget == reference.DevelopTarget)],
            _ => frames,
        };
    }

    /// <summary>
    /// 기준 사진이 목록에 없을 때 고를 자리입니다. macOS
    /// <c>selectMostRecentAvailableFrameIfNeeded()</c> 와 같은 규칙 — <b>가장 최근에 찍힌</b>
    /// 사진이며, 같은 시각이면 뒤에 있는 것입니다.
    /// </summary>
    /// <remarks>
    /// 앞 판은 첫 항목(<c>0</c>)을 골랐습니다. 그래서 스캔이나 가져오기 직후 기준이 잠시
    /// 목록 밖으로 나가면 현상뷰가 방금 넣은 사진이 아니라 <b>맨 첫 장</b>으로 튀었고,
    /// 무엇으로 튀는지가 넣은 차례와 정렬에 따라 달라졌습니다(사용자 보고 2026-09-04).
    ///
    /// 프리뷰 스캔은 macOS 처럼 뺍니다. 그것뿐이면 그때만 프리뷰까지 넣어 같은 규칙으로
    /// 고릅니다 — 어느 경우에도 "첫 장" 으로 접지 않습니다. 원본 존재 여부는 필름스트립
    /// 항목이 들고 있지 않으므로 여기서는 보지 않습니다.
    /// </remarks>
    public static int MostRecentIndex(IReadOnlyList<LibraryFrameListItem> items)
    {
        ArgumentNullException.ThrowIfNull(items);
        int best = MostRecentIndex(items, skipPreviewScans: true);
        return best >= 0 ? best : MostRecentIndex(items, skipPreviewScans: false);
    }

    private static int MostRecentIndex(
        IReadOnlyList<LibraryFrameListItem> items,
        bool skipPreviewScans)
    {
        int best = -1;
        DateTimeOffset bestScannedAt = DateTimeOffset.MinValue;
        for (int index = 0; index < items.Count; ++index)
        {
            LibraryFrameSnapshot frame = items[index].Frame;
            if (skipPreviewScans && frame.IsPreviewScan)
            {
                continue;
            }
            DateTimeOffset scannedAt = frame.ScannedAt ?? DateTimeOffset.MinValue;
            if (best < 0 || scannedAt >= bestScannedAt)
            {
                best = index;
                bestScannedAt = scannedAt;
            }
        }
        return best;
    }

    private static string FolderPath(LibraryFrameSnapshot frame)
    {
        try
        {
            return Path.GetDirectoryName(frame.SourcePath) ?? string.Empty;
        }
        catch (Exception error) when (error is ArgumentException or PathTooLongException)
        {
            return string.Empty;
        }
    }
}
