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
    private readonly DevelopExportCoordinator coordinator;
    private LibraryDocument? document;

    public LibraryHostService(IUiDispatcher dispatcher)
        : this(dispatcher, new NativeDevelopExporterAdapter())
    {
    }

    public LibraryHostService(IUiDispatcher dispatcher, IDevelopExporter exporter)
    {
        ArgumentNullException.ThrowIfNull(dispatcher);
        ArgumentNullException.ThrowIfNull(exporter);
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
            State = LibraryHostState.Open;
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

        FrameImportPlan plan = FrameImport.Plan(filePaths, document.Frames, process);
        if (plan.Rows.Count > 0)
        {
            _ = document.AppendAndSave(plan.Rows, out _);
        }
        return plan;
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

        FrameImportPlan plan = FrameImport.PlanScanner(scan, document.Frames);
        if (plan.Rows.Count != 1)
        {
            return new(ScannerFramePublishStatus.CatalogWriteFailed, plan, null, null,
                CatalogStoreError.None);
        }
        CatalogStoreError save = document.AppendAndSave(plan.Rows, out int added);
        if (save != CatalogStoreError.None || added != 1)
        {
            return new(ScannerFramePublishStatus.CatalogWriteFailed, plan, null, null, save);
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

    public CatalogStoreError Save() =>
        document is null ? CatalogStoreError.NotFound : document.Save();

    public LibrarySourceRelinkResult Relink(SourceRelinkPlan plan) =>
        document is null
            ? new(0, 0, plan?.Mappings.Count ?? 0, CatalogStoreError.NotFound)
            : document.Relink(plan);

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
        document?.Dispose();
        document = null;
        State = LibraryHostState.NotOpened;
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
}
