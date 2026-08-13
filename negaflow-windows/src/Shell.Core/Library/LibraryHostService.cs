using Negaflow.Catalog;
using Negaflow.Interop;
using System.Security.Cryptography;

namespace Negaflow.Shell;

public enum LibraryHostState
{
    NotOpened,
    Open,

    /// <summary>다른 프로세스가 이미 이 카탈로그의 작성자입니다.</summary>
    Busy,

    /// <summary>카탈로그가 손상됐거나 이 빌드가 모르는 version 입니다.</summary>
    Unavailable,
}

public enum ScannerFramePublishStatus
{
    Published,
    InfraredApplied,
    InfraredSkipped,
    InfraredSourceUnreadable,
    ReceiptWriteFailed,
    CatalogWriteFailed,
}

public sealed record ScannerFramePublishResult(
    ScannerFramePublishStatus Status,
    FrameImportPlan Plan,
    LibraryFrameSnapshot? Frame,
    InfraredDefectApplyResult? Infrared,
    CatalogStoreError CatalogError);

/// <summary>
/// 셸이 라이브러리와 현상 엔진에 닿는 유일한 자리입니다. XAML 코드비하인드가 catalog 세션이나
/// 네이티브 호출을 직접 잡지 않도록 여기서 소유합니다.
/// </summary>
/// <remarks>
/// 열기는 시작할 때 한 번입니다. 실패해도 예외를 던지지 않고 상태로 남기며, 셸은 그 상태를
/// 보여 줄 뿐 빈 라이브러리로 착각하지 않습니다.
/// </remarks>
public sealed class LibraryHostService : IDisposable
{
    private const int AsynchronousAvailabilityThreshold = 256;
    private readonly DevelopExportCoordinator coordinator;
    private readonly IUiDispatcher dispatcher;
    private readonly Func<string, LibrarySourceMetadata?> sourceMetadataReader;
    private IReadOnlyDictionary<string, LibrarySourceAvailability> availabilityByFrameId =
        new Dictionary<string, LibrarySourceAvailability>();
    private IReadOnlyDictionary<string, bool> availabilityByFolderId =
        new Dictionary<string, bool>();
    private int availabilityRefreshVersion;
    private LibraryDocument? document;
    private StorageRootSet? storageRoots;

    public LibraryHostService(IUiDispatcher dispatcher)
        : this(dispatcher, new NativeDevelopExporterAdapter(), ReadSourceMetadata)
    {
    }

    public LibraryHostService(
        IUiDispatcher dispatcher,
        IDevelopExporter exporter,
        Func<string, LibrarySourceMetadata?>? sourceMetadataReader = null)
    {
        ArgumentNullException.ThrowIfNull(dispatcher);
        ArgumentNullException.ThrowIfNull(exporter);
        this.dispatcher = dispatcher;
        this.sourceMetadataReader = sourceMetadataReader ?? ReadSourceMetadata;
        coordinator = new DevelopExportCoordinator(exporter, dispatcher);
    }

    public LibraryHostState State { get; private set; } = LibraryHostState.NotOpened;

    public CatalogSessionError SessionError { get; private set; }

    public CatalogStoreError StoreError { get; private set; }

    public DefectSidecarError DefectSidecarError { get; private set; }

    public IReadOnlyList<LibraryFrameSnapshot> Frames =>
        document?.Frames ?? [];

    public IReadOnlyList<LibraryFrameIssue> Issues =>
        document?.Issues ?? [];

    public IReadOnlyList<LibraryFolderSnapshot> Folders =>
        document?.Folders ?? [];

    public IReadOnlyDictionary<string, LibrarySourceAvailability> SourceAvailabilityByFrameId =>
        availabilityByFrameId;

    public IReadOnlyDictionary<string, bool> FolderAvailabilityById => availabilityByFolderId;

    public bool IsExporting => coordinator.IsRunning;

    public LibraryHostState Open(StorageRootSet roots)
    {
        ArgumentNullException.ThrowIfNull(roots);
        if (document is not null)
        {
            return State;
        }

        LibraryDocumentOpenResult opened = LibraryDocument.Open(roots);
        SessionError = opened.SessionError;
        StoreError = opened.StoreError;
        DefectSidecarError = opened.DefectSidecarError;
        if (opened.Document is { } loaded)
        {
            document = loaded;
            storageRoots = roots;
            State = LibraryHostState.Open;
            RecoverScannerPublications();
            return State;
        }

        State = opened.Error == LibraryDocumentError.SessionBusy
            ? LibraryHostState.Busy
            : LibraryHostState.Unavailable;
        return State;
    }

