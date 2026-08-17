using System.Text.Json.Nodes;
using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>읽지 못한 frame 하나입니다. 목록에서 조용히 사라지지 않도록 남깁니다.</summary>
public sealed record LibraryFrameIssue(
    int Position,
    string? Id,
    LibraryFrameError Error,
    DevelopRouteError RouteError);

public enum LibraryDocumentError
{
    None,
    SessionBusy,
    SessionUnavailable,
    CatalogUnreadable,
}

public readonly record struct LibraryDocumentOpenResult(
    LibraryDocument? Document,
    LibraryDocumentError Error,
    CatalogSessionError SessionError,
    CatalogStoreError StoreError,
    DefectSidecarError DefectSidecarError)
{
    public bool IsSuccess => Error == LibraryDocumentError.None && Document is not null;

    internal static LibraryDocumentOpenResult Success(LibraryDocument document) =>
        new(document, LibraryDocumentError.None, CatalogSessionError.None,
            CatalogStoreError.None, DefectSidecarError.None);

    internal static LibraryDocumentOpenResult SessionFailure(
        CatalogSessionError error,
        DefectSidecarError defectSidecarError) =>
        new(
            null,
            error == CatalogSessionError.Busy
                ? LibraryDocumentError.SessionBusy
                : LibraryDocumentError.SessionUnavailable,
            error,
            CatalogStoreError.None,
            defectSidecarError);

    internal static LibraryDocumentOpenResult StoreFailure(CatalogStoreError error) =>
        new(
            null,
            LibraryDocumentError.CatalogUnreadable,
            CatalogSessionError.None,
            error,
            DefectSidecarError.None);
}

public readonly record struct LibraryDefectRecipeWriteResult(
    DefectRecipeSnapshot? Recipe,
    LibraryFrameError FrameError,
    DefectSidecarError SidecarError,
    CatalogStoreError CatalogError)
{
    public bool IsSuccess => Recipe is not null &&
        FrameError == LibraryFrameError.None &&
        SidecarError == DefectSidecarError.None &&
        CatalogError == CatalogStoreError.None;
}

public readonly record struct LibrarySourceRelinkResult(
    int UpdatedFrameCount,
    int UpdatedSourceCount,
    int RejectedSourceCount,
    CatalogStoreError CatalogError)
{
    public bool IsSuccess => CatalogError == CatalogStoreError.None;
}

/// <summary>
/// 라이브러리에서 뺀 사진들과, 그와 함께 지워야 할 결함 sidecar 입니다.
/// </summary>
public sealed record LibraryFrameRemoval(
    IReadOnlyList<string> FrameIds,
    IReadOnlyList<(Guid FrameId, ulong Revision)> DefectSidecars)
{
    public int Count => FrameIds.Count;
}

/// <summary>
/// 열려 있는 라이브러리 하나입니다. catalog 세션을 소유하므로 <see cref="Dispose"/> 할 때까지
/// 다른 프로세스는 이 카탈로그의 작성자가 될 수 없습니다.
/// </summary>
/// <remarks>
/// 원본 payload 를 그대로 들고 있다가 저장할 때 그 위에 편집을 얹습니다. 투영된 값만 들고 있으면
/// 이 빌드가 모르는 field 가 저장할 때마다 사라집니다.
/// </remarks>
public sealed class LibraryDocument : IDisposable
{
    private readonly LibraryDocumentState state;
    private readonly LibraryOrganizationService organization;
    private readonly LibraryCatalogPersistence persistence;
    private readonly LibrarySourceRelinker sourceRelinker;
    private readonly LibraryUndoCoordinator undo;
    private readonly LibraryFrameEditor frameEditor;
    private readonly LibraryDefectRecipeStore defectRecipeStore;
    private readonly LibraryFrameRemovalService frameRemoval;
    private readonly LibraryVirtualCopyService virtualCopies;

    private CatalogSession session => state.Session;

    internal LibraryDocument(
        CatalogSession session,
        List<string> rowIds,
        List<JsonObject> payloads,
        Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>> retainedRows,
        string? activeRollId)
    {
        state = new LibraryDocumentState(
            session,
            rowIds,
            payloads,
            retainedRows,
            activeRollId);
        organization = new LibraryOrganizationService(state);
        persistence = new LibraryCatalogPersistence(state);
        sourceRelinker = new LibrarySourceRelinker(state, persistence);
        undo = new LibraryUndoCoordinator(state);
        frameEditor = new LibraryFrameEditor(state);
        defectRecipeStore = new LibraryDefectRecipeStore(state, persistence);
        frameRemoval = new LibraryFrameRemovalService(state);
        virtualCopies = new LibraryVirtualCopyService(state);
    }

