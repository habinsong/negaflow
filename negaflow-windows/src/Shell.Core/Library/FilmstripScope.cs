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
