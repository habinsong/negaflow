using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell;

internal sealed class ScannerFramePublisher
{
    private readonly Func<string, LibrarySourceMetadata?> sourceMetadataReader;
    private readonly Action<string> selectFrame;

    internal ScannerFramePublisher(
        Func<string, LibrarySourceMetadata?> sourceMetadataReader,
        Action<string> selectFrame)
    {
        ArgumentNullException.ThrowIfNull(sourceMetadataReader);
        ArgumentNullException.ThrowIfNull(selectFrame);
        this.sourceMetadataReader = sourceMetadataReader;
        this.selectFrame = selectFrame;
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

        InfraredDefectApplyResult infrared = InfraredDefectRecipeCoordinator.RunFiles(
            document,
            frame,
            identity,
            frame.SourcePath,
            frame.InfraredPath,
            parameters,
            run);
        return new(
            infrared.Status == InfraredDefectApplyStatus.Applied
                ? ScannerFramePublishStatus.InfraredApplied
                : ScannerFramePublishStatus.Published,
            plan,
            document.Frames.FirstOrDefault(candidate => candidate.Id == frame.Id) ?? frame,
            infrared,
            CatalogStoreError.None);
    }

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
                new ScannerFrameImport(receipt.VisiblePath, receipt.InfraredPath, receipt.Process),
                null,
                null,
                path);
        }
    }

    private static bool HasPublishedFrame(LibraryDocument document, ScannerFrameImport scan) =>
        document.Frames.Any(frame =>
            string.Equals(frame.SourcePath, scan.VisiblePath, StringComparison.OrdinalIgnoreCase) &&
            string.Equals(frame.InfraredPath, scan.InfraredPath, StringComparison.OrdinalIgnoreCase));
}