    /// <summary>
    /// 마지막 저장 뒤에 바뀐 것이 있는지. 편집은 메모리에서 먼저 일어나므로 이 표시가 없으면
    /// 셸은 무엇을 저장해야 하는지 알 수 없고, 창을 닫을 때 조용히 잃습니다.
    /// </summary>
    public bool IsDirty => state.IsDirty;

    public IReadOnlyList<LibraryFrameSnapshot> Frames => state.Frames;

    public IReadOnlyList<LibraryFolderSnapshot> Folders => state.Folders;

    /// <summary>
    /// 저장된 찾기입니다. 스마트 컬렉션이 먼저, 저장된 검색이 뒤에 옵니다 — macOS 목록과
    /// 같은 차례입니다.
    /// </summary>
    public IReadOnlyList<LibraryStoredSearchSnapshot> StoredSearches => state.StoredSearches;

    /// <summary>필름 롤입니다. 순서는 catalog 의 순서입니다.</summary>
    public IReadOnlyList<LibraryRollSnapshot> Rolls => state.Rolls;

    /// <summary>지금 스캔 중인 롤입니다. catalog 최상위에 macOS 와 같은 키로 삽니다.</summary>
    public string? ActiveRollId => state.ActiveRollId;

    /// <summary>이 frame 이 속한 롤입니다. 어느 롤에도 없으면 null 입니다.</summary>
    public LibraryRollSnapshot? RollFor(string frameId)
        => organization.RollFor(frameId);

    /// <summary>사용자가 손으로 모은 묶음입니다. 순서는 catalog 의 순서입니다.</summary>
    public IReadOnlyList<LibraryCollectionSnapshot> Collections => state.Collections;

    /// <summary>한 장으로 접어 둔 사진 묶음입니다.</summary>
    public IReadOnlyList<LibraryStackSnapshot> Stacks => state.Stacks;

    public bool CanUndo => undo.CanUndo;

    public bool CanRedo => undo.CanRedo;

    /// <summary>되돌릴 동작의 이름입니다. 화면에 그대로 보여 줄 수 있는 문구입니다.</summary>
    public string? UndoActionName => undo.UndoActionName;

    public string? RedoActionName => undo.RedoActionName;

    /// <summary>
    /// 이 편집을 되돌릴 수 있게 지금 상태를 담아 둡니다. **바꾸기 직전에** 불러야 합니다.
    /// </summary>
    /// <remarks>
    /// 담는 것은 카탈로그 상태 전부입니다 — 연산마다 역연산을 쓰면 열 가지 연산이 열 가지 실수
    /// 자리를 만들지만, 상태 복원은 한 자리뿐입니다.
    /// </remarks>
    public void CaptureUndo(string actionName)
        => undo.CaptureUndo(actionName);

    /// <summary>
    /// 한 단계 되돌립니다. 되돌린 동작의 이름을 돌려주며, 되돌릴 것이 없으면 null 입니다.
    /// </summary>
    public string? Undo()
        => undo.Undo();

    public string? Redo()
        => undo.Redo();

    /// <summary>
    /// 이 사진이 든 묶음입니다. 두 묶음에 걸쳐 있으면 null 입니다 — 손상된 카탈로그에서
    /// 어느 쪽을 고를지는 알 수 없고, 아무 쪽이나 고르면 접기·펼치기가 엉뚱한 묶음에 걸립니다.
    /// </summary>
    public LibraryStackSnapshot? StackFor(string frameId)
        => organization.StackFor(frameId);

    /// <summary>
    /// 투영에 실패한 frame 들입니다. **비어 있지 않은데 무시하면 사용자에게는 사진이 사라진
    /// 것으로 보입니다.** 목록에서 빼는 것과 없어진 것은 다릅니다.
    /// </summary>
    public IReadOnlyList<LibraryFrameIssue> Issues => state.Issues;

    public int RecordCount => state.Payloads.Count;

    public static LibraryDocumentOpenResult Open(StorageRootSet roots)
        => LibraryDocumentOpener.Open(roots);

    /// <summary>
    /// 톤과 수동 base 를 갱신합니다. 메모리 안에서만 바뀌며, 디스크로 가려면
    /// <see cref="Save"/> 를 불러야 합니다.
    /// </summary>
    public LibraryFrameError Edit(string frameId, LibraryFrameEdit edit)
        => frameEditor.Edit(frameId, edit);

