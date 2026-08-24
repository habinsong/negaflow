using System.Text.Json.Nodes;
using Negaflow.Catalog;

namespace Negaflow.Shell;

internal readonly record struct LibraryStartupDefectRecipeCleanupResult(
    CatalogSnapshot? Snapshot,
    IReadOnlyDictionary<string, ulong> Revisions,
    DefectSidecarError SidecarError,
    CatalogStoreError CatalogError)
{
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
        int frameCount = current.Rows(CatalogEntityTable.Frames).Count;
        for (int index = 0; index < frameCount; ++index)
        {
            CatalogEntityRow row = current.Rows(CatalogEntityTable.Frames)[index];
            if (!DeclaresDefectEdits(row.Payload))
            {
                continue;
            }
            if (!Guid.TryParseExact(row.Id, "D", out Guid frameId))
            {
                return Failure(
                    revisions,
                    DefectSidecarError.InvalidFrameId,
                    CatalogStoreError.MissingAuthoritativeData);
            }

            DefectSidecarReadResult read = session.ReadDefectRecipe(frameId);
            if (read.Snapshot is not { } recipe)
            {
                return Failure(revisions, read.Error, CatalogStoreError.None);
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
        }

        return new(
            current,
            revisions,
            DefectSidecarError.None,
            CatalogStoreError.None);
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
