using System.Text.Json.Nodes;
using Negaflow.Catalog;

namespace Negaflow.Shell;

internal readonly record struct LibraryStartupDefectRecipeCleanupResult(
    CatalogSnapshot? Snapshot,
    IReadOnlyDictionary<string, ulong> Revisions,
    DefectSidecarError SidecarError,
    CatalogStoreError CatalogError)
{
    /// <summary>
    /// 카탈로그가 결함 편집을 선언하는데 기록을 읽지 못한 사진입니다. macOS
    /// <c>defectEditsNeedRestore</c> 처럼 그 사진만 "복원 대기" 로 두고 라이브러리는 엽니다.
    /// </summary>
    internal IReadOnlyCollection<string> RestorePending { get; init; } = [];

    /// <summary>
    /// 여기서 읽은 편집이 남은 기록입니다. 문서 투영이 같은 파일을 다시 복호하지 않고 이것을
    /// 씁니다 - 예전에는 켤 때마다 같은 기록을 두 번 풀었습니다.
    /// </summary>
    internal IReadOnlyDictionary<string, DefectRecipeSnapshot> Recipes { get; init; } =
        new Dictionary<string, DefectRecipeSnapshot>(StringComparer.Ordinal);

    internal bool IsSuccess => Snapshot is not null &&
        SidecarError == DefectSidecarError.None &&
        CatalogError == CatalogStoreError.None;
}

/// <summary>
/// document 투영 전에 catalog가 선언한 recipe sidecar를 검증하고 revision을 복원합니다.
/// 유효한 GrainMend/IR 편집은 앱 재시작 뒤에도 같은 레이어로 유지합니다.
/// </summary>
internal static class LibraryStartupDefectRecipeCleanup
{
    internal static LibraryStartupDefectRecipeCleanupResult Run(
        CatalogSession session,
        CatalogSnapshot initial)
    {
        ArgumentNullException.ThrowIfNull(session);
        ArgumentNullException.ThrowIfNull(initial);

        CatalogSnapshot current = initial;
        Dictionary<string, ulong> revisions = new(StringComparer.Ordinal);
        Dictionary<string, DefectRecipeSnapshot> recipes = new(StringComparer.Ordinal);
        List<string> restorePending = [];

        // 선언한 사진을 차례대로 모으고 기록은 한꺼번에 읽습니다(`ReadDefectRecipes`). 사진마다
        // 파일이 따로라 읽는 차례가 결과를 바꾸지 않습니다. 사진 id 가 틀린 줄에서는 모으기를
        // 멈추고, 그 앞 사진까지 처리한 뒤 실패합니다 - 한 장씩 읽던 때와 같습니다.
        IReadOnlyList<CatalogEntityRow> frames = current.Rows(CatalogEntityTable.Frames);
        List<int> declaredIndices = [];
        List<Guid> declaredIds = [];
        bool invalidFrameId = false;
        for (int index = 0; index < frames.Count; ++index)
        {
            if (!DeclaresDefectEdits(frames[index].Payload))
            {
                continue;
            }
            if (!Guid.TryParseExact(frames[index].Id, "D", out Guid frameId))
            {
                invalidFrameId = true;
                break;
            }
            // macOS 처럼 읽기 전에 자기 기록의 빠진 권한을 되돌립니다.
            _ = session.RestoreDefectRecordAccess(frameId);
            declaredIndices.Add(index);
            declaredIds.Add(frameId);
        }
        IReadOnlyList<DefectSidecarReadResult> reads = session.ReadDefectRecipes(declaredIds);

        for (int slot = 0; slot < declaredIndices.Count; ++slot)
        {
            int index = declaredIndices[slot];
            Guid frameId = declaredIds[slot];
            CatalogEntityRow row = current.Rows(CatalogEntityTable.Frames)[index];
            DefectSidecarReadResult read = reads[slot];
            // macOS 처럼 백업에 같은 사진의 기록이 남아 있으면 되살린 뒤 다시 읽습니다.
            if (read.Snapshot is null && session.RestoreDefectRecipeFromBackup(frameId))
            {
                read = session.ReadDefectRecipe(frameId);
            }
            if (read.Snapshot is not { } recipe)
            {
                restorePending.Add(row.Id);
                continue;
            }
            if (recipe.Items.Count == 0)
            {
                if (recipe.RecipeRevision == ulong.MaxValue)
                {
                    return Failure(
                        revisions,
                        DefectSidecarError.InvalidSnapshot,
                        CatalogStoreError.None);
                }
                ulong nextRevision = recipe.RecipeRevision + 1UL;
                CatalogSnapshot target = WithoutRecipeState(current, index);
                DefectRecipeCatalogDeleteResult deleted =
                    session.DeleteDefectRecipeAndCatalog(frameId, nextRevision, target);
                if (!deleted.IsSuccess)
                {
                    return Failure(revisions, deleted.SidecarError, deleted.CatalogError);
                }
                revisions[row.Id] = nextRevision;
                current = target;
                continue;
            }
            revisions[row.Id] = recipe.RecipeRevision;
            recipes[row.Id] = recipe;
        }
        if (invalidFrameId)
        {
            return Failure(
                revisions,
                DefectSidecarError.InvalidFrameId,
                CatalogStoreError.MissingAuthoritativeData);
        }

        return new(
            current,
            revisions,
            DefectSidecarError.None,
            CatalogStoreError.None)
        {
            RestorePending = restorePending,
            Recipes = recipes,
        };
    }

    private static CatalogSnapshot WithoutRecipeState(
        CatalogSnapshot current,
        int frameIndex)
    {
        IReadOnlyList<CatalogEntityRow> currentFrames =
            current.Rows(CatalogEntityTable.Frames);
        JsonObject payload =
            (JsonObject)currentFrames[frameIndex].Payload.DeepClone();
        payload.Remove("hasDefectEdits");
        payload = DefectReviewTrackingCodec.Apply(payload, mark: null).FrameRecord!;

        List<CatalogEntityRow> frames = currentFrames.ToList();
        frames[frameIndex] = new CatalogEntityRow(
            currentFrames[frameIndex].Id,
            payload);
        Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>> tables =
            CatalogEntityTables.All.ToDictionary(
                table => table,
                table => table == CatalogEntityTable.Frames
                    ? (IReadOnlyList<CatalogEntityRow>)frames
                    : current.Rows(table));
        return new CatalogSnapshot(current.ActiveRollId, tables);
    }

    private static bool DeclaresDefectEdits(JsonObject payload) =>
        payload.TryGetPropertyValue("hasDefectEdits", out JsonNode? node) &&
        node is JsonValue value &&
        value.TryGetValue(out bool declared) &&
        declared;

    private static LibraryStartupDefectRecipeCleanupResult Failure(
        IReadOnlyDictionary<string, ulong> revisions,
        DefectSidecarError sidecarError,
        CatalogStoreError catalogError) =>
        new(null, revisions, sidecarError, catalogError);
}