    /// <summary>
    /// develop route 를 바꿉니다. 필름 룩 선택이 이 경로로 저장됩니다 — recipe 값과 달리
    /// route 는 <see cref="DevelopRouteWriter"/> 가 소유하므로 따로 둡니다.
    /// </summary>
    public LibraryFrameError EditRoute(string frameId, DevelopRouteSelection selection)
        => frameEditor.EditRoute(frameId, selection);

    /// <summary>
    /// frame record 의 복사본입니다. 사이드카가 catalog 에 있는 그대로의 <c>params</c> 를 적기
    /// 위해 씁니다 — 40여 개 필드를 다시 모델링하면 recipe 축이 늘 때마다 사이드카가 조용히
    /// 뒤처집니다.
    /// </summary>
    public System.Text.Json.Nodes.JsonObject? FrameRecord(string frameId)
        => frameEditor.FrameRecord(frameId);

    /// <summary>
    /// frame record 하나를 통째로 바꿉니다. 버전 담기·되돌리기·지우기와 현상 설정 붙여넣기가
    /// 모두 이 자리를 씁니다.
    /// </summary>
    public LibraryFrameError EditFrameRecord(
        string frameId,
        Func<JsonObject, LibraryFrameWriteResult> edit)
        => frameEditor.EditFrameRecord(frameId, edit);

    /// <summary>
    /// 계획된 frame 을 뒤에 덧붙입니다. 메모리 안에서만 바뀌며 <see cref="Save"/> 로 디스크에
    /// 갑니다.
    /// </summary>
    public int Append(IReadOnlyList<CatalogEntityRow> rows)
        => persistence.Append(rows);

    /// <summary>
    /// 새 frame 공개는 catalog write가 실패해도 메모리에만 남은 유령 frame을 만들면 안 됩니다.
    /// append는 끝에만 일어나므로 실패 시 이번 호출이 덧붙인 꼬리만 정확히 되돌릴 수 있습니다.
    /// </summary>
    public CatalogStoreError AppendAndSave(IReadOnlyList<CatalogEntityRow> rows, out int added)
        => persistence.AppendAndSave(rows, out added);

    /// <summary>
    /// source folder 등록과 해당 folder의 frame append를 한 catalog transaction으로 저장합니다.
    /// 저장이 실패하면 메모리 projection도 바꾸지 않습니다.
    /// </summary>
    public CatalogStoreError AppendFoldersAndFramesAndSave(
        IReadOnlyList<LibraryFolderSnapshot> requestedFolders,
        IReadOnlyList<CatalogEntityRow> requestedFrames,
        out int addedFolders,
        out int addedFrames)
        => persistence.AppendFoldersAndFramesAndSave(
            requestedFolders,
            requestedFrames,
            out addedFolders,
            out addedFrames);

    public CatalogStoreError Save()
        => persistence.Save();

    /// <summary>
    /// 원본 위치만 바꾸는 원자적 catalog 갱신입니다. source-bound defect sidecar가 있는 경우
    /// 새 파일의 SHA-256까지 같아야 하므로, 다른 사진을 같은 경로에 연결하지 않습니다.
    /// </summary>
    public LibrarySourceRelinkResult Relink(
        SourceRelinkPlan plan,
        Func<string, LibrarySourceMetadata?>? sourceMetadataReader = null)
        => sourceRelinker.Relink(plan, sourceMetadataReader);

    public LibraryDefectRecipeWriteResult WriteDefectRecipe(
        string frameId,
        DefectRecipeSnapshot recipe)
        => defectRecipeStore.Write(frameId, recipe);

    /// <summary>
    /// 사진을 라이브러리에서 뺍니다. **원본 파일은 건드리지 않습니다** — 목록에서 빼는 것과
    /// 지우는 것은 다릅니다.
    /// </summary>
    /// <remarks>
    /// 프레임 행만 지우면 롤과 묶음에 죽은 id 가 남고, 사용자에게는 "묶음에 5장인데 4장만
    /// 보인다"로 나타납니다. macOS <c>performLibraryRemoval</c> 도 롤·묶음 소속을 같이
    /// 정리하므로 여기서 한 번에 처리합니다. 결함 sidecar 는 프레임이 사라지면 주인이 없으므로
    /// 함께 지우지만, 그것은 catalog 를 저장한 **뒤**여야 합니다 — sidecar 삭제는 catalog 가
    /// 아직 그 사진의 결함 편집을 선언하고 있으면 거부하기 때문입니다. 그래서 여기서는 지울
    /// sidecar 를 알려만 주고, 지우는 것은 <see cref="PurgeDefectSidecars"/> 가 합니다.
    /// </remarks>
    public LibraryFrameRemoval RemoveFrames(IEnumerable<string> frameIds)
        => frameRemoval.Remove(frameIds);

