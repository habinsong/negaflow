using Negaflow.Catalog;

namespace Negaflow.Shell;

internal sealed class LibraryImportController
{
    private readonly Func<string, LibrarySourceMetadata?> sourceMetadataReader;
    private readonly Action<string> selectFrame;

    internal LibraryImportController(
        Func<string, LibrarySourceMetadata?> sourceMetadataReader,
        Action<string> selectFrame)
    {
        ArgumentNullException.ThrowIfNull(sourceMetadataReader);
        ArgumentNullException.ThrowIfNull(selectFrame);
        this.sourceMetadataReader = sourceMetadataReader;
        this.selectFrame = selectFrame;
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

        FrameImportPlan plan = FrameImport.Plan(
            filePaths,
            document.Frames,
            process,
            sourceMetadataReader: sourceMetadataReader);
        if (plan.Rows.Count > 0)
        {
            _ = document.AppendAndSave(plan.Rows, out int added);
            if (added > 0)
            {
                selectFrame(plan.Rows[^1].Id);
            }
        }

        return plan;
    }

    internal FolderImportResult ImportFolders(
        LibraryDocument? document,
        IReadOnlyList<string> folderPaths,
        DevelopmentProcess process)
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

        FolderImportPlan plan = FolderImport.Plan(
            folderPaths,
            document.Frames,
            process,
            sourceMetadataReader: sourceMetadataReader);
        CatalogStoreError save = document.AppendFoldersAndFramesAndSave(
            plan.Folders,
            plan.Frames.Rows,
            out int addedFolders,
            out int addedFrames);
        if (save == CatalogStoreError.None && addedFrames > 0 && plan.Frames.Rows.Count > 0)
        {
            selectFrame(plan.Frames.Rows[^1].Id);
        }

        return new FolderImportResult(plan, addedFolders, addedFrames, save);
    }
}
