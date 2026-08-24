using Negaflow.Catalog;

namespace Negaflow.Shell;

internal sealed class LibraryImportController
{
    private readonly Func<string, LibrarySourceMetadata?> sourceMetadataReader;
    private readonly Action<string> infraredAttached;
    private readonly Action<string> selectFrame;
    private readonly Action<StrayInfraredFrameRepairPlan> strayInfraredFramesRemoved;

    internal LibraryImportController(
        Func<string, LibrarySourceMetadata?> sourceMetadataReader,
        Action<string> selectFrame,
        Action<string> infraredAttached,
        Action<StrayInfraredFrameRepairPlan> strayInfraredFramesRemoved)
    {
        ArgumentNullException.ThrowIfNull(sourceMetadataReader);
        ArgumentNullException.ThrowIfNull(selectFrame);
        ArgumentNullException.ThrowIfNull(infraredAttached);
        ArgumentNullException.ThrowIfNull(strayInfraredFramesRemoved);
        this.sourceMetadataReader = sourceMetadataReader;
        this.selectFrame = selectFrame;
        this.infraredAttached = infraredAttached;
        this.strayInfraredFramesRemoved = strayInfraredFramesRemoved;
    }

    internal FrameImportPlan Import(
        LibraryDocument? document,
        IReadOnlyList<string> filePaths,
        DevelopmentProcess process)
    {
        ArgumentNullException.ThrowIfNull(filePaths);
        if (document is null)
        {
            return new FrameImportPlan([], [new FrameImportRejection(
                string.Empty,
                FrameImportRefusal.NoFiles)]);
        }

        StrayInfraredFrameRepairPlan repair = HasImportableFile(filePaths)
            ? StrayInfraredFrameRepair.Plan(document.Frames)
            : StrayInfraredFrameRepairPlan.Empty;
        FrameImportPlan plan = IncludeRepair(FrameImport.Plan(
            filePaths,
            repair.Project(document.Frames),
            process,
            sourceMetadataReader: sourceMetadataReader), repair);
        if (plan.HasAnything)
        {
            CatalogStoreError save = document.ApplyImportAndSave(
                [],
                plan.Rows,
                plan.InfraredAttachments,
                plan.RemovedStrayInfraredFrameIds,
                out _,
                out int added,
                out IReadOnlyList<string> attachedFrameIds,
                out IReadOnlyList<string> removedFrameIds);
            if (save == CatalogStoreError.None)
            {
                foreach (string frameId in attachedFrameIds)
                {
                    infraredAttached(frameId);
                }
                if (removedFrameIds.Count > 0)
                {
                    strayInfraredFramesRemoved(repair);
                }
                if (added > 0)
                {
                    selectFrame(plan.Rows[^1].Id);
                }
            }
        }

        return plan;
    }

    internal FolderImportResult ImportFolders(
        LibraryDocument? document,
        IReadOnlyList<string> folderPaths,
        DevelopmentProcess process,
        bool selectAddedFrame = true)
    {
        ArgumentNullException.ThrowIfNull(folderPaths);
        if (document is null)
        {
            FolderImportPlan unavailable = new(
                [],
                new FrameImportPlan([], [new FrameImportRejection(
                    string.Empty,
                    FrameImportRefusal.NoFiles)]),
                [new FolderImportRejection(string.Empty, FolderImportRefusal.NoFolders)]);
            return new FolderImportResult(unavailable, 0, 0, CatalogStoreError.NotFound);
        }

        FolderImportPlan initial = FolderImport.Plan(
            folderPaths,
            document.Frames,
            process,
            sourceMetadataReader: sourceMetadataReader);
        if (initial.Rejected.Count > 0)
        {
            return new FolderImportResult(initial, 0, 0, CatalogStoreError.None);
        }
        StrayInfraredFrameRepairPlan repair = initial.HasImportableFiles
            ? StrayInfraredFrameRepair.Plan(document.Frames)
            : StrayInfraredFrameRepairPlan.Empty;
        FolderImportPlan planned = repair.RemovedFrameIds.Count > 0
            ? FolderImport.Plan(
                folderPaths,
                repair.Project(document.Frames),
                process,
                sourceMetadataReader: sourceMetadataReader)
            : initial;
        FolderImportPlan plan = planned with { Frames = IncludeRepair(planned.Frames, repair) };
        CatalogStoreError save = document.ApplyImportAndSave(
            plan.Folders,
            plan.Frames.Rows,
            plan.Frames.InfraredAttachments,
            plan.Frames.RemovedStrayInfraredFrameIds,
            out int addedFolders,
            out int addedFrames,
            out IReadOnlyList<string> attachedFrameIds,
            out IReadOnlyList<string> removedFrameIds);
        if (save == CatalogStoreError.None)
        {
            foreach (string frameId in attachedFrameIds)
            {
                infraredAttached(frameId);
            }
            if (removedFrameIds.Count > 0)
            {
                strayInfraredFramesRemoved(repair);
            }
        }
        if (selectAddedFrame && save == CatalogStoreError.None &&
            addedFrames > 0 && plan.Frames.Rows.Count > 0)
        {
            selectFrame(plan.Frames.Rows[^1].Id);
        }

        return new FolderImportResult(plan, addedFolders, addedFrames, save)
        {
            AttachedInfraredCount = attachedFrameIds.Count,
            RemovedStrayInfraredFrameCount = removedFrameIds.Count,
        };
    }

    private static FrameImportPlan IncludeRepair(
        FrameImportPlan plan,
        StrayInfraredFrameRepairPlan repair) => plan with
    {
        InfraredAttachments = [.. repair.Attachments, .. plan.InfraredAttachments],
        RemovedStrayInfraredFrameIds = repair.RemovedFrameIds,
    };

    private static bool HasImportableFile(IReadOnlyList<string> filePaths) => filePaths.Any(path =>
        !string.IsNullOrWhiteSpace(path) && Path.IsPathFullyQualified(path) &&
        File.Exists(path) && ImageSourcePaths.IsSupportedImportPath(path));
}