    /// <summary>
    /// 주인이 사라진 결함 sidecar 를 지웁니다. **catalog 를 저장한 뒤에** 불러야 합니다.
    /// </summary>
    /// <remarks>
    /// 라이브러리 제거는 이것을 부르지 <b>않습니다</b>. 되돌리기가 사진을 되살릴 수 있어야 하고,
    /// 되살아난 사진이 결함 편집을 잃으면 되돌린 것이 아니기 때문입니다. 주인이 영영 없어진
    /// sidecar 를 정리해야 할 자리가 생기면 여기를 씁니다.
    /// </remarks>
    public void PurgeDefectSidecars(LibraryFrameRemoval removal)
        => defectRecipeStore.Purge(removal);

    public void Dispose() => session.Dispose();

    /// <summary>
    /// 묶음을 만듭니다. 이름이 비었거나 너무 길면 만들지 않습니다 — 이름 없는 묶음은 목록에서
    /// 고를 수 없습니다.
    /// </summary>
    public string? CreateCollection(string name, IEnumerable<string> frameIds)
        => organization.CreateCollection(name, frameIds);

    public bool RenameCollection(string collectionId, string name)
        => organization.RenameCollection(collectionId, name);

    /// <summary>묶음이 담는 사진을 통째로 바꿉니다. 카탈로그에 없는 id 는 버립니다.</summary>
    public bool SetCollectionFrames(string collectionId, IEnumerable<string> frameIds)
        => organization.SetCollectionFrames(collectionId, frameIds);

    public bool DeleteCollection(string collectionId)
        => organization.DeleteCollection(collectionId);

    /// <summary>
    /// 롤을 만듭니다. 이름이 비면 만들지 않습니다 — 이름 없는 롤은 목록에서 고를 수 없습니다.
    /// </summary>
    public string? CreateRoll(string name, FilmType filmType, IEnumerable<string> frameIds)
        => organization.CreateRoll(name, filmType, frameIds);

    /// <summary>롤 기록을 바꿉니다. 비우면 키 자체를 지웁니다.</summary>
    public bool SetRollRecord(string rollId, RollRecord? record) =>
        organization.SetRollRecord(rollId, record);

    public bool SetRollFrames(string rollId, IEnumerable<string> frameIds)
        => organization.SetRollFrames(rollId, frameIds);

    public bool DeleteRoll(string rollId)
        => organization.DeleteRoll(rollId);

    /// <summary>지금 스캔 중인 롤을 정합니다. 없는 롤은 받지 않습니다.</summary>
    public bool SetActiveRoll(string? rollId)
        => organization.SetActiveRoll(rollId);

    /// <summary>지금 조건을 이름 붙여 담습니다. 이름이 비면 담지 않습니다.</summary>
    public string? CreateStoredSearch(
        string name,
        LibraryStoredSearchKind kind,
        LibraryStoredQuery query)
        => organization.CreateStoredSearch(name, kind, query);

    public bool DeleteStoredSearch(string searchId)
        => organization.DeleteStoredSearch(searchId);

    /// <summary>
    /// 가상 사본을 만듭니다. **원본 파일은 하나 그대로**이고, 카탈로그에만 같은 원본을 가리키는
    /// 줄이 하나 늘어납니다 — 현상만 따로 갈 수 있는 사진입니다.
    /// </summary>
    /// <remarks>
    /// payload 를 통째로 복제합니다. 아는 field 만 옮기면 이 빌드가 모르는 값이 사본에서
    /// 사라져, 원본과 사본의 현상 결과가 갈립니다. 새 줄은 <b>가족의 마지막 뒤</b>에 넣습니다 —
    /// macOS 도 그렇게 하며, 그래야 사본이 원본 옆에 붙어 보입니다.
    /// </remarks>
    public string? CreateVirtualCopy(string frameId)
        => virtualCopies.Create(frameId);

    /// <summary>
    /// 고른 사진들을 한 묶음으로 접습니다. 이미 다른 묶음에 든 사진이 하나라도 있으면 만들지
    /// 않습니다 — 한 사진이 두 묶음에 들면 어느 쪽을 접어야 할지 정할 수 없습니다.
    /// </summary>
    public string? CreateStack(IEnumerable<string> frameIds)
        => organization.CreateStack(frameIds);

    /// <summary>묶음을 풀어 사진들을 각자 돌려보냅니다. 사진 자체는 그대로입니다.</summary>
    public bool UngroupStack(string stackId)
        => organization.UngroupStack(stackId);

    public bool ToggleStackCollapsed(string stackId)
        => organization.ToggleStackCollapsed(stackId);

}
