using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
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

    /// <summary>macOS <c>scheduleLibrarySave</c> 와 같은 1.5 초입니다.</summary>
    private static readonly TimeSpan AutomaticSaveDelay = TimeSpan.FromSeconds(1.5);
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

    /// <summary>열린 카탈로그가 쓰는 디스크 자리입니다. 열기 전에는 null 입니다.</summary>
    public StorageRootSet? StorageRoots => storageRoots;
    private Timer? saveTimer;

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

    /// <summary>
    /// 사용자가 고른 frame 들입니다. macOS 처럼 라이브러리와 현상이 같은 선택을 봅니다 — 그래야
    /// 출력 패널의 "내보내기 (N)" 이 격자에서 고른 것과 같은 것을 가리킵니다.
    /// </summary>
    public IReadOnlyList<string> SelectedFrameIds { get; private set; } = [];

    public event EventHandler? SelectionChanged;

    /// <summary>고른 순서를 지키며, 카탈로그에 없는 id 는 버립니다.</summary>
    public void SetSelection(IEnumerable<string> frameIds)
    {
        ArgumentNullException.ThrowIfNull(frameIds);
        var known = new HashSet<string>(Frames.Select(frame => frame.Id), StringComparer.Ordinal);
        var seen = new HashSet<string>(StringComparer.Ordinal);
        string[] next = [.. frameIds.Where(id => known.Contains(id) && seen.Add(id))];
        if (next.SequenceEqual(SelectedFrameIds, StringComparer.Ordinal))
        {
            return;
        }
        SelectedFrameIds = next;
        SelectionChanged?.Invoke(this, EventArgs.Empty);
    }

    /// <summary>선택된 frame 들입니다. 선택이 비면 빈 목록입니다.</summary>
    public IReadOnlyList<LibraryFrameSnapshot> SelectedFrames
    {
        get
        {
            if (SelectedFrameIds.Count == 0)
            {
                return [];
            }
            var byId = Frames.ToDictionary(frame => frame.Id, StringComparer.Ordinal);
            return [.. SelectedFrameIds
                .Select(id => byId.TryGetValue(id, out LibraryFrameSnapshot? frame) ? frame : null)
                .OfType<LibraryFrameSnapshot>()];
        }
    }

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

    /// <summary>
    /// 편집 셋은 모두 이 자리를 지나므로, 저장 예약도 여기서 겁니다. 호출부마다 예약을 걸게
    /// 하면 한 군데만 빠져도 그 편집이 조용히 사라집니다.
    /// </summary>
    public LibraryFrameError Edit(string frameId, LibraryFrameEdit edit) =>
        AfterEdit(document is null
            ? LibraryFrameError.MissingId
            : document.Edit(frameId, edit));

    /// <summary>필름 룩처럼 develop route 자체를 바꾸는 편집입니다.</summary>
    public LibraryFrameError EditRoute(string frameId, DevelopRouteSelection selection) =>
        AfterEdit(document is null
            ? LibraryFrameError.MissingId
            : document.EditRoute(frameId, selection));

    public IReadOnlyList<LibraryCollectionSnapshot> Collections =>
        document?.Collections ?? [];

    public IReadOnlyList<LibraryRollSnapshot> Rolls => document?.Rolls ?? [];

    public IReadOnlyList<LibraryStoredSearchSnapshot> StoredSearches =>
        document?.StoredSearches ?? [];

    public string? CreateStoredSearch(
        string name,
        LibraryStoredSearchKind kind,
        LibraryStoredQuery query)
    {
        string? id = document?.CreateStoredSearch(name, kind, query);
        if (id is not null)
        {
            _ = SaveIfDirty();
        }
        return id;
    }

    public bool DeleteStoredSearch(string searchId) =>
        SavedAfter(document?.DeleteStoredSearch(searchId) == true);

    public string? ActiveRollId => document?.ActiveRollId;

    public LibraryRollSnapshot? RollFor(string frameId) => document?.RollFor(frameId);

    public string? CreateRoll(string name, FilmType filmType, IEnumerable<string> frameIds)
    {
        string? id = document?.CreateRoll(name, filmType, frameIds);
        if (id is not null)
        {
            _ = SaveIfDirty();
        }
        return id;
    }

    public bool SetRollRecord(string rollId, RollRecord? record) =>
        SavedAfter(document?.SetRollRecord(rollId, record) == true);

    public bool SetRollFrames(string rollId, IEnumerable<string> frameIds) =>
        SavedAfter(document?.SetRollFrames(rollId, frameIds) == true);

    public bool DeleteRoll(string rollId) =>
        SavedAfter(document?.DeleteRoll(rollId) == true);

    public bool SetActiveRoll(string? rollId) =>
        SavedAfter(document?.SetActiveRoll(rollId) == true);

    /// <summary>묶음을 만들고 바로 저장합니다. 만들지 못하면 null 입니다.</summary>
    public string? CreateCollection(string name, IEnumerable<string> frameIds)
    {
        string? id = document?.CreateCollection(name, frameIds);
        if (id is not null)
        {
            _ = SaveIfDirty();
        }
        return id;
    }

    public bool RenameCollection(string collectionId, string name) =>
        SavedAfter(document?.RenameCollection(collectionId, name) == true);

    public bool SetCollectionFrames(string collectionId, IEnumerable<string> frameIds) =>
        SavedAfter(document?.SetCollectionFrames(collectionId, frameIds) == true);

    public bool DeleteCollection(string collectionId) =>
        SavedAfter(document?.DeleteCollection(collectionId) == true);

    /// <summary>한 장으로 접어 둔 사진 묶음입니다.</summary>
    public IReadOnlyList<LibraryStackSnapshot> Stacks => document?.Stacks ?? [];

    public LibraryStackSnapshot? StackFor(string frameId) => document?.StackFor(frameId);

    public string? CreateStack(IEnumerable<string> frameIds)
    {
        string? id = document?.CreateStack(frameIds);
        if (id is not null)
        {
            _ = SaveIfDirty();
        }
        return id;
    }

    public bool UngroupStack(string stackId) =>
        SavedAfter(document?.UngroupStack(stackId) == true);

    public bool ToggleStackCollapsed(string stackId) =>
        SavedAfter(document?.ToggleStackCollapsed(stackId) == true);

    /// <summary>
    /// 사진을 라이브러리에서 빼고 바로 저장합니다. 원본 파일은 그대로 둡니다. 돌려주는 값은
    /// 실제로 빠진 장수입니다.
    /// </summary>
    public int RemoveFrames(IEnumerable<string> frameIds)
    {
        ArgumentNullException.ThrowIfNull(frameIds);
        if (document is not { } open)
        {
            return 0;
        }
        LibraryFrameRemoval removal = open.RemoveFrames(frameIds);
        if (removal.Count == 0)
        {
            return 0;
        }
        _ = SaveIfDirty();
        // sidecar 는 catalog 가 더 이상 그 사진을 말하지 않게 된 뒤에만 지울 수 있습니다.
        open.PurgeDefectSidecars(removal);
        return removal.Count;
    }

    private bool SavedAfter(bool changed)
    {
        if (changed)
        {
            _ = SaveIfDirty();
        }
        return changed;
    }

    /// <summary>사이드카가 적을 frame record 의 복사본입니다.</summary>
    public System.Text.Json.Nodes.JsonObject? FrameRecord(string frameId) =>
        document?.FrameRecord(frameId);

    /// <summary>현상 버전을 담거나 되돌리거나, 현상 설정을 붙여넣습니다.</summary>
    public LibraryFrameError EditFrameRecord(
        string frameId,
        Func<System.Text.Json.Nodes.JsonObject, LibraryFrameWriteResult> edit) =>
        AfterEdit(document is null
            ? LibraryFrameError.MissingId
            : document.EditFrameRecord(frameId, edit));

    private LibraryFrameError AfterEdit(LibraryFrameError error)
    {
        if (error == LibraryFrameError.None)
        {
            ScheduleSave();
        }
        return error;
    }

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

        FrameImportPlan plan = FrameImport.PlanScanner(
            scan,
            document.Frames,
            sourceMetadataReader: sourceMetadataReader);
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

    public CatalogStoreError Save()
    {
        saveTimer?.Change(Timeout.Infinite, Timeout.Infinite);
        return document is null ? CatalogStoreError.NotFound : document.Save();
    }

    /// <summary>
    /// 마지막 저장 실패 사유입니다. 자동 저장은 조용히 일어나므로, 실패했다는 사실만은 셸이
    /// 볼 수 있어야 합니다.
    /// </summary>
    public CatalogStoreError LastAutomaticSaveError { get; private set; }

    /// <summary>
    /// 잠시 뒤에 저장합니다. macOS 와 같이 1.5 초를 기다렸다가 그 사이의 변경을 한 번에
    /// 씁니다 — 슬라이더를 끄는 동안 catalog 를 수백 번 쓰지 않기 위해서입니다.
    /// </summary>
    /// <remarks>
    /// 편집은 메모리에서 먼저 일어나므로 이 예약이 없으면 창을 닫는 순간 조용히 사라집니다.
    /// 타이머는 UI 스레드가 아닌 곳에서 울리므로 dispatcher 를 거쳐 문서를 만집니다 —
    /// <see cref="LibraryDocument"/> 는 한 스레드에서만 쓰입니다.
    /// </remarks>
    public void ScheduleSave()
    {
        if (document is null)
        {
            return;
        }
        saveTimer ??= new Timer(_ => RequestAutomaticSave(), null, Timeout.Infinite, Timeout.Infinite);
        saveTimer.Change(AutomaticSaveDelay, Timeout.InfiniteTimeSpan);
    }

    /// <summary>
    /// 예약된 저장이 남아 있으면 지금 씁니다. 창을 닫기 전에 부릅니다.
    /// </summary>
    public CatalogStoreError SaveIfDirty()
    {
        saveTimer?.Change(Timeout.Infinite, Timeout.Infinite);
        return document is { IsDirty: true } dirty ? dirty.Save() : CatalogStoreError.None;
    }

    private void RequestAutomaticSave()
    {
        if (dispatcher.HasThreadAccess)
        {
            AutomaticSave();
            return;
        }
        // 큐에 넣지 못했다는 것은 창이 이미 닫혔다는 뜻입니다. 그때는 Dispose 가 마지막으로
        // 한 번 씁니다.
        _ = dispatcher.TryEnqueue(AutomaticSave);
    }

    private void AutomaticSave()
    {
        if (document is not { IsDirty: true } dirty)
        {
            return;
        }
        LastAutomaticSaveError = dirty.Save();
    }

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
        Action<DevelopExportOutcome> onCompleted,
        ExportEncodingOptions? encoding = null) =>
        coordinator.StartAsync(frame, destinationPath, format, onCompleted, encoding);

    public void Dispose()
    {
        // 놓아 주기 전에 마지막으로 씁니다. 여기서 빠지면 마지막 1.5 초의 편집이 사라집니다.
        _ = SaveIfDirty();
        saveTimer?.Dispose();
        saveTimer = null;
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

    /// <summary>
    /// 캔버스에서 그은 결함 편집 한 획을 붙이고 sidecar 와 catalog 에 씁니다. 원본을 읽어
    /// identity 를 확인하므로, 파일이 바뀐 사진에는 붙지 않습니다.
    /// </summary>
    public LibraryFrameError AppendDefectStroke(
        string frameId,
        Func<DefectSourceIdentity, DefectRecipeSnapshot?, DefectRecipeSnapshot?> build)
    {
        ArgumentNullException.ThrowIfNull(frameId);
        ArgumentNullException.ThrowIfNull(build);
        if (document is null)
        {
            return LibraryFrameError.MissingId;
        }
        if (document.Frames.FirstOrDefault(candidate => candidate.Id == frameId)
            is not { } frame)
        {
            return LibraryFrameError.MissingId;
        }
        if (!TryReadSourceIdentity(frame.SourcePath, out DefectSourceIdentity identity))
        {
            return LibraryFrameError.InvalidDefectRecipe;
        }
        if (build(identity, frame.DefectRecipe) is not { } recipe)
        {
            return LibraryFrameError.InvalidDefectRecipe;
        }
        LibraryDefectRecipeWriteResult written = document.WriteDefectRecipe(frameId, recipe);
        if (!written.IsSuccess)
        {
            return written.FrameError == LibraryFrameError.None
                ? LibraryFrameError.InvalidDefectRecipe
                : written.FrameError;
        }
        // sidecar 와 catalog 는 이미 여기서 함께 쓰였으므로 지연 저장을 다시 걸지 않습니다.
        return LibraryFrameError.None;
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
