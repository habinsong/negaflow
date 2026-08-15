using System.Text.Json;
using System.Text.Json.Nodes;
using System.Security.Cryptography;
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
    private readonly CatalogSession session;
    private readonly List<JsonObject> payloads;
    private readonly List<string> rowIds;
    private readonly Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>> retainedRows;
    private readonly List<LibraryFolderSnapshot> folders = [];
    private readonly List<LibraryCollectionSnapshot> collections = [];
    private readonly List<LibraryStackSnapshot> stacks = [];
    private readonly List<LibraryRollSnapshot> rolls = [];
    private readonly List<LibraryStoredSearchSnapshot> storedSearches = [];
    private readonly List<LibraryFrameSnapshot> frames = [];
    private readonly List<LibraryFrameIssue> issues = [];
    private readonly Dictionary<string, int> indexById = new(StringComparer.Ordinal);
    private readonly Dictionary<string, DefectRecipeSnapshot> defectRecipes =
        new(StringComparer.Ordinal);
    private string? activeRollId;

    private LibraryDocument(
        CatalogSession session,
        List<string> rowIds,
        List<JsonObject> payloads,
        Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>> retainedRows,
        string? activeRollId)
    {
        this.session = session;
        this.rowIds = rowIds;
        this.payloads = payloads;
        this.retainedRows = retainedRows;
        this.activeRollId = activeRollId;
        ProjectFolders();
        ProjectCollections();
        ProjectStacks();
        ProjectRolls();
        ProjectStoredSearches();
        Project();
        // 방금 읽은 것은 바뀐 것이 아닙니다.
        IsDirty = false;
    }

    /// <summary>
    /// 마지막 저장 뒤에 바뀐 것이 있는지. 편집은 메모리에서 먼저 일어나므로 이 표시가 없으면
    /// 셸은 무엇을 저장해야 하는지 알 수 없고, 창을 닫을 때 조용히 잃습니다.
    /// </summary>
    public bool IsDirty { get; private set; }

    public IReadOnlyList<LibraryFrameSnapshot> Frames => frames;

    public IReadOnlyList<LibraryFolderSnapshot> Folders => folders;

    /// <summary>
    /// 저장된 찾기입니다. 스마트 컬렉션이 먼저, 저장된 검색이 뒤에 옵니다 — macOS 목록과
    /// 같은 차례입니다.
    /// </summary>
    public IReadOnlyList<LibraryStoredSearchSnapshot> StoredSearches => storedSearches;

    /// <summary>필름 롤입니다. 순서는 catalog 의 순서입니다.</summary>
    public IReadOnlyList<LibraryRollSnapshot> Rolls => rolls;

    /// <summary>지금 스캔 중인 롤입니다. catalog 최상위에 macOS 와 같은 키로 삽니다.</summary>
    public string? ActiveRollId => activeRollId;

    /// <summary>이 frame 이 속한 롤입니다. 어느 롤에도 없으면 null 입니다.</summary>
    public LibraryRollSnapshot? RollFor(string frameId)
    {
        ArgumentNullException.ThrowIfNull(frameId);
        return rolls.FirstOrDefault(roll =>
            roll.FrameIds.Contains(frameId, StringComparer.Ordinal));
    }

    /// <summary>사용자가 손으로 모은 묶음입니다. 순서는 catalog 의 순서입니다.</summary>
    public IReadOnlyList<LibraryCollectionSnapshot> Collections => collections;

    /// <summary>한 장으로 접어 둔 사진 묶음입니다.</summary>
    public IReadOnlyList<LibraryStackSnapshot> Stacks => stacks;

    /// <summary>
    /// 이 사진이 든 묶음입니다. 두 묶음에 걸쳐 있으면 null 입니다 — 손상된 카탈로그에서
    /// 어느 쪽을 고를지는 알 수 없고, 아무 쪽이나 고르면 접기·펼치기가 엉뚱한 묶음에 걸립니다.
    /// </summary>
    public LibraryStackSnapshot? StackFor(string frameId)
    {
        ArgumentNullException.ThrowIfNull(frameId);
        LibraryStackSnapshot? found = null;
        foreach (LibraryStackSnapshot stack in stacks)
        {
            if (!stack.FrameIds.Contains(frameId, StringComparer.Ordinal))
            {
                continue;
            }
            if (found is not null)
            {
                return null;
            }
            found = stack;
        }
        return found;
    }

    /// <summary>
    /// 투영에 실패한 frame 들입니다. **비어 있지 않은데 무시하면 사용자에게는 사진이 사라진
    /// 것으로 보입니다.** 목록에서 빼는 것과 없어진 것은 다릅니다.
    /// </summary>
    public IReadOnlyList<LibraryFrameIssue> Issues => issues;

    public int RecordCount => payloads.Count;

    public static LibraryDocumentOpenResult Open(StorageRootSet roots)
    {
        ArgumentNullException.ThrowIfNull(roots);

        CatalogSessionOpenResult opened = CatalogSession.Open(roots);
        if (opened.Session is not { } session)
        {
            return LibraryDocumentOpenResult.SessionFailure(
                opened.Error,
                opened.DefectSidecarError);
        }

        CatalogReadResult read = session.ReadOrCreate();
        if (read.Snapshot is not { } snapshot)
        {
            session.Dispose();
            return LibraryDocumentOpenResult.StoreFailure(read.Error);
        }

        IReadOnlyList<CatalogEntityRow> rows = snapshot.Rows(CatalogEntityTable.Frames);
        List<string> rowIds = new(rows.Count);
        List<JsonObject> payloads = new(rows.Count);
        foreach (CatalogEntityRow row in rows)
        {
            rowIds.Add(row.Id);
            payloads.Add(row.Payload);
        }

        Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>> retainedRows = [];
        foreach (CatalogEntityTable table in CatalogEntityTables.All)
        {
            if (table == CatalogEntityTable.Frames)
            {
                continue;
            }

            retainedRows[table] = snapshot.Rows(table)
                .Select(row => new CatalogEntityRow(row.Id, (JsonObject)row.Payload.DeepClone()))
                .ToArray();
        }

        return LibraryDocumentOpenResult.Success(
            new LibraryDocument(session, rowIds, payloads, retainedRows, snapshot.ActiveRollId));
    }

    /// <summary>
    /// 톤과 수동 base 를 갱신합니다. 메모리 안에서만 바뀌며, 디스크로 가려면
    /// <see cref="Save"/> 를 불러야 합니다.
    /// </summary>
    public LibraryFrameError Edit(string frameId, LibraryFrameEdit edit)
    {
        ArgumentNullException.ThrowIfNull(frameId);
        ArgumentNullException.ThrowIfNull(edit);

        if (!indexById.TryGetValue(frameId, out int index))
        {
            return LibraryFrameError.MissingId;
        }

        LibraryFrameWriteResult written = LibraryFrameWriter.Apply(payloads[index], edit);
        if (written.FrameRecord is not { } updated)
        {
            return written.Error;
        }

        payloads[index] = updated;
        Project();
        return LibraryFrameError.None;
    }

    /// <summary>
    /// develop route 를 바꿉니다. 필름 룩 선택이 이 경로로 저장됩니다 — recipe 값과 달리
    /// route 는 <see cref="DevelopRouteWriter"/> 가 소유하므로 따로 둡니다.
    /// </summary>
    public LibraryFrameError EditRoute(string frameId, DevelopRouteSelection selection)
    {
        ArgumentNullException.ThrowIfNull(frameId);
        ArgumentNullException.ThrowIfNull(selection);

        if (!indexById.TryGetValue(frameId, out int index))
        {
            return LibraryFrameError.MissingId;
        }

        DevelopRouteWriteResult written = DevelopRouteWriter.Apply(payloads[index], selection);
        if (written.FrameRecord is not { } updated)
        {
            return LibraryFrameError.InvalidDevelopRoute;
        }

        payloads[index] = updated;
        Project();
        return LibraryFrameError.None;
    }

    /// <summary>
    /// frame record 의 복사본입니다. 사이드카가 catalog 에 있는 그대로의 <c>params</c> 를 적기
    /// 위해 씁니다 — 40여 개 필드를 다시 모델링하면 recipe 축이 늘 때마다 사이드카가 조용히
    /// 뒤처집니다.
    /// </summary>
    public System.Text.Json.Nodes.JsonObject? FrameRecord(string frameId)
    {
        ArgumentNullException.ThrowIfNull(frameId);
        return indexById.TryGetValue(frameId, out int index)
            ? payloads[index].DeepClone().AsObject()
            : null;
    }

    /// <summary>
    /// frame record 하나를 통째로 바꿉니다. 버전 담기·되돌리기·지우기와 현상 설정 붙여넣기가
    /// 모두 이 자리를 씁니다.
    /// </summary>
    public LibraryFrameError EditFrameRecord(
        string frameId,
        Func<JsonObject, LibraryFrameWriteResult> edit)
    {
        ArgumentNullException.ThrowIfNull(frameId);
        ArgumentNullException.ThrowIfNull(edit);

        if (!indexById.TryGetValue(frameId, out int index))
        {
            return LibraryFrameError.MissingId;
        }

        LibraryFrameWriteResult written = edit(payloads[index]);
        if (written.FrameRecord is not { } updated)
        {
            return written.Error;
        }

        payloads[index] = updated;
        Project();
        return LibraryFrameError.None;
    }

    /// <summary>
    /// 계획된 frame 을 뒤에 덧붙입니다. 메모리 안에서만 바뀌며 <see cref="Save"/> 로 디스크에
    /// 갑니다.
    /// </summary>
    public int Append(IReadOnlyList<CatalogEntityRow> rows)
    {
        ArgumentNullException.ThrowIfNull(rows);
        int added = 0;
        foreach (CatalogEntityRow row in rows)
        {
            if (rowIds.Contains(row.Id))
            {
                continue;
            }
            rowIds.Add(row.Id);
            payloads.Add(row.Payload);
            ++added;
        }
        if (added > 0)
        {
            Project();
        }
        return added;
    }

    /// <summary>
    /// 새 frame 공개는 catalog write가 실패해도 메모리에만 남은 유령 frame을 만들면 안 됩니다.
    /// append는 끝에만 일어나므로 실패 시 이번 호출이 덧붙인 꼬리만 정확히 되돌릴 수 있습니다.
    /// </summary>
    public CatalogStoreError AppendAndSave(IReadOnlyList<CatalogEntityRow> rows, out int added)
    {
        return AppendFoldersAndFramesAndSave([], rows, out _, out added);
    }

    /// <summary>
    /// source folder 등록과 해당 folder의 frame append를 한 catalog transaction으로 저장합니다.
    /// 저장이 실패하면 메모리 projection도 바꾸지 않습니다.
    /// </summary>
    public CatalogStoreError AppendFoldersAndFramesAndSave(
        IReadOnlyList<LibraryFolderSnapshot> requestedFolders,
        IReadOnlyList<CatalogEntityRow> requestedFrames,
        out int addedFolders,
        out int addedFrames)
    {
        ArgumentNullException.ThrowIfNull(requestedFolders);
        ArgumentNullException.ThrowIfNull(requestedFrames);

        List<CatalogEntityRow> candidateFrames = FrameRows();
        HashSet<string> frameIds = new(rowIds, StringComparer.Ordinal);
        addedFrames = 0;
        foreach (CatalogEntityRow row in requestedFrames)
        {
            if (!frameIds.Add(row.Id))
            {
                continue;
            }
            candidateFrames.Add(row);
            ++addedFrames;
        }

        List<CatalogEntityRow> candidateFolders = retainedRows[CatalogEntityTable.Folders].ToList();
        HashSet<string> folderPaths = new(
            folders.Select(folder => folder.SourcePath),
            StringComparer.OrdinalIgnoreCase);
        addedFolders = 0;
        foreach (LibraryFolderSnapshot folder in requestedFolders)
        {
            if (!LibraryFolderRecord.TryNormalizePath(folder.SourcePath, out string normalized) ||
                !folderPaths.Add(normalized))
            {
                continue;
            }

            candidateFolders.Add(LibraryFolderRecord.Write(folder with { SourcePath = normalized }));
            ++addedFolders;
        }

        if (addedFrames == 0 && addedFolders == 0)
        {
            return CatalogStoreError.None;
        }

        CatalogStoreError save = session.Write(CreateSnapshot(candidateFrames, candidateFolders)).Error;
        if (save != CatalogStoreError.None)
        {
            addedFolders = 0;
            addedFrames = 0;
            return save;
        }

        if (addedFrames > 0)
        {
            rowIds.Clear();
            payloads.Clear();
            foreach (CatalogEntityRow row in candidateFrames)
            {
                rowIds.Add(row.Id);
                payloads.Add(row.Payload);
            }
            Project();
        }
        if (addedFolders > 0)
        {
            retainedRows[CatalogEntityTable.Folders] = candidateFolders;
            ProjectFolders();
        }
        return CatalogStoreError.None;
    }

    public CatalogStoreError Save()
    {
        CatalogStoreError error = session.Write(CreateSnapshot(FrameRows())).Error;
        if (error == CatalogStoreError.None)
        {
            IsDirty = false;
        }
        return error;
    }

    /// <summary>
    /// 원본 위치만 바꾸는 원자적 catalog 갱신입니다. source-bound defect sidecar가 있는 경우
    /// 새 파일의 SHA-256까지 같아야 하므로, 다른 사진을 같은 경로에 연결하지 않습니다.
    /// </summary>
    public LibrarySourceRelinkResult Relink(
        SourceRelinkPlan plan,
        Func<string, LibrarySourceMetadata?>? sourceMetadataReader = null)
    {
        ArgumentNullException.ThrowIfNull(plan);
        Dictionary<string, string> mappings = new(StringComparer.OrdinalIgnoreCase);
        foreach (SourceRelinkMapping mapping in plan.Mappings)
        {
            if (!TryNormalizePath(mapping.OldSourcePath, out string oldPath) ||
                !TryNormalizePath(mapping.NewSourcePath, out string newPath) ||
                !File.Exists(newPath) ||
                !mappings.TryAdd(oldPath, newPath))
            {
                continue;
            }
        }
        List<JsonObject> previousPayloads = payloads.Select(payload => payload).ToList();
        IReadOnlyList<CatalogEntityRow> previousFolderRows = CloneRows(
            retainedRows[CatalogEntityTable.Folders]);
        int requestedSourceCount = mappings.Count;
        int updatedFrames = 0;
        int updatedSources = 0;
        int rejectedSources = 0;
        HashSet<string> processed = new(StringComparer.OrdinalIgnoreCase);
        foreach (LibraryFrameSnapshot frame in frames)
        {
            if (!TryNormalizePath(frame.SourcePath, out string oldPath) ||
                !mappings.TryGetValue(oldPath, out string? newPath) ||
                newPath is null || !CanReadFile(newPath))
            {
                continue;
            }
            if (processed.Add(oldPath))
            {
                LibrarySourceMetadata? actualMetadata = null;
                foreach (LibraryFrameSnapshot familyFrame in frames)
                {
                    if (!TryNormalizePath(familyFrame.SourcePath, out string familyPath) ||
                        !string.Equals(familyPath, oldPath, StringComparison.OrdinalIgnoreCase) ||
                        familyFrame.SourceMetadata is not { } expectedMetadata)
                    {
                        continue;
                    }
                    actualMetadata ??= sourceMetadataReader?.Invoke(newPath);
                    if (actualMetadata is null || !expectedMetadata.IsCompatibleWith(actualMetadata.Value))
                    {
                        mappings.Remove(oldPath);
                        ++rejectedSources;
                        break;
                    }
                }
                if (!mappings.ContainsKey(oldPath))
                {
                    continue;
                }
                DefectSourceIdentity? actual = null;
                foreach (LibraryFrameSnapshot familyFrame in frames)
                {
                    if (!TryNormalizePath(familyFrame.SourcePath, out string familyPath) ||
                        !string.Equals(familyPath, oldPath, StringComparison.OrdinalIgnoreCase) ||
                        familyFrame.DefectRecipe?.SourceIdentity is not { } identity)
                    {
                        continue;
                    }
                    if (actual is null &&
                        (!TryReadSourceIdentity(newPath, out DefectSourceIdentity measured) ||
                         measured != identity))
                    {
                        mappings.Remove(oldPath);
                        ++rejectedSources;
                        break;
                    }
                    actual ??= identity;
                    if (actual != identity)
                    {
                        mappings.Remove(oldPath);
                        ++rejectedSources;
                        break;
                    }
                }
                if (!mappings.ContainsKey(oldPath))
                {
                    continue;
                }
                ++updatedSources;
            }
            if (!mappings.ContainsKey(oldPath) || !indexById.TryGetValue(frame.Id, out int index))
            {
                continue;
            }

            string? infrared = SourceRelinkPlanner.RelocateCompanion(frame.InfraredPath, plan);
            if (infrared is not null && PathsEqual(newPath, infrared))
            {
                ++rejectedSources;
                continue;
            }
            JsonObject updated = (JsonObject)payloads[index].DeepClone();
            updated[LibraryFrameReader.SourcePathName] = newPath;
            if (infrared is not null)
            {
                updated[LibraryFrameReader.InfraredPathName] = infrared;
            }
            payloads[index] = updated;
            ++updatedFrames;
        }
        rejectedSources += plan.Mappings.Count - updatedSources - rejectedSources;
        bool updatedFolder = RebaseRegisteredFolder(
            plan,
            allMappingsApplied: updatedSources == requestedSourceCount);
        if (updatedFrames == 0 && !updatedFolder)
        {
            return new(0, 0, Math.Max(0, rejectedSources), CatalogStoreError.None);
        }

        ProjectFolders();
        Project();
        CatalogStoreError saved = Save();
        if (saved == CatalogStoreError.None)
        {
            return new(updatedFrames, updatedSources, Math.Max(0, rejectedSources), saved);
        }
        payloads.Clear();
        payloads.AddRange(previousPayloads);
        retainedRows[CatalogEntityTable.Folders] = previousFolderRows;
        ProjectFolders();
        Project();
        return new(0, 0, Math.Max(0, rejectedSources), saved);
    }

    public LibraryDefectRecipeWriteResult WriteDefectRecipe(
        string frameId,
        DefectRecipeSnapshot recipe)
    {
        ArgumentNullException.ThrowIfNull(frameId);
        ArgumentNullException.ThrowIfNull(recipe);
        if (!indexById.TryGetValue(frameId, out int index) ||
            !Guid.TryParseExact(frameId, "D", out Guid parsedFrameId) ||
            parsedFrameId != recipe.FrameId)
        {
            return new(null, LibraryFrameError.MissingId,
                DefectSidecarError.None, CatalogStoreError.None);
        }

        DefectSidecarWriteResult sidecar = session.WriteDefectRecipe(recipe);
        if (!sidecar.IsSuccess)
        {
            return new(null, LibraryFrameError.None, sidecar.Error, CatalogStoreError.None);
        }
        DefectSidecarReadResult read = session.ReadDefectRecipe(parsedFrameId);
        if (read.Snapshot is not { } stored)
        {
            return new(null, LibraryFrameError.None, read.Error, CatalogStoreError.None);
        }

        JsonObject previousPayload = payloads[index];
        DefectRecipeSnapshot? previousRecipe = defectRecipes.GetValueOrDefault(frameId);
        JsonObject updatedPayload = (JsonObject)previousPayload.DeepClone();
        updatedPayload["hasDefectEdits"] = true;
        payloads[index] = updatedPayload;
        defectRecipes[frameId] = stored;
        CatalogStoreError catalogError = Save();
        if (catalogError != CatalogStoreError.None)
        {
            payloads[index] = previousPayload;
            if (previousRecipe is null)
            {
                defectRecipes.Remove(frameId);
            }
            else
            {
                defectRecipes[frameId] = previousRecipe;
            }
            Project();
            return new(null, LibraryFrameError.None,
                DefectSidecarError.None, catalogError);
        }

        Project();
        return new(stored, LibraryFrameError.None,
            DefectSidecarError.None, CatalogStoreError.None);
    }

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
    {
        ArgumentNullException.ThrowIfNull(frameIds);
        var removing = new HashSet<string>(KnownFrameIds(frameIds), StringComparer.Ordinal);
        if (removing.Count == 0)
        {
            return new LibraryFrameRemoval([], []);
        }

        var sidecars = new List<(Guid FrameId, ulong Revision)>();
        for (int index = payloads.Count - 1; index >= 0; index--)
        {
            if (!removing.Contains(rowIds[index]))
            {
                continue;
            }
            if (defectRecipes.Remove(rowIds[index], out DefectRecipeSnapshot? recipe) &&
                Guid.TryParseExact(rowIds[index], "D", out Guid sidecarId))
            {
                sidecars.Add((sidecarId, recipe.RecipeRevision));
            }
            payloads.RemoveAt(index);
            rowIds.RemoveAt(index);
        }

        DropMembership(CatalogEntityTable.Rolls, removing);
        DropMembership(CatalogEntityTable.ManualCollections, removing);
        DropMembership(CatalogEntityTable.Stacks, removing);
        // 한 장만 남은 묶음은 접어도 아무것도 감추지 않으면서 배지만 남깁니다. 없앱니다.
        retainedRows[CatalogEntityTable.Stacks] =
            [.. retainedRows[CatalogEntityTable.Stacks].Where(row =>
                LibraryStackRecord.TryRead(row, out _))];
        ProjectRolls();
        ProjectCollections();
        ProjectStacks();
        Project();
        return new LibraryFrameRemoval([.. removing], sidecars);
    }

    /// <summary>
    /// 주인이 사라진 결함 sidecar 를 지웁니다. **catalog 를 저장한 뒤에** 불러야 합니다.
    /// 실패해도 아무 말 하지 않습니다 — 남은 파일은 아무도 읽지 않지만, 여기서 제거를
    /// 되돌리면 사용자가 지운 사진이 되살아납니다.
    /// </summary>
    public void PurgeDefectSidecars(LibraryFrameRemoval removal)
    {
        ArgumentNullException.ThrowIfNull(removal);
        foreach ((Guid frameId, ulong revision) in removal.DefectSidecars)
        {
            // revision 은 "이보다 낮은 판은 다시 쓰지 말라"는 바닥값입니다. 지금 판보다 하나
            // 위를 주어야 지우는 사이에 날아든 옛 저장이 sidecar 를 되살리지 못합니다.
            _ = session.RemoveDefectRecipe(frameId, revision + 1);
        }
    }

    /// <summary>
    /// 롤과 묶음의 구성원 목록에서 사라진 id 를 뺍니다. 두 표는 같은 <c>frameIDs</c> 배열
    /// 모양을 쓰므로 한 함수로 다룹니다.
    /// </summary>
    private void DropMembership(CatalogEntityTable table, HashSet<string> removing)
    {
        List<CatalogEntityRow> rows = [.. retainedRows[table]];
        bool changed = false;
        for (int index = 0; index < rows.Count; index++)
        {
            if (rows[index].Payload["frameIDs"] is not JsonArray members)
            {
                continue;
            }
            var kept = new JsonArray();
            bool dropped = false;
            foreach (JsonNode? member in members)
            {
                if (member?.GetValue<string>() is { } frameId && removing.Contains(frameId))
                {
                    dropped = true;
                    continue;
                }
                kept.Add(member?.DeepClone());
            }
            if (!dropped)
            {
                continue;
            }
            JsonObject payload = (JsonObject)rows[index].Payload.DeepClone();
            payload["frameIDs"] = kept;
            rows[index] = new CatalogEntityRow(rows[index].Id, payload);
            changed = true;
        }
        if (changed)
        {
            retainedRows[table] = rows;
        }
    }

    public void Dispose() => session.Dispose();

    private void Project()
    {
        // 모든 변경이 이 자리를 지나므로, 여기서 표시하면 놓치는 편집이 없습니다.
        IsDirty = true;
        frames.Clear();
        issues.Clear();
        indexById.Clear();

        for (int index = 0; index < payloads.Count; index++)
        {
            using JsonDocument document = JsonDocument.Parse(
                CatalogJson.SerializeCanonical(payloads[index]));
            LibraryFrameReadResult read = LibraryFrameReader.Read(document.RootElement);
            if (read.Frame is { } frame)
            {
                if (DeclaresDefectEdits(payloads[index]))
                {
                    if (!defectRecipes.TryGetValue(rowIds[index], out var recipe))
                    {
                        if (!Guid.TryParseExact(rowIds[index], "D", out Guid frameId) ||
                            session.ReadDefectRecipe(frameId).Snapshot is not { } loadedRecipe)
                        {
                            issues.Add(new LibraryFrameIssue(
                                index,
                                rowIds[index],
                                LibraryFrameError.InvalidDefectRecipe,
                                DevelopRouteError.None));
                            continue;
                        }
                        recipe = loadedRecipe;
                        defectRecipes[rowIds[index]] = recipe;
                    }
                    frame = frame with { DefectRecipe = recipe };
                }
                else
                {
                    defectRecipes.Remove(rowIds[index]);
                }
                frames.Add(frame);
                indexById[frame.Id] = index;
                continue;
            }
            issues.Add(new LibraryFrameIssue(
                index,
                rowIds[index],
                read.Error,
                read.RouteError));
        }
    }

    /// <summary>
    /// 묶음을 만듭니다. 이름이 비었거나 너무 길면 만들지 않습니다 — 이름 없는 묶음은 목록에서
    /// 고를 수 없습니다.
    /// </summary>
    public string? CreateCollection(string name, IEnumerable<string> frameIds)
    {
        ArgumentNullException.ThrowIfNull(frameIds);
        if (LibraryCollectionSnapshot.NormalizeName(name) is not { } normalized)
        {
            return null;
        }
        LibraryCollectionSnapshot created = new(
            Guid.NewGuid().ToString("D"),
            normalized,
            KnownFrameIds(frameIds));
        List<CatalogEntityRow> rows = [.. retainedRows[CatalogEntityTable.ManualCollections]];
        rows.Add(LibraryCollectionRecord.Write(created));
        retainedRows[CatalogEntityTable.ManualCollections] = rows;
        ProjectCollections();
        return created.Id;
    }

    public bool RenameCollection(string collectionId, string name)
    {
        if (LibraryCollectionSnapshot.NormalizeName(name) is not { } normalized)
        {
            return false;
        }
        return ReplaceCollection(
            collectionId,
            existing => existing with { Name = normalized });
    }

    /// <summary>묶음이 담는 사진을 통째로 바꿉니다. 카탈로그에 없는 id 는 버립니다.</summary>
    public bool SetCollectionFrames(string collectionId, IEnumerable<string> frameIds)
    {
        ArgumentNullException.ThrowIfNull(frameIds);
        IReadOnlyList<string> known = KnownFrameIds(frameIds);
        return ReplaceCollection(collectionId, existing => existing with { FrameIds = known });
    }

    public bool DeleteCollection(string collectionId)
    {
        ArgumentException.ThrowIfNullOrEmpty(collectionId);
        List<CatalogEntityRow> rows = [.. retainedRows[CatalogEntityTable.ManualCollections]];
        int removed = rows.RemoveAll(row =>
            string.Equals(row.Id, collectionId, StringComparison.Ordinal));
        if (removed == 0)
        {
            return false;
        }
        retainedRows[CatalogEntityTable.ManualCollections] = rows;
        ProjectCollections();
        return true;
    }

    private bool ReplaceCollection(
        string collectionId,
        Func<LibraryCollectionSnapshot, LibraryCollectionSnapshot> update)
    {
        ArgumentException.ThrowIfNullOrEmpty(collectionId);
        List<CatalogEntityRow> rows = [.. retainedRows[CatalogEntityTable.ManualCollections]];
        for (int index = 0; index < rows.Count; ++index)
        {
            if (!string.Equals(rows[index].Id, collectionId, StringComparison.Ordinal) ||
                !LibraryCollectionRecord.TryRead(
                    rows[index],
                    out LibraryCollectionSnapshot existing))
            {
                continue;
            }
            rows[index] = LibraryCollectionRecord.Write(update(existing));
            retainedRows[CatalogEntityTable.ManualCollections] = rows;
            ProjectCollections();
            return true;
        }
        return false;
    }

    /// <summary>카탈로그에 실제로 있는 frame 만, 준 순서대로, 중복 없이 남깁니다.</summary>
    private IReadOnlyList<string> KnownFrameIds(IEnumerable<string> frameIds)
    {
        var seen = new HashSet<string>(StringComparer.Ordinal);
        return [.. frameIds.Where(id => indexById.ContainsKey(id) && seen.Add(id))];
    }

    /// <summary>
    /// 롤을 만듭니다. 이름이 비면 만들지 않습니다 — 이름 없는 롤은 목록에서 고를 수 없습니다.
    /// </summary>
    public string? CreateRoll(string name, FilmType filmType, IEnumerable<string> frameIds)
    {
        ArgumentNullException.ThrowIfNull(frameIds);
        if (AppMetadataOverlay.NormalizeText(name) is not { } normalized)
        {
            return null;
        }
        LibraryRollSnapshot created = new(
            Guid.NewGuid().ToString("D"),
            LibraryRollKind.Physical,
            normalized,
            DateTimeOffset.UtcNow,
            filmType,
            KnownFrameIds(frameIds),
            null);
        List<CatalogEntityRow> rows = [.. retainedRows[CatalogEntityTable.Rolls]];
        rows.Add(LibraryRollRecordCodec.Write(created));
        retainedRows[CatalogEntityTable.Rolls] = rows;
        ProjectRolls();
        return created.Id;
    }

    /// <summary>롤 기록을 바꿉니다. 비우면 키 자체를 지웁니다.</summary>
    public bool SetRollRecord(string rollId, RollRecord? record) =>
        ReplaceRoll(rollId, existing => existing with
        {
            Record = record is { } value && !value.Normalized().IsEmpty
                ? value.Normalized()
                : null,
        });

    public bool SetRollFrames(string rollId, IEnumerable<string> frameIds)
    {
        ArgumentNullException.ThrowIfNull(frameIds);
        IReadOnlyList<string> known = KnownFrameIds(frameIds);
        return ReplaceRoll(rollId, existing => existing with { FrameIds = known });
    }

    public bool DeleteRoll(string rollId)
    {
        ArgumentException.ThrowIfNullOrEmpty(rollId);
        List<CatalogEntityRow> rows = [.. retainedRows[CatalogEntityTable.Rolls]];
        if (rows.RemoveAll(row =>
                string.Equals(row.Id, rollId, StringComparison.Ordinal)) == 0)
        {
            return false;
        }
        retainedRows[CatalogEntityTable.Rolls] = rows;
        if (string.Equals(activeRollId, rollId, StringComparison.Ordinal))
        {
            activeRollId = null;
        }
        ProjectRolls();
        return true;
    }

    /// <summary>지금 스캔 중인 롤을 정합니다. 없는 롤은 받지 않습니다.</summary>
    public bool SetActiveRoll(string? rollId)
    {
        if (rollId is not null &&
            !rolls.Any(roll => string.Equals(roll.Id, rollId, StringComparison.Ordinal)))
        {
            return false;
        }
        if (string.Equals(activeRollId, rollId, StringComparison.Ordinal))
        {
            return true;
        }
        activeRollId = rollId;
        IsDirty = true;
        return true;
    }

    private bool ReplaceRoll(
        string rollId,
        Func<LibraryRollSnapshot, LibraryRollSnapshot> update)
    {
        ArgumentException.ThrowIfNullOrEmpty(rollId);
        List<CatalogEntityRow> rows = [.. retainedRows[CatalogEntityTable.Rolls]];
        for (int index = 0; index < rows.Count; ++index)
        {
            if (!string.Equals(rows[index].Id, rollId, StringComparison.Ordinal) ||
                !LibraryRollRecordCodec.TryRead(rows[index], out LibraryRollSnapshot existing))
            {
                continue;
            }
            rows[index] = LibraryRollRecordCodec.Write(update(existing));
            retainedRows[CatalogEntityTable.Rolls] = rows;
            ProjectRolls();
            return true;
        }
        return false;
    }

    /// <summary>지금 조건을 이름 붙여 담습니다. 이름이 비면 담지 않습니다.</summary>
    public string? CreateStoredSearch(
        string name,
        LibraryStoredSearchKind kind,
        LibraryStoredQuery query)
    {
        ArgumentNullException.ThrowIfNull(query);
        if (LibraryCollectionSnapshot.NormalizeName(name) is not { } normalized)
        {
            return null;
        }
        LibraryStoredSearchSnapshot created = new(
            Guid.NewGuid().ToString("D"),
            normalized,
            kind,
            query);
        if (LibraryStoredSearchRecord.Write(created) is not { } row)
        {
            return null;
        }
        CatalogEntityTable table = TableFor(kind);
        retainedRows[table] = [.. retainedRows[table], row];
        ProjectStoredSearches();
        return created.Id;
    }

    public bool DeleteStoredSearch(string searchId)
    {
        ArgumentException.ThrowIfNullOrEmpty(searchId);
        bool removed = false;
        foreach (CatalogEntityTable table in new[]
        {
            CatalogEntityTable.SmartCollections,
            CatalogEntityTable.SavedSearches,
        })
        {
            List<CatalogEntityRow> rows = [.. retainedRows[table]];
            if (rows.RemoveAll(row =>
                    string.Equals(row.Id, searchId, StringComparison.Ordinal)) > 0)
            {
                retainedRows[table] = rows;
                removed = true;
            }
        }
        if (removed)
        {
            ProjectStoredSearches();
        }
        return removed;
    }

    private static CatalogEntityTable TableFor(LibraryStoredSearchKind kind) =>
        kind == LibraryStoredSearchKind.SmartCollection
            ? CatalogEntityTable.SmartCollections
            : CatalogEntityTable.SavedSearches;

    private void ProjectStoredSearches()
    {
        IsDirty = true;
        storedSearches.Clear();
        foreach ((CatalogEntityTable table, LibraryStoredSearchKind kind) in new[]
        {
            (CatalogEntityTable.SmartCollections, LibraryStoredSearchKind.SmartCollection),
            (CatalogEntityTable.SavedSearches, LibraryStoredSearchKind.SavedSearch),
        })
        {
            foreach (CatalogEntityRow row in retainedRows[table])
            {
                if (LibraryStoredSearchRecord.TryRead(
                        row,
                        kind,
                        out LibraryStoredSearchSnapshot search))
                {
                    storedSearches.Add(search);
                }
            }
        }
    }

    private void ProjectRolls()
    {
        IsDirty = true;
        rolls.Clear();
        foreach (CatalogEntityRow row in retainedRows[CatalogEntityTable.Rolls])
        {
            if (LibraryRollRecordCodec.TryRead(row, out LibraryRollSnapshot roll))
            {
                rolls.Add(roll);
            }
        }
    }

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
    {
        ArgumentNullException.ThrowIfNull(frameId);
        if (!indexById.TryGetValue(frameId, out int index))
        {
            return null;
        }
        LibraryFrameSnapshot source = frames.First(frame => frame.Id == frameId);
        string rootId = source.RootFrameId;

        int lastFamilyIndex = index;
        int nextNumber = 1;
        for (int candidate = 0; candidate < frames.Count; candidate++)
        {
            if (frames[candidate].RootFrameId != rootId)
            {
                continue;
            }
            lastFamilyIndex = indexById[frames[candidate].Id];
            if (frames[candidate].VirtualCopyNumber is { } number && number >= nextNumber)
            {
                nextNumber = number + 1;
            }
        }

        string copyId = Guid.NewGuid().ToString("D");
        // 사본이 물려받는 것은 **뿌리의 이름**입니다. 원본 이름을 나중에 바꿔도 이미 만든 사본의
        // 이름은 그대로 남습니다 — macOS 도 만들 때 한 번 적습니다.
        JsonObject copy = LibraryFrameWriter.MakeVirtualCopy(
            payloads[index],
            copyId,
            rootId,
            nextNumber,
            LibraryFrameNaming.DisplayName(source));

        payloads.Insert(lastFamilyIndex + 1, copy);
        rowIds.Insert(lastFamilyIndex + 1, copyId);

        // 결함 편집은 물려받되 sidecar 는 **각자의 파일**이어야 합니다. 하나를 지우는 것이
        // 다른 하나를 깨뜨리면 안 됩니다. payload 에 hasDefectEdits 가 복제되어 왔으므로,
        // 사본 몫의 sidecar 를 지금 만들지 않으면 투영이 그 사진을 읽지 못해 목록에서
        // 사라집니다.
        if (defectRecipes.TryGetValue(frameId, out DefectRecipeSnapshot? recipe) &&
            Guid.TryParseExact(copyId, "D", out Guid copyGuid))
        {
            DefectRecipeSnapshot copied = DefectRecipeSnapshot.Create(
                copyGuid,
                recipe.RecipeRevision,
                recipe.SourceIdentity,
                recipe.Items);
            if (session.WriteDefectRecipe(copied).IsSuccess)
            {
                defectRecipes[copyId] = copied;
            }
            else
            {
                // sidecar 를 못 만들면 사본은 결함 편집 없이 시작합니다. 읽을 수 없는 사진을
                // 목록에 남기는 것보다 낫습니다.
                copy.Remove("hasDefectEdits");
            }
        }
        Project();
        return copyId;
    }

    /// <summary>
    /// 고른 사진들을 한 묶음으로 접습니다. 이미 다른 묶음에 든 사진이 하나라도 있으면 만들지
    /// 않습니다 — 한 사진이 두 묶음에 들면 어느 쪽을 접어야 할지 정할 수 없습니다.
    /// </summary>
    public string? CreateStack(IEnumerable<string> frameIds)
    {
        ArgumentNullException.ThrowIfNull(frameIds);
        IReadOnlyList<string> known = KnownFrameIds(frameIds);
        if (known.Any(frameId => StackFor(frameId) is not null))
        {
            return null;
        }
        string id = Guid.NewGuid().ToString("D");
        if (LibraryStackSnapshot.TryCreate(id, known, isCollapsed: true) is not { } created)
        {
            return null;
        }
        List<CatalogEntityRow> rows = [.. retainedRows[CatalogEntityTable.Stacks]];
        rows.Add(LibraryStackRecord.Write(created));
        retainedRows[CatalogEntityTable.Stacks] = rows;
        ProjectStacks();
        return id;
    }

    /// <summary>묶음을 풀어 사진들을 각자 돌려보냅니다. 사진 자체는 그대로입니다.</summary>
    public bool UngroupStack(string stackId)
    {
        ArgumentException.ThrowIfNullOrEmpty(stackId);
        List<CatalogEntityRow> rows = [.. retainedRows[CatalogEntityTable.Stacks]];
        if (rows.RemoveAll(row =>
                string.Equals(row.Id, stackId, StringComparison.Ordinal)) == 0)
        {
            return false;
        }
        retainedRows[CatalogEntityTable.Stacks] = rows;
        ProjectStacks();
        return true;
    }

    public bool ToggleStackCollapsed(string stackId)
    {
        ArgumentException.ThrowIfNullOrEmpty(stackId);
        List<CatalogEntityRow> rows = [.. retainedRows[CatalogEntityTable.Stacks]];
        for (int index = 0; index < rows.Count; index++)
        {
            if (!string.Equals(rows[index].Id, stackId, StringComparison.Ordinal) ||
                !LibraryStackRecord.TryRead(rows[index], out LibraryStackSnapshot existing))
            {
                continue;
            }
            rows[index] = LibraryStackRecord.Write(
                existing with { IsCollapsed = !existing.IsCollapsed });
            retainedRows[CatalogEntityTable.Stacks] = rows;
            ProjectStacks();
            return true;
        }
        return false;
    }

    private void ProjectStacks()
    {
        IsDirty = true;
        stacks.Clear();
        foreach (CatalogEntityRow row in retainedRows[CatalogEntityTable.Stacks])
        {
            if (LibraryStackRecord.TryRead(row, out LibraryStackSnapshot stack))
            {
                stacks.Add(stack);
            }
        }
    }

    private void ProjectCollections()
    {
        IsDirty = true;
        collections.Clear();
        foreach (CatalogEntityRow row in retainedRows[CatalogEntityTable.ManualCollections])
        {
            if (LibraryCollectionRecord.TryRead(row, out LibraryCollectionSnapshot collection))
            {
                collections.Add(collection);
            }
        }
    }

    private void ProjectFolders()
    {
        IsDirty = true;
        folders.Clear();
        HashSet<string> seenPaths = new(StringComparer.OrdinalIgnoreCase);
        foreach (CatalogEntityRow row in retainedRows[CatalogEntityTable.Folders])
        {
            if (LibraryFolderRecord.TryRead(row, out LibraryFolderSnapshot folder) &&
                seenPaths.Add(folder.SourcePath))
            {
                folders.Add(folder);
            }
        }
    }

    private List<CatalogEntityRow> FrameRows()
    {
        List<CatalogEntityRow> rows = new(payloads.Count);
        for (int index = 0; index < payloads.Count; index++)
        {
            rows.Add(new CatalogEntityRow(rowIds[index], payloads[index]));
        }
        return rows;
    }

    private bool RebaseRegisteredFolder(
        SourceRelinkPlan plan,
        bool allMappingsApplied)
    {
        if (!plan.IsComplete || !allMappingsApplied ||
            !LibraryFolderRecord.TryNormalizePath(plan.OldFolderPath, out string oldRoot) ||
            !LibraryFolderRecord.TryNormalizePath(plan.NewFolderPath, out string newRoot))
        {
            return false;
        }

        List<CatalogEntityRow> updatedRows = [];
        bool changed = false;
        foreach (CatalogEntityRow row in retainedRows[CatalogEntityTable.Folders])
        {
            if (LibraryFolderRecord.TryRead(row, out LibraryFolderSnapshot folder) &&
                string.Equals(folder.SourcePath, oldRoot, StringComparison.OrdinalIgnoreCase))
            {
                updatedRows.Add(LibraryFolderRecord.Write(folder with { SourcePath = newRoot }));
                changed = true;
            }
            else
            {
                updatedRows.Add(new CatalogEntityRow(row.Id, (JsonObject)row.Payload.DeepClone()));
            }
        }

        if (changed)
        {
            retainedRows[CatalogEntityTable.Folders] = updatedRows;
        }
        return changed;
    }

    private static IReadOnlyList<CatalogEntityRow> CloneRows(
        IReadOnlyList<CatalogEntityRow> rows) => rows
        .Select(row => new CatalogEntityRow(row.Id, (JsonObject)row.Payload.DeepClone()))
        .ToArray();

    private CatalogSnapshot CreateSnapshot(
        IReadOnlyList<CatalogEntityRow> frameRows,
        IReadOnlyList<CatalogEntityRow>? folderRows = null)
    {
        Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>> tables = new(retainedRows)
        {
            [CatalogEntityTable.Frames] = frameRows,
        };
        if (folderRows is not null)
        {
            tables[CatalogEntityTable.Folders] = folderRows;
        }
        return new CatalogSnapshot(activeRollId, tables);
    }

    private static bool DeclaresDefectEdits(JsonObject payload) =>
        payload.TryGetPropertyValue("hasDefectEdits", out JsonNode? node) &&
        node is JsonValue value &&
        value.TryGetValue(out bool hasEdits) &&
        hasEdits;

    private static bool TryReadSourceIdentity(string path, out DefectSourceIdentity identity)
    {
        identity = default;
        try
        {
            using FileStream stream = new(path, FileMode.Open, FileAccess.Read, FileShare.Read,
                bufferSize: 128 * 1024, FileOptions.SequentialScan);
            if (stream.Length <= 0)
            {
                return false;
            }
            identity = new DefectSourceIdentity(
                checked((ulong)stream.Length),
                Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant());
            return true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or ArgumentException or PathTooLongException or OverflowException)
        {
            return false;
        }
    }

    private static bool CanReadFile(string path)
    {
        try
        {
            using FileStream stream = new(path, FileMode.Open, FileAccess.Read, FileShare.Read,
                bufferSize: 1, FileOptions.SequentialScan);
            return stream.Length > 0;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or ArgumentException or PathTooLongException)
        {
            return false;
        }
    }

    private static bool TryNormalizePath(string path, out string normalized)
    {
        normalized = string.Empty;
        if (string.IsNullOrWhiteSpace(path) || !Path.IsPathFullyQualified(path))
        {
            return false;
        }
        try
        {
            normalized = Path.TrimEndingDirectorySeparator(Path.GetFullPath(path));
            return true;
        }
        catch (Exception error) when (error is ArgumentException or NotSupportedException or
            PathTooLongException)
        {
            return false;
        }
    }

    private static bool PathsEqual(string left, string right) =>
        TryNormalizePath(left, out string normalizedLeft) &&
        TryNormalizePath(right, out string normalizedRight) &&
        string.Equals(normalizedLeft, normalizedRight, StringComparison.OrdinalIgnoreCase);
}
