using Negaflow.Catalog;

namespace Negaflow.Shell.Print;

public static class PrintSourceSelection
{
    public static IReadOnlyList<LibraryFrameSnapshot> Eligible(
        IReadOnlyList<LibraryFrameSnapshot> frames)
    {
        ArgumentNullException.ThrowIfNull(frames);
        return [.. frames.Where(frame => !frame.IsPreviewScan)];
    }

    public static IReadOnlyList<LibraryFrameSnapshot> Resolve(
        IReadOnlyList<LibraryFrameSnapshot> selected,
        IReadOnlyList<LibraryFrameSnapshot> all)
    {
        ArgumentNullException.ThrowIfNull(selected);
        ArgumentNullException.ThrowIfNull(all);
        LibraryFrameSnapshot[] selectedEligible = [..
            selected.Where(frame => !frame.IsPreviewScan)];
        if (selectedEligible.Length > 0)
        {
            return selectedEligible;
        }
        LibraryFrameSnapshot? first = all.FirstOrDefault(frame => !frame.IsPreviewScan);
        return first is null ? [] : [first];
    }

    public static string? ActiveFrameId(
        string? requestedId,
        IReadOnlyList<LibraryFrameSnapshot> sources)
    {
        ArgumentNullException.ThrowIfNull(sources);
        return sources.FirstOrDefault(frame => string.Equals(
                frame.Id,
                requestedId,
                StringComparison.Ordinal))?.Id ??
            sources.FirstOrDefault()?.Id;
    }
}
