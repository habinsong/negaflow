using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

/// <summary>
/// 기존 defect sidecar 여러 개와 그 frame들을 바꾸는 catalog snapshot을 한 commit 경계로 묶습니다.
/// </summary>
internal sealed class DefectRecipeCatalogBatchTransaction(StorageRootSet roots)
{
    internal DefectRecipeCatalogBatchWriteResult Write(
        IReadOnlyList<DefectRecipeSnapshot> recipes,
        CatalogSnapshot catalog,
        Func<CatalogWriteResult> commitCatalog,
        bool forceSidecarRollbackFailure)
    {
        if (recipes.Count == 0 ||
            recipes.Select(recipe => recipe.FrameId).Distinct().Count() != recipes.Count)
        {
            return DefectRecipeCatalogBatchWriteResult.Failure(
                DefectSidecarError.InvalidSnapshot);
        }

        foreach (DefectRecipeSnapshot recipe in recipes)
        {
            if (recipe.Items.Count == 0 || !CatalogDeclaresDefectEdits(catalog, recipe.FrameId))
            {
                return DefectRecipeCatalogBatchWriteResult.Failure(
                    DefectSidecarError.InvalidSnapshot,
                    CatalogStoreError.MissingAuthoritativeData);
            }
            DefectSidecarReadResult current = DefectSidecarStore.Read(roots, recipe.FrameId);
            if (current.Snapshot is not { } previous ||
                previous.RecipeRevision == ulong.MaxValue ||
                recipe.RecipeRevision != previous.RecipeRevision + 1UL)
            {
                return DefectRecipeCatalogBatchWriteResult.Failure(
                    DefectSidecarError.InvalidSnapshot);
            }
        }

        return DefectSidecarCatalogWriter.WriteMany(
            roots,
            recipes,
            () => DefectSidecarCatalogHealth.ValidateDeclaredSidecars(roots, catalog) ==
                    DefectSidecarError.None
                ? commitCatalog()
                : CatalogWriteResult.Failure(CatalogStoreError.MissingAuthoritativeData),
            forceSidecarRollbackFailure);
    }

    private static bool CatalogDeclaresDefectEdits(
        CatalogSnapshot snapshot,
        Guid frameId)
    {
        string expected = frameId.ToString("D");
        CatalogEntityRow[] rows = snapshot.Rows(CatalogEntityTable.Frames)
            .Where(candidate => string.Equals(
                candidate.Id,
                expected,
                StringComparison.OrdinalIgnoreCase))
            .Take(2)
            .ToArray();
        if (rows.Length != 1)
        {
            return false;
        }
        JsonObject payload = rows[0].Payload;
        return payload.TryGetPropertyValue("hasDefectEdits", out JsonNode? node) &&
            node is JsonValue value &&
            value.TryGetValue(out bool hasEdits) &&
            hasEdits;
    }
}
