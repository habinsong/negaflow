using Negaflow.Catalog;

namespace Negaflow.Shell;

internal sealed class LibrarySelectionState
{
    private readonly Action changed;

    internal LibrarySelectionState(Action changed)
    {
        ArgumentNullException.ThrowIfNull(changed);
        this.changed = changed;
    }

    internal IReadOnlyList<string> SelectedFrameIds { get; private set; } = [];

    internal string? ActiveFrameId { get; private set; }

    /// <summary>
    /// Shift 로 이어 고를 때의 기준점입니다. macOS <c>frameSelectionAnchorID</c> 자리입니다.
    /// </summary>
    internal string? AnchorFrameId { get; private set; }

    /// <summary>
    /// 누른 칸과 글쇠로 선택을 바꿉니다. macOS
    /// <c>selectFrame(_:orderedFrameIDs:modifiers:)</c> 와 같은 규칙입니다.
    /// </summary>
    internal void SelectFrame(
        IReadOnlyList<LibraryFrameSnapshot> frames,
        string frameId,
        IReadOnlyList<string> orderedFrameIds,
        LibrarySelectionModifiers modifiers)
    {
        ArgumentNullException.ThrowIfNull(frames);
        LibraryFrameSelectionCommand next = LibraryFrameSelectionCommand.Apply(
            frameId,
            orderedFrameIds,
            SelectedFrameIds,
            ActiveFrameId,
            AnchorFrameId,
            modifiers);
        AnchorFrameId = next.AnchorFrameId;
        Set(frames, next.SelectedFrameIds, next.ActiveFrameId);
    }

    internal void Set(
        IReadOnlyList<LibraryFrameSnapshot> frames,
        IEnumerable<string> frameIds,
        string? activeFrameId)
    {
        ArgumentNullException.ThrowIfNull(frames);
        ArgumentNullException.ThrowIfNull(frameIds);
        var known = new HashSet<string>(frames.Select(frame => frame.Id), StringComparer.Ordinal);
        var seen = new HashSet<string>(StringComparer.Ordinal);
        string[] next = [.. frameIds.Where(id => known.Contains(id) && seen.Add(id))];
        string? nextActive = activeFrameId is not null && next.Contains(activeFrameId, StringComparer.Ordinal)
            ? activeFrameId
            : ActiveFrameId is not null && next.Contains(ActiveFrameId, StringComparer.Ordinal)
                ? ActiveFrameId
                : next.FirstOrDefault();
        if (next.SequenceEqual(SelectedFrameIds, StringComparer.Ordinal) &&
            string.Equals(nextActive, ActiveFrameId, StringComparison.Ordinal))
        {
            return;
        }

        SelectedFrameIds = next;
        ActiveFrameId = nextActive;
        changed();
    }

    internal string? RestoreActiveFrame(
        IReadOnlyList<LibraryFrameSnapshot> frames,
        string? savedFrameId,
        Func<string, bool> isAvailable)
    {
        string? candidate = frames.FirstOrDefault(frame =>
                string.Equals(frame.Id, savedFrameId, StringComparison.Ordinal) &&
                isAvailable(frame.Id))?.Id
            ?? MostRecentAvailableFrameId(frames, isAvailable);
        Set(frames, candidate is null ? [] : [candidate], candidate);
        return candidate;
    }

    internal string? ReconcileActiveFrameAvailability(
        IReadOnlyList<LibraryFrameSnapshot> frames,
        Func<string, bool> isAvailable)
    {
        if (ActiveFrameId is { } activeFrameId && isAvailable(activeFrameId))
        {
            return activeFrameId;
        }

        string? candidate = SelectedFrameIds.FirstOrDefault(isAvailable)
            ?? MostRecentAvailableFrameId(frames, isAvailable);
        Set(frames, candidate is null ? [] : [candidate], candidate);
        return candidate;
    }

    internal IReadOnlyList<LibraryFrameSnapshot> SelectedFrames(
        IReadOnlyList<LibraryFrameSnapshot> frames)
    {
        if (SelectedFrameIds.Count == 0)
        {
            return [];
        }

        var byId = frames.ToDictionary(frame => frame.Id, StringComparer.Ordinal);
        return [.. SelectedFrameIds
            .Select(id => byId.TryGetValue(id, out LibraryFrameSnapshot? frame) ? frame : null)
            .OfType<LibraryFrameSnapshot>()];
    }

    private static string? MostRecentAvailableFrameId(
        IReadOnlyList<LibraryFrameSnapshot> frames,
        Func<string, bool> isAvailable) => frames
        .Select((frame, index) => (frame, index))
        .Where(entry => isAvailable(entry.frame.Id))
        .OrderBy(entry => entry.frame.ScannedAt ?? DateTimeOffset.MinValue)
        .ThenBy(entry => entry.index)
        .LastOrDefault().frame?.Id;
}
