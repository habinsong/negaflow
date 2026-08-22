using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;

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
    private readonly LibraryAutosaveController autosave;
    private readonly LibraryAvailabilityController availability;
    private readonly DevelopExportCoordinator coordinator;
    private readonly LibraryImportController importer;
    private readonly ScannerFramePublisher scannerPublisher;
    private readonly LibrarySelectionState selection;
    private readonly LibrarySourceController sourceController;
    private readonly Func<string, LibrarySourceMetadata?> sourceMetadataReader;
    private LibraryDocument? document;
    private StorageRootSet? storageRoots;

    /// <summary>열린 카탈로그가 쓰는 디스크 자리입니다. 열기 전에는 null 입니다.</summary>
    public StorageRootSet? StorageRoots => storageRoots;
    public LibraryHostService(IUiDispatcher dispatcher)
        : this(dispatcher, new NativeDevelopExporterAdapter(), LibrarySourceMetadataReader.Read)
    {
    }

    public LibraryHostService(
        IUiDispatcher dispatcher,
        IDevelopExporter exporter,
        Func<string, LibrarySourceMetadata?>? sourceMetadataReader = null)
    {
        ArgumentNullException.ThrowIfNull(dispatcher);
        ArgumentNullException.ThrowIfNull(exporter);
        this.sourceMetadataReader = sourceMetadataReader ?? LibrarySourceMetadataReader.Read;
        selection = new LibrarySelectionState(
            () => SelectionChanged?.Invoke(this, EventArgs.Empty));
        availability = new LibraryAvailabilityController(dispatcher, () => document);
        autosave = new LibraryAutosaveController(dispatcher, () => document);
        importer = new LibraryImportController(this.sourceMetadataReader, SelectSingleFrame);
        scannerPublisher = new ScannerFramePublisher(this.sourceMetadataReader, SelectSingleFrame);
        sourceController = new LibrarySourceController(this.sourceMetadataReader);
        coordinator = new DevelopExportCoordinator(exporter, dispatcher);
    }

    public LibraryHostState State { get; private set; } = LibraryHostState.NotOpened;

    public CatalogSessionError SessionError { get; private set; }

    /// <summary>
    /// 마지막 저장 뒤에 바뀐 것이 있는지입니다. 진단 보고서가 읽습니다 - macOS
    /// <c>hasUnsavedLibraryChanges</c> 자리입니다.
    /// </summary>
    public bool HasUnsavedChanges => document?.IsDirty ?? false;

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
    public IReadOnlyList<string> SelectedFrameIds => selection.SelectedFrameIds;

    /// <summary>
    /// 선택 집합 안에서 Library, Develop, Print가 현재 보여 주는 한 장입니다. 다중 선택과
    /// 분리해야 Print 대상 전체를 유지하면서 Develop 캔버스는 한 장만 정확히 가리킬 수 있습니다.
    /// </summary>
    public string? ActiveFrameId => selection.ActiveFrameId;

    public event EventHandler? SelectionChanged;

    /// <summary>
    /// 편집이 실제로 값을 바꾼 뒤 한 번 납니다. 창 안 메뉴막대가 macOS 의 메뉴 Toggle 처럼
    /// 지금 값을 되비추려면 이 신호가 필요합니다 — WinUI <c>MenuBarItem</c> 에는 메뉴를 여는
    /// 순간에 나는 이벤트가 없습니다.
    /// </summary>
    public event EventHandler? FrameEdited;

    /// <summary>고른 순서를 지키며, 카탈로그에 없는 id 는 버립니다.</summary>
    public void SetSelection(IEnumerable<string> frameIds, string? activeFrameId = null)
    {
        selection.Set(Frames, frameIds, activeFrameId);
        TryInfraredCleanIfNeeded(ActiveFrameId);
    }

    /// <summary>
    /// 앱을 다시 열 때 저장된 active frame을 복구합니다. 없거나 원본이 오프라인이면 macOS처럼
    /// 가장 최근의 사용 가능한 사진을 고릅니다.
    /// </summary>
    public string? RestoreActiveFrame(string? savedFrameId)
        => selection.RestoreActiveFrame(Frames, savedFrameId, availability.IsAvailable);

    /// <summary>
    /// 비동기 원본 가용성 검사가 끝난 뒤 오프라인 active frame을 바로잡습니다. 살아 있는
    /// 선택을 먼저 지키고, 없을 때만 최근 사진으로 이동합니다.
    /// </summary>
    public string? ReconcileActiveFrameAvailability()
        => selection.ReconcileActiveFrameAvailability(Frames, availability.IsAvailable);

    /// <summary>선택된 frame 들입니다. 선택이 비면 빈 목록입니다.</summary>
    public IReadOnlyList<LibraryFrameSnapshot> SelectedFrames => selection.SelectedFrames(Frames);

    public IReadOnlyList<LibraryFolderSnapshot> Folders =>
        document?.Folders ?? [];

    public IReadOnlyDictionary<string, LibrarySourceAvailability> SourceAvailabilityByFrameId =>
        availability.ByFrameId;

    public IReadOnlyDictionary<string, bool> FolderAvailabilityById => availability.ByFolderId;

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
            scannerPublisher.Recover(document, storageRoots);
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
    /// <summary>
    /// 지금 카탈로그를 백업합니다. 열려 있지 않으면 아무 것도 하지 않고 실패를 냅니다 —
    /// 빈 백업을 만들어 "성공"으로 적으면 사용자는 지켜지고 있다고 믿습니다.
    /// </summary>
    public CatalogBackupCreateResult CreateBackup() =>
        document?.CreateBackup() ??
        new CatalogBackupCreateResult(null, 0, CatalogBackupError.InvalidCatalog, false);

    public LibraryFrameError Edit(string frameId, LibraryFrameEdit edit) =>
        AfterCoalescedDevelopEdit(frameId, () =>
            document is null
                ? LibraryFrameError.MissingId
                : document.Edit(frameId, edit));

    /// <summary>
    /// macOS <c>registerDevelopAdjustmentUndo</c> — 초기화처럼 한 번에 여러 슬라이더를
    /// 지우는 동작은 ⌘Z / Ctrl+Z 로 되돌려야 합니다.
    /// </summary>
    public LibraryFrameError EditUndoable(
        string frameId,
        string actionName,
        LibraryFrameEdit edit)
    {
        if (document is not { } open)
        {
            return LibraryFrameError.MissingId;
        }

        frameEdits.Clear(frameId);
        open.CaptureUndo(actionName);
        LibraryFrameError error = open.Edit(frameId, edit);
        if (error != LibraryFrameError.None)
        {
            _ = open.Undo();
            return error;
        }

        return AfterEdit(error);
    }

    /// <summary>필름 룩처럼 develop route 자체를 바꾸는 편집입니다.</summary>
    public LibraryFrameError EditRoute(string frameId, DevelopRouteSelection selection) =>
        AfterCoalescedDevelopEdit(frameId, () =>
            document is null
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
    public string? CreateCollection(string name, IEnumerable<string> frameIds) =>
        Undoable(UndoActions.CreateCollection, () => document?.CreateCollection(name, frameIds));

    public bool RenameCollection(string collectionId, string name) =>
        Undoable(UndoActions.RenameCollection, () =>
            document?.RenameCollection(collectionId, name) == true);

    public bool SetCollectionFrames(string collectionId, IEnumerable<string> frameIds) =>
        Undoable(UndoActions.EditCollection, () =>
            document?.SetCollectionFrames(collectionId, frameIds) == true);

    public bool DeleteCollection(string collectionId) =>
        Undoable(UndoActions.DeleteCollection, () =>
            document?.DeleteCollection(collectionId) == true);

    /// <summary>
    /// 가상 사본을 만들고 바로 저장합니다. 원본 파일은 그대로이며 카탈로그에만 줄이 늘어납니다.
    /// </summary>
    public string? CreateVirtualCopy(string frameId) =>
        Undoable(UndoActions.VirtualCopy, () => document?.CreateVirtualCopy(frameId));

    /// <summary>한 장으로 접어 둔 사진 묶음입니다.</summary>
    public IReadOnlyList<LibraryStackSnapshot> Stacks => document?.Stacks ?? [];

    public LibraryStackSnapshot? StackFor(string frameId) => document?.StackFor(frameId);

    public string? CreateStack(IEnumerable<string> frameIds) =>
        Undoable(UndoActions.CreateStack, () => document?.CreateStack(frameIds));

    public bool UngroupStack(string stackId) =>
        Undoable(UndoActions.UngroupStack, () => document?.UngroupStack(stackId) == true);

    public bool ToggleStackCollapsed(string stackId) =>
        Undoable(UndoActions.ToggleStack, () =>
            document?.ToggleStackCollapsed(stackId) == true);

    /// <summary>
    /// 사진을 라이브러리에서 빼고 바로 저장합니다. 원본 파일은 그대로 둡니다. 돌려주는 값은
    /// 실제로 빠진 장수입니다.
    /// </summary>
    /// <remarks>
    /// **결함 sidecar 는 지우지 않고 남깁니다.** 되돌리기가 사진을 되살릴 수 있어야 하고,
    /// 되살아난 사진이 결함 편집을 잃으면 그것은 되돌린 것이 아닙니다. 주인이 영영 없는
    /// sidecar 는 아무도 읽지 않는 파일일 뿐입니다.
    /// </remarks>
    public int RemoveFrames(IEnumerable<string> frameIds)
    {
        ArgumentNullException.ThrowIfNull(frameIds);
        if (document is not { } open)
        {
            return 0;
        }
        open.CaptureUndo(UndoActions.RemoveFrames);
        LibraryFrameRemoval removal = open.RemoveFrames(frameIds);
        if (removal.Count == 0)
        {
            // 아무것도 빠지지 않았으면 되돌릴 것도 없습니다.
            _ = open.Undo();
            return 0;
        }
        _ = SaveIfDirty();
        return removal.Count;
    }

    /// <summary>되돌리기·다시 실행에 붙는 이름입니다. 셸이 이 값을 번역해 보여 줍니다.</summary>
    public static class UndoActions
    {
        public const string RemoveFrames = "libraryRemoveFromLibrary";
        public const string CreateCollection = "libraryNewCollection";
        public const string RenameCollection = "libraryRename";
        public const string EditCollection = "libraryAddToCollection";
        public const string DeleteCollection = "libraryDelete";
        public const string VirtualCopy = "libraryVirtualCopy";
        public const string CreateStack = "libraryStackGroup";
        public const string UngroupStack = "libraryStackUngroup";
        public const string ToggleStack = "libraryStackCollapse";
        public const string ResetAdjustments = "commandResetAdjustments";
        public const string DevelopAdjustment = "developAdjustment";

        /// <summary>
        /// GrainMend 편집 한 칸입니다 — macOS <c>recordDefectHistory</c>. 브러시 한 획,
        /// 복제 한 획, 가이드·자동 한 번, 레이어 켜기·강도·삭제, IR 적용이 전부 이 이름으로
        /// 한 칸씩 쌓입니다.
        /// </summary>
        public const string DefectEdit = LibraryDefectEditor.UndoActionName;
    }

    public bool CanUndo => document?.CanUndo == true;

    public bool CanRedo => document?.CanRedo == true;

    public string? UndoActionName => document?.UndoActionName;

    public string? RedoActionName => document?.RedoActionName;

    /// <summary>한 단계 되돌리고 저장합니다. 되돌린 동작의 이름을 돌려줍니다.</summary>
    public string? Undo()
    {
        frameEdits.Clear();
        string? name = document?.Undo();
        if (name is not null)
        {
            _ = SaveIfDirty();
        }
        return name;
    }

    public string? Redo()
    {
        frameEdits.Clear();
        string? name = document?.Redo();
        if (name is not null)
        {
            _ = SaveIfDirty();
        }
        return name;
    }

    private readonly FrameEditHistory frameEdits = new();
    private readonly HashSet<string> infraredCleanAttempted = new(StringComparer.Ordinal);

    /// <summary>macOS <c>runInfraredCleanIfNeeded</c>.</summary>
    public InfraredDefectApplyResult? TryInfraredCleanIfNeeded(string? frameId)
    {
        if (document is null || frameId is null)
        {
            return null;
        }

        LibraryFrameSnapshot? frame = Frames.FirstOrDefault(candidate =>
            string.Equals(candidate.Id, frameId, StringComparison.Ordinal));
        bool attempted = infraredCleanAttempted.Contains(frameId);
        if (!InfraredCleanPolicy.ShouldRun(frame, attempted) || frame is null)
        {
            return null;
        }

        infraredCleanAttempted.Add(frameId);
        if (!DefectSourceIdentityReader.TryRead(frame.SourcePath, out DefectSourceIdentity identity) ||
            frame.InfraredPath is not { } infraredPath)
        {
            if (InfraredCleanPolicy.ShouldRearm(InfraredDefectApplyStatus.DetectionFailed))
            {
                infraredCleanAttempted.Remove(frameId);
            }

            return new InfraredDefectApplyResult(
                InfraredDefectApplyStatus.DetectionFailed,
                null,
                null,
                DefectSidecarError.None,
                CatalogStoreError.None);
        }

        InfraredDefectApplyResult result = InfraredDefectRecipeCoordinator.RunFiles(
            document,
            frame,
            identity,
            frame.SourcePath,
            infraredPath);
        if (InfraredCleanPolicy.ShouldRearm(result.Status))
        {
            infraredCleanAttempted.Remove(frameId);
        }

        return result;
    }

    /// <summary>macOS <c>recordFrameEditIfChanged</c> — <see cref="Edit"/> 길목.</summary>
    private LibraryFrameError AfterCoalescedDevelopEdit(
        string frameId,
        Func<LibraryFrameError> edit)
    {
        if (document is not { } open)
        {
            return LibraryFrameError.MissingId;
        }

        DateTime now = DateTime.UtcNow;
        bool captured = frameEdits.ConsumeCapture(frameId, now);
        if (captured)
        {
            open.CaptureUndo(UndoActions.DevelopAdjustment);
        }

        LibraryFrameError error = edit();
        if (error != LibraryFrameError.None && captured)
        {
            _ = open.Undo();
            return error;
        }

        return AfterEdit(error);
    }

    /// <summary>
    /// 바꾸기 직전 상태를 담고 편집을 돌린 뒤 저장합니다. 편집이 아무것도 바꾸지 않았으면
    /// 담아 둔 상태를 도로 버립니다 — 아무 일도 없었던 편집이 되돌리기 더미를 채우면 Ctrl+Z 가
    /// 헛돕니다.
    /// </summary>
    private T Undoable<T>(string actionName, Func<T> mutate)
    {
        if (document is not { } open)
        {
            return mutate();
        }
        open.CaptureUndo(actionName);
        T result = mutate();
        bool changed = result switch
        {
            bool flag => flag,
            null => false,
            _ => true,
        };
        if (!changed)
        {
            _ = open.Undo();
            return result;
        }
        _ = SaveIfDirty();
        return result;
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
            FrameEdited?.Invoke(this, EventArgs.Empty);
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
        => importer.Import(document, filePaths, process);

    public FolderImportResult ImportFolders(
        IReadOnlyList<string> folderPaths,
        DevelopmentProcess process)
        => importer.ImportFolders(document, folderPaths, process);

    /// <summary>
    /// macOS와 같은 source/folder snapshot을 만듭니다. 작은 library는 즉시 갱신하고, 256개를
    /// 넘으면 UI thread 밖에서 검사한 뒤 아직 같은 document인 경우에만 결과를 반영합니다.
    /// </summary>
    public void RefreshAvailability(Action? onCompleted = null)
        => availability.Refresh(onCompleted);

    /// <summary>
    /// scanner host가 두 artifact를 commit한 뒤 호출하는 publication 경계입니다. RGB record가
    /// catalog에 먼저 durable하게 남은 뒤에만 IR recipe를 써서, 실패가 원본 frame 자체를
    /// 사라지게 하거나 고아 sidecar를 남기지 않게 합니다.
    /// </summary>
    public ScannerFramePublishResult PublishScannerFrame(
        ScannerFrameImport scan,
        InfraredDetectorParameters? parameters = null,
        DevelopRun? run = null) =>
        scannerPublisher.Publish(document, storageRoots, scan, parameters, run);

    public CatalogStoreError Save() => autosave.Save();

    /// <summary>마지막 자동 저장 실패 사유입니다.</summary>
    public CatalogStoreError LastAutomaticSaveError => autosave.LastAutomaticSaveError;

    /// <summary>macOS와 같은 1.5초 debounce 뒤 catalog 저장을 예약합니다.</summary>
    public void ScheduleSave() => autosave.Schedule();

    /// <summary>예약된 저장이 남아 있으면 창을 닫기 전에 즉시 씁니다.</summary>
    public CatalogStoreError SaveIfDirty() => autosave.SaveIfDirty();

    /// <summary>
    /// 고른 사진의 원본을 다른 폴더로 옮기고 카탈로그를 따라가게 합니다. 파일 이동이 실패하면
    /// 카탈로그는 손대지 않습니다 — 없는 자리를 가리키는 사진을 만들지 않기 위해서입니다.
    /// </summary>
    public SourceMoveOutcome MoveSources(
        IReadOnlyList<LibraryFrameSnapshot> frames,
        string destinationFolder)
        => sourceController.Move(document, frames, destinationFolder);

    public LibrarySourceRelinkResult Relink(SourceRelinkPlan plan) =>
        sourceController.Relink(document, plan);

    /// <summary>
    /// 현상해서 파일로 씁니다. 네이티브 호출은 워커 스레드에서 돌고 결과는 dispatcher 를 거쳐
    /// 돌아옵니다. 자세한 계약은 <see cref="DevelopExportCoordinator"/> 를 보십시오.
    /// </summary>
    /// <param name="maximumConcurrent">
    /// 동시에 돌아도 되는 장 수입니다. 배치만 1 보다 큰 값을 넘깁니다 —
    /// <see cref="DevelopExportCoordinator.MaximumConcurrentExports"/>.
    /// </param>
    public Task<bool> ExportAsync(
        LibraryFrameSnapshot frame,
        string destinationPath,
        DevelopExportFormat format,
        Action<DevelopExportOutcome> onCompleted,
        ExportEncodingOptions? encoding = null,
        int maximumConcurrent = 1) =>
        coordinator.StartAsync(
            frame, destinationPath, format, onCompleted, encoding, maximumConcurrent);

    public void Dispose()
    {
        // 놓아 주기 전에 마지막으로 씁니다. 여기서 빠지면 마지막 1.5 초의 편집이 사라집니다.
        _ = SaveIfDirty();
        autosave.Dispose();
        availability.Reset();
        document?.Dispose();
        document = null;
        State = LibraryHostState.NotOpened;
    }

    /// <summary>
    /// 캔버스에서 그은 결함 편집 한 획을 붙이고 sidecar 와 catalog 에 씁니다. 원본을 읽어
    /// identity 를 확인하므로, 파일이 바뀐 사진에는 붙지 않습니다.
    /// </summary>
    public LibraryFrameError AppendDefectStroke(
        string frameId,
        Func<DefectSourceIdentity, DefectRecipeSnapshot?, DefectRecipeSnapshot?> build)
        => LibraryDefectEditor.AppendStroke(document, frameId, build);

    private void SelectSingleFrame(string frameId) => SetSelection([frameId], frameId);

}
