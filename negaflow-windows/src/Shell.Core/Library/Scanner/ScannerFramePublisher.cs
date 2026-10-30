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
        string? existingReceipt = null) =>
        // 검출도 이 스레드에서 돌리므로 안에서 양보하는 await 가 없어 그 자리에서 끝납니다.
        PublishAsync(document, storageRoots, scan, parameters, run, existingReceipt, offloadDetection: false)
            .GetAwaiter()
            .GetResult();

    /// <summary>
    /// 스캔 한 장을 게시합니다. 카탈로그와 문서를 고치는 일은 부른 컨텍스트(UI)에서 하고,
    /// <paramref name="offloadDetection"/> 이면 그 사이의 IR 검출만 워커에서 돌립니다.
    /// </summary>
    /// <remarks>
    /// 실측(실제 라이브러리 183 장, 2400 dpi 한 쌍): 게시 1,650 ms 중 IR 검출이 505 ms(첫 회
    /// 869 ms)였고, 그동안 UI 스레드가 통째로 멈췄습니다. 검출은 문서를 건드리지 않으므로
    /// 옮겨도 카탈로그 목록과 경쟁하지 않습니다.
    /// </remarks>
    internal async Task<ScannerFramePublishResult> PublishAsync(
        LibraryDocument? document,
        StorageRootSet? storageRoots,
        ScannerFrameImport scan,
        InfraredDetectorParameters? parameters,
        DevelopRun? run,
        string? existingReceipt = null,
        bool offloadDetection = true)
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

        // **IR 이 끝나기 전에는 이 사진을 내놓지 않습니다.**
        //
        // 앞 판은 여기서 곧바로 골랐습니다. 그러면 IR 을 붙이기 전 사진이 먼저 화면에
        // 뜨고, 몇 초 뒤에 GrainMend IR 이 얹히면서 같은 사진이 두 번 바뀝니다 - 사용자에게는
        // "IR 이 안 먹은 사진이 먼저 나온다" 로 보입니다. IR 을 쓰는 스캔은 본 스캔 한 장과
        // IR 한 장이 <b>합쳐져야 한 장</b>이므로, 그 일이 끝난 뒤에 내놓습니다.
        if (frame.InfraredPath is not { } infraredPath ||
            frame.Route.FilmType is not (FilmType.ColorNegative or FilmType.ColorPositive))
        {
            selectFrame(frame.Id);
            return new(ScannerFramePublishStatus.InfraredSkipped, plan, frame, null,
                CatalogStoreError.None);
        }
        if (!DefectSourceIdentityReader.TryRead(frame.SourcePath, out DefectSourceIdentity identity))
        {
            selectFrame(frame.Id);
            return new(ScannerFramePublishStatus.InfraredSourceUnreadable, plan, frame, null,
                CatalogStoreError.None);
        }

        InfraredDefectApplyResult? infrared = null;
        try
        {
            beginInfraredClean(frame.Id);
            infrared = offloadDetection
                ? await InfraredDefectRecipeCoordinator.RunFilesAsync(
                    document,
                    frame,
                    identity,
                    frame.SourcePath,
                    infraredPath,
                    parameters,
                    run)
                : InfraredDefectRecipeCoordinator.RunFiles(
                    document,
                    frame,
                    identity,
                    frame.SourcePath,
                    infraredPath,
                    parameters,
                    run);
        }
        finally
        {
            completeInfraredClean(frame.Id, infrared ?? FailedInfraredClean());
            // IR 이 끝난 지금이 이 사진을 내놓을 자리입니다 - 붙었든 못 붙었든, 더 바뀔 일이
            // 없을 때 한 번만 보여 줍니다.
            selectFrame(frame.Id);
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
