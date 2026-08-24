using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell;

internal sealed class ScannerFramePublisher
{
    private readonly Func<string, LibrarySourceMetadata?> sourceMetadataReader;
    private readonly Action<string> selectFrame;
    private readonly Action<string> beginInfraredClean;
    private readonly Action<string, InfraredDefectApplyResult> completeInfraredClean;

    internal ScannerFramePublisher(
        Func<string, LibrarySourceMetadata?> sourceMetadataReader,
        Action<string> selectFrame,
        Action<string> beginInfraredClean,
        Action<string, InfraredDefectApplyResult> completeInfraredClean)
    {
        ArgumentNullException.ThrowIfNull(sourceMetadataReader);
        ArgumentNullException.ThrowIfNull(selectFrame);
        ArgumentNullException.ThrowIfNull(beginInfraredClean);
        ArgumentNullException.ThrowIfNull(completeInfraredClean);
        this.sourceMetadataReader = sourceMetadataReader;
        this.selectFrame = selectFrame;
        this.beginInfraredClean = beginInfraredClean;
        this.completeInfraredClean = completeInfraredClean;
    }

    internal ScannerFramePublishResult PublishPreview(
        LibraryDocument? document,
        ScannerFrameImport scan)
    {
        ArgumentNullException.ThrowIfNull(scan);
        if (document is null || !scan.IsPreviewScan)
        {
            return Failed(scan.VisiblePath, CatalogStoreError.NotFound);
        }

        FrameImportPlan plan = FrameImport.PlanScanner(
            scan,
            document.Frames,
            sourceMetadataReader: sourceMetadataReader);
        if (plan.Rows.Count != 1 || document.AppendTransientPreview(plan.Rows) != 1)
        {
            return new(
                ScannerFramePublishStatus.CatalogWriteFailed,
                plan,
                null,
                null,
                CatalogStoreError.None);
        }

        LibraryFrameSnapshot? frame = document.Frames.FirstOrDefault(
            candidate => candidate.Id == plan.Rows[0].Id);
        if (frame is null)
        {
            return new(
                ScannerFramePublishStatus.CatalogWriteFailed,
                plan,
                null,
                null,
                CatalogStoreError.InvalidSnapshot);
        }

        _ = document.RemoveTransientPreviewFrames(frame.Id);
        selectFrame(frame.Id);
        return new(
            ScannerFramePublishStatus.InfraredSkipped,
            plan,
            frame,
            null,
            CatalogStoreError.None);
    }

    internal ScannerFramePublishResult Publish(
        LibraryDocument? document,
        StorageRootSet? storageRoots,
        ScannerFrameImport scan,
        InfraredDetectorParameters? parameters,
        DevelopRun? run,
        string? existingReceipt = null)
    {
        ArgumentNullException.ThrowIfNull(scan);
        if (document is null)
        {
            return new(
                ScannerFramePublishStatus.CatalogWriteFailed,
                new FrameImportPlan([], [new FrameImportRejection(
                    scan.VisiblePath,
                    FrameImportRefusal.NoFiles)]),
                null,
                null,
                CatalogStoreError.NotFound);
        }

        string? receiptPath = existingReceipt;
        if (receiptPath is null && storageRoots is not null &&
            !ScannerPublicationReceiptStore.TrySchedule(storageRoots, scan, out receiptPath))
        {
            return new(
                ScannerFramePublishStatus.ReceiptWriteFailed,
                new FrameImportPlan([], [new FrameImportRejection(
                    scan.VisiblePath,
                    FrameImportRefusal.NoFiles)]),
                null,
                null,
                CatalogStoreError.None);
        }

        FrameImportPlan plan = FrameImport.PlanScanner(
            scan,
            document.Frames,
            sourceMetadataReader: sourceMetadataReader);
        if (plan.Rows.Count != 1)
        {
            if (existingReceipt is not null && HasPublishedFrame(document, scan))
            {
                ScannerPublicationReceiptStore.Complete(existingReceipt);
            }
            return new(ScannerFramePublishStatus.CatalogWriteFailed, plan, null, null,
                CatalogStoreError.None);
        }

        CatalogStoreError save = document.AppendAndSave(plan.Rows, out int added);
        if (save != CatalogStoreError.None || added != 1)
        {
            return new(ScannerFramePublishStatus.CatalogWriteFailed, plan, null, null, save);
        }
        if (receiptPath is not null)
        {
            ScannerPublicationReceiptStore.Complete(receiptPath);
        }

        LibraryFrameSnapshot? frame = document.Frames.FirstOrDefault(
            candidate => candidate.Id == plan.Rows[0].Id);
        if (frame is null)
        {
            return new(ScannerFramePublishStatus.CatalogWriteFailed, plan, null, null,
                CatalogStoreError.InvalidSnapshot);
        }

        selectFrame(frame.Id);
        if (frame.InfraredPath is null ||
            frame.Route.FilmType is not (FilmType.ColorNegative or FilmType.ColorPositive))
        {
            return new(ScannerFramePublishStatus.InfraredSkipped, plan, frame, null,
                CatalogStoreError.None);
        }
        if (!DefectSourceIdentityReader.TryRead(frame.SourcePath, out DefectSourceIdentity identity))
        {
            return new(ScannerFramePublishStatus.InfraredSourceUnreadable, plan, frame, null,
                CatalogStoreError.None);
        }

        InfraredDefectApplyResult? infrared = null;
        try
        {
            beginInfraredClean(frame.Id);
            infrared = InfraredDefectRecipeCoordinator.RunFiles(
                document,
                frame,
                identity,
                frame.SourcePath,
                frame.InfraredPath,
                parameters,
                run);
        }
        finally
        {
            completeInfraredClean(frame.Id, infrared ?? FailedInfraredClean());
        }
        return new(
            infrared.Status == InfraredDefectApplyStatus.Applied
                ? ScannerFramePublishStatus.InfraredApplied
                : ScannerFramePublishStatus.Published,
            plan,
            document.Frames.FirstOrDefault(candidate => candidate.Id == frame.Id) ?? frame,
            infrared,
            CatalogStoreError.None);
    }

    private static InfraredDefectApplyResult FailedInfraredClean() => new(
        InfraredDefectApplyStatus.DetectionFailed,
        null,
        null,
        DefectSidecarError.None,
        CatalogStoreError.None);

    internal void Recover(LibraryDocument? document, StorageRootSet? storageRoots)
    {
        if (storageRoots is null || document is null)
        {
            return;
        }

        foreach ((string path, ScannerPublicationReceipt receipt) in
                 ScannerPublicationReceiptStore.ReadPending(storageRoots))
        {
            _ = Publish(
                document,
                storageRoots,
                ScannerPublicationReceiptStore.ToScan(receipt),
                null,
                null,
                path);
        }
    }

    private static bool HasPublishedFrame(LibraryDocument document, ScannerFrameImport scan) =>
        document.Frames.Any(frame =>
            string.Equals(frame.SourcePath, scan.VisiblePath, StringComparison.OrdinalIgnoreCase) &&
            string.Equals(frame.InfraredPath, scan.InfraredPath, StringComparison.OrdinalIgnoreCase));

    private static ScannerFramePublishResult Failed(string path, CatalogStoreError error) =>
        new(
            ScannerFramePublishStatus.CatalogWriteFailed,
            new FrameImportPlan([], [new FrameImportRejection(path, FrameImportRefusal.NoFiles)]),
            null,
            null,
            error);
}
