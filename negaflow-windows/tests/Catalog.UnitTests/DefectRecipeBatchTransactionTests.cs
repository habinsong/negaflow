using System.Text.Json.Nodes;
using static Negaflow.Catalog.UnitTests.CatalogTestAssert;
using static Negaflow.Catalog.UnitTests.DefectTestFixture;

namespace Negaflow.Catalog.UnitTests;

internal static class DefectRecipeBatchTransactionTests
{
    internal static void Run(StorageRootSet parentRoots)
    {
        StorageRootSet roots = StorageRootResolver.ResolveForTests(Path.Combine(
            parentRoots.LocalApplicationDataRoot,
            "defect-batch-transaction")).Roots!;
        Guid firstId = Guid.Parse("4df0537d-2b12-4379-a1a2-65b17dc50d1a");
        Guid secondId = Guid.Parse("804cb84a-3043-4bd9-bf86-85c4fb7030a1");
        DefectRecipeSnapshot firstOne = Recipe(firstId, 1, strength: 1.0);
        DefectRecipeSnapshot secondOne = Recipe(secondId, 1, strength: 1.0);
        DefectRecipeSnapshot firstTwo = Recipe(firstId, 2, strength: 0.75);
        DefectRecipeSnapshot secondTwo = Recipe(secondId, 2, strength: 0.75);

        Check(SqliteCatalogStore.Write(
                Catalog(firstId, secondId, firstHasEdits: false, secondHasEdits: false, "old"),
                roots.CatalogPath).IsSuccess,
            "defect_batch_seed_catalog");
        using CatalogSession session = CatalogSession.Open(roots).Session!;
        Check(session.WriteDefectRecipeAndCatalog(
                firstOne,
                Catalog(firstId, secondId, firstHasEdits: true, secondHasEdits: false, "old"))
            .IsSuccess,
            "defect_batch_seed_first_sidecar");
        Check(session.WriteDefectRecipeAndCatalog(
                secondOne,
                Catalog(firstId, secondId, firstHasEdits: true, secondHasEdits: true, "old"))
            .IsSuccess,
            "defect_batch_seed_second_sidecar");

        string firstPath = DefectSidecarStore.PathFor(roots, firstId);
        string secondPath = DefectSidecarStore.PathFor(roots, secondId);
        byte[] firstBytes = File.ReadAllBytes(firstPath);
        byte[] secondBytes = File.ReadAllBytes(secondPath);
        CatalogSnapshot target = Catalog(
            firstId,
            secondId,
            firstHasEdits: true,
            secondHasEdits: true,
            "new");
        DefectRecipeCatalogBatchWriteResult failed =
            session.WriteDefectRecipesAndCatalogForTesting(
                [firstTwo, secondTwo],
                target,
                writer: (_, _) => CatalogWriteResult.Failure(CatalogStoreError.IoFailure));
        Check(!failed.IsSuccess &&
              failed.CatalogError == CatalogStoreError.IoFailure &&
              File.ReadAllBytes(firstPath).SequenceEqual(firstBytes) &&
              File.ReadAllBytes(secondPath).SequenceEqual(secondBytes) &&
              session.ReadDefectRecipe(firstId).Snapshot?.RecipeRevision == 1 &&
              session.ReadDefectRecipe(secondId).Snapshot?.RecipeRevision == 1 &&
              Marker(session.Read(), firstId) == "old" &&
              Marker(session.Read(), secondId) == "old",
            "defect_batch_catalog_failure_restores_every_sidecar_and_catalog");

        DefectRecipeCatalogBatchWriteResult committed =
            session.WriteDefectRecipesAndCatalog([firstTwo, secondTwo], target);
        Check(committed.IsSuccess && committed.Snapshots.Count == 2 &&
              session.ReadDefectRecipe(firstId).Snapshot?.RecipeRevision == 2 &&
              session.ReadDefectRecipe(secondId).Snapshot?.RecipeRevision == 2 &&
              Marker(session.Read(), firstId) == "new" &&
              Marker(session.Read(), secondId) == "new",
            "defect_batch_commits_every_sidecar_with_one_catalog");

        DefectRecipeCatalogBatchWriteResult duplicateTarget =
            session.WriteDefectRecipesAndCatalog(
                [Recipe(firstId, 3, strength: 0.5), Recipe(secondId, 3, strength: 0.5)],
                new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] =
                        [
                            Row(firstId, hasEdits: true, "duplicate"),
                            Row(firstId, hasEdits: true, "duplicate"),
                            Row(secondId, hasEdits: true, "duplicate"),
                        ],
                    }));
        Check(!duplicateTarget.IsSuccess &&
              duplicateTarget.SidecarError == DefectSidecarError.InvalidSnapshot &&
              session.ReadDefectRecipe(firstId).Snapshot?.RecipeRevision == 2 &&
              session.ReadDefectRecipe(secondId).Snapshot?.RecipeRevision == 2,
            "defect_batch_duplicate_target_frame_fails_closed_before_sidecars");
    }

    private static DefectRecipeSnapshot Recipe(Guid frameId, ulong revision, double strength)
    {
        DefectEditItem item = DefectRecipeItems()[0] with { Strength = strength };
        return DefectRecipeSnapshot.Create(frameId, revision, sourceIdentity: null, [item]);
    }

    private static CatalogSnapshot Catalog(
        Guid firstId,
        Guid secondId,
        bool firstHasEdits,
        bool secondHasEdits,
        string marker) =>
        new(null, new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
        {
            [CatalogEntityTable.Frames] =
            [
                Row(firstId, firstHasEdits, marker),
                Row(secondId, secondHasEdits, marker),
            ],
        });

    private static CatalogEntityRow Row(Guid frameId, bool hasEdits, string marker)
    {
        JsonObject payload = new()
        {
            ["id"] = frameId.ToString("D"),
            ["marker"] = marker,
        };
        if (hasEdits)
        {
            payload["hasDefectEdits"] = true;
        }
        return new CatalogEntityRow(frameId.ToString("D"), payload);
    }

    private static string? Marker(CatalogReadResult read, Guid frameId) =>
        read.Snapshot?.Rows(CatalogEntityTable.Frames)
            .Single(row => string.Equals(
                row.Id,
                frameId.ToString("D"),
                StringComparison.OrdinalIgnoreCase))
            .Payload["marker"]?.GetValue<string>();
}
