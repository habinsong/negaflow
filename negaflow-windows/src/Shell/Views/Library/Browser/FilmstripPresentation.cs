using Negaflow.Catalog;
using Negaflow.Shell.Library;

namespace Negaflow.Shell.Views;

/// <summary>
/// 하단바가 정한 범위·차례를 필름스트립 목록에 겁니다.
/// </summary>
/// <remarks>
/// macOS <c>activeDevelopInteractionScopeFrameIDs</c> 와 같은 계산입니다 — <b>범위로 먼저
/// 좁히고</b> 그 다음 정렬합니다. 기준은 지금 보고 있는 사진이며, 기준은 언제나 자기 범위
/// 안에 있으므로 범위를 좁혀도 고른 사진이 목록 밖으로 밀려나지 않습니다.
/// </remarks>
public static class FilmstripPresentation
{
    public static IReadOnlyList<LibraryFrameListItem> Project(
        LibraryHostService library,
        WorkspacePresentationState? state)
    {
        ArgumentNullException.ThrowIfNull(library);
        IReadOnlyList<LibraryFrameSnapshot> frames = library.Frames;
        if (state?.Current is not { } preferences)
        {
            return LibraryFrameListItems.From(frames);
        }

        LibraryFrameSnapshot? reference = library.ActiveFrameId is { Length: > 0 } activeId
            ? frames.FirstOrDefault(frame =>
                string.Equals(frame.Id, activeId, StringComparison.Ordinal))
            : null;
        IReadOnlyList<LibraryFrameSnapshot> scoped = FilmstripScopes.Filtered(
            preferences.FilmstripScope,
            frames,
            reference);
        return LibrarySorter.Sort(
            LibraryFrameListItems.From(scoped),
            preferences.FilmstripSortKey,
            preferences.FilmstripSortAscending);
    }
}
