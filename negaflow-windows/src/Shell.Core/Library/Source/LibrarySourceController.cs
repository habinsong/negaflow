using Negaflow.Catalog;

namespace Negaflow.Shell;

internal sealed class LibrarySourceController
{
    private readonly Func<string, LibrarySourceMetadata?> sourceMetadataReader;

    internal LibrarySourceController(Func<string, LibrarySourceMetadata?> sourceMetadataReader)
    {
        ArgumentNullException.ThrowIfNull(sourceMetadataReader);
        this.sourceMetadataReader = sourceMetadataReader;
    }

    internal SourceMoveOutcome Move(
        LibraryDocument? document,
        IReadOnlyList<LibraryFrameSnapshot> frames,
        string destinationFolder)
    {
        ArgumentNullException.ThrowIfNull(frames);
        SourceMovePlanResult planned = SourceMovePlanner.Files(
            [.. frames.Select(frame => new SourceMovePair(frame.SourcePath, frame.InfraredPath))],
            destinationFolder);
        if (planned.Plan is not { } plan)
        {
            return planned.Error == SourceMovePlanError.Collision
                ? SourceMoveOutcome.Collision
                : SourceMoveOutcome.SourceMissing;
        }

        SourceMoveResult moved = SourceMoveTransaction.Move(plan.FileMoves);
        if (!moved.IsSuccess)
        {
            return moved.Outcome;
        }

        LibrarySourceRelinkResult relinked = Relink(document, plan.RelinkPlan);
        return relinked.IsSuccess && relinked.UpdatedSourceCount == plan.SourceCount
            ? SourceMoveOutcome.Moved
            : SourceMoveOutcome.Failed;
    }

    internal LibrarySourceRelinkResult Relink(
        LibraryDocument? document,
        SourceRelinkPlan plan) => document is null
        ? new(
            0,
            0,
            plan?.Mappings.Count ?? 0,
            CatalogStoreError.NotFound,
            DefectSidecarError.None)
        : document.Relink(plan, sourceMetadataReader);
}