    public LibraryFrameError Edit(string frameId, LibraryFrameEdit edit) =>
        document is null
            ? LibraryFrameError.MissingId
            : document.Edit(frameId, edit);

    /// <summary>필름 룩처럼 develop route 자체를 바꾸는 편집입니다.</summary>
    public LibraryFrameError EditRoute(string frameId, DevelopRouteSelection selection) =>
        document is null
            ? LibraryFrameError.MissingId
            : document.EditRoute(frameId, selection);

    /// <summary>
    /// 고른 파일을 라이브러리에 넣고 바로 저장합니다. 넣기만 하고 저장하지 않으면 앱이 죽었을 때
    /// 사용자가 방금 가져온 것이 사라집니다.
    /// </summary>
    public FrameImportPlan Import(
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
            filePaths, document.Frames, process, sourceMetadataReader: sourceMetadataReader);
        if (plan.Rows.Count > 0)
        {
            _ = document.AppendAndSave(plan.Rows, out _);
        }
        return plan;
    }

    public FolderImportResult ImportFolders(
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
            folderPaths, document.Frames, process, sourceMetadataReader: sourceMetadataReader);
        CatalogStoreError save = document.AppendFoldersAndFramesAndSave(
            plan.Folders,
            plan.Frames.Rows,
            out int addedFolders,
            out int addedFrames);
        return new FolderImportResult(plan, addedFolders, addedFrames, save);
    }

    /// <summary>
    /// macOS와 같은 source/folder snapshot을 만듭니다. 작은 library는 즉시 갱신하고, 256개를
    /// 넘으면 UI thread 밖에서 검사한 뒤 아직 같은 document인 경우에만 결과를 반영합니다.
    /// </summary>
    public void RefreshAvailability(Action? onCompleted = null)
    {
        LibraryDocument? currentDocument = document;
        if (currentDocument is null)
        {
            return;
        }

        IReadOnlyList<LibraryFrameSnapshot> frames = currentDocument.Frames.ToArray();
        IReadOnlyList<LibraryFolderSnapshot> folders = currentDocument.Folders.ToArray();
        int refreshVersion = unchecked(++availabilityRefreshVersion);
        if (frames.Count <= AsynchronousAvailabilityThreshold)
        {
            ApplyAvailability(currentDocument, refreshVersion,
                LibraryAvailability.Probe(frames, folders), onCompleted);
            return;
        }

        _ = Task.Run(() => LibraryAvailability.Probe(frames, folders)).ContinueWith(
            task =>
            {
                if (task.Status != TaskStatus.RanToCompletion)
                {
                    return;
                }
                _ = dispatcher.TryEnqueue(() => ApplyAvailability(
                    currentDocument,
                    refreshVersion,
                    task.Result,
                    onCompleted));
            },
            CancellationToken.None,
            TaskContinuationOptions.ExecuteSynchronously,
            TaskScheduler.Default);
    }

    /// <summary>
    /// scanner host가 두 artifact를 commit한 뒤 호출하는 publication 경계입니다. RGB record가
    /// catalog에 먼저 durable하게 남은 뒤에만 IR recipe를 써서, 실패가 원본 frame 자체를
    /// 사라지게 하거나 고아 sidecar를 남기지 않게 합니다.
    /// </summary>
    public ScannerFramePublishResult PublishScannerFrame(
        ScannerFrameImport scan,
        InfraredDetectorParameters? parameters = null,
        DevelopRun? run = null)
    {
        return PublishScannerFrame(scan, parameters, run, null);
    }

    private ScannerFramePublishResult PublishScannerFrame(
        ScannerFrameImport scan,
        InfraredDetectorParameters? parameters,
        DevelopRun? run,
        string? existingReceipt)
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
                new FrameImportPlan([], [new FrameImportRejection(scan.VisiblePath, FrameImportRefusal.NoFiles)]),
                null,
                null,
                CatalogStoreError.None);
        }

        FrameImportPlan plan = FrameImport.PlanScanner(scan, document.Frames);
        if (plan.Rows.Count != 1)
        {
            if (existingReceipt is not null && HasPublishedFrame(scan))
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
        if (frame.InfraredPath is null ||
            frame.Route.FilmType is not (FilmType.ColorNegative or FilmType.ColorPositive))
        {
            return new(ScannerFramePublishStatus.InfraredSkipped, plan, frame, null,
                CatalogStoreError.None);
        }
        if (!TryReadSourceIdentity(frame.SourcePath, out DefectSourceIdentity identity))
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

    private void RecoverScannerPublications()
    {
        if (storageRoots is null || document is null)
        {
            return;
        }

        foreach ((string path, ScannerPublicationReceipt receipt) in
                 ScannerPublicationReceiptStore.ReadPending(storageRoots))
        {
            _ = PublishScannerFrame(
                new ScannerFrameImport(receipt.VisiblePath, receipt.InfraredPath, receipt.Process),
                null,
                null,
                path);
        }
    }

    private bool HasPublishedFrame(ScannerFrameImport scan) => document?.Frames.Any(
        frame => string.Equals(frame.SourcePath, scan.VisiblePath, StringComparison.OrdinalIgnoreCase) &&
                 string.Equals(frame.InfraredPath, scan.InfraredPath, StringComparison.OrdinalIgnoreCase)) == true;

    public CatalogStoreError Save() =>
        document is null ? CatalogStoreError.NotFound : document.Save();

    public LibrarySourceRelinkResult Relink(SourceRelinkPlan plan) =>
        document is null
            ? new(0, 0, plan?.Mappings.Count ?? 0, CatalogStoreError.NotFound)
            : document.Relink(plan, sourceMetadataReader);

    /// <summary>
    /// 현상해서 파일로 씁니다. 네이티브 호출은 워커 스레드에서 돌고 결과는 dispatcher 를 거쳐
    /// 돌아옵니다. 자세한 계약은 <see cref="DevelopExportCoordinator"/> 를 보십시오.
    /// </summary>
    public Task<bool> ExportAsync(
        LibraryFrameSnapshot frame,
        string destinationPath,
        DevelopExportFormat format,
        Action<DevelopExportOutcome> onCompleted) =>
        coordinator.StartAsync(frame, destinationPath, format, onCompleted);

    public void Dispose()
    {
        unchecked { ++availabilityRefreshVersion; }
        availabilityByFrameId = new Dictionary<string, LibrarySourceAvailability>();
        availabilityByFolderId = new Dictionary<string, bool>();
        document?.Dispose();
        document = null;
        State = LibraryHostState.NotOpened;
    }

    private void ApplyAvailability(
        LibraryDocument expectedDocument,
        int refreshVersion,
        LibraryAvailabilitySnapshot snapshot,
        Action? onCompleted)
    {
        if (!ReferenceEquals(document, expectedDocument) ||
            availabilityRefreshVersion != refreshVersion)
        {
            return;
        }
        availabilityByFrameId = snapshot.ByFrameId;
        availabilityByFolderId = snapshot.ByFolderId;
        onCompleted?.Invoke();
    }

    private static bool TryReadSourceIdentity(string path, out DefectSourceIdentity identity)
    {
        identity = default;
        try
        {
            using FileStream stream = new(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                bufferSize: 128 * 1024,
                FileOptions.SequentialScan);
            if (stream.Length <= 0)
            {
                return false;
            }
            byte[] hash = SHA256.HashData(stream);
            identity = new DefectSourceIdentity(
                checked((ulong)stream.Length),
                Convert.ToHexString(hash).ToLowerInvariant());
            return true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or ArgumentException or PathTooLongException or OverflowException)
        {
            return false;
        }
    }

    private static LibrarySourceMetadata? ReadSourceMetadata(string path)
    {
        bool read = ImageSourcePaths.UsesWicStandardDecoder(path)
            ? NativeStandardImageSourceProbe.TryRead(path, out TiffSourceMetadata metadata)
            : NativeTiffSourceProbe.TryRead(path, out metadata);
        return read
            ? new LibrarySourceMetadata(
                metadata.FileBytes,
                metadata.PixelWidth,
                metadata.PixelHeight,
                metadata.SamplesPerPixel,
                metadata.BitsPerSample,
                metadata.SampleFormat,
                metadata.Orientation)
            : null;
    }

}
