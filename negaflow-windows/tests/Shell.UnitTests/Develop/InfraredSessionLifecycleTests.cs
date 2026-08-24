using System.Text.Json;
using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class InfraredSessionLifecycleTests
{
    public static void Run()
    {
        string parent = Path.Combine(AppContext.BaseDirectory, "infrared-session-lifecycle-tests");
        string isolatedBase = Path.Combine(parent, $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        Guid frameId = Guid.Parse("5d3bb352-cbeb-43da-aeb0-a4639d4ebc1d");
        string frameIdText = frameId.ToString("D");
        string sourcePath = Path.Combine(isolatedBase, "visible.tif");
        string infraredPath = Path.Combine(isolatedBase, "infrared.tif");
        try
        {
            Directory.CreateDirectory(isolatedBase);
            File.WriteAllBytes(sourcePath, [1, 3, 5, 7]);
            File.WriteAllBytes(infraredPath, [2, 4, 6, 8]);
            Check(DefectSourceIdentityReader.TryRead(sourcePath, out DefectSourceIdentity identity),
                "infrared_session_source_identity");

            DefectEditItem region = RegionItem();
            DefectRecipeSnapshot recipe = DefectRecipeSnapshot.Create(
                frameId,
                recipeRevision: 1,
                identity,
                [region, InfraredItem()]);
            JsonObject plain = FrameRecord(frameIdText, "visible.tif", exposure: 0.0);
            plain[LibraryFrameReader.SourcePathName] = sourcePath;
            plain[LibraryFrameReader.InfraredPathName] = infraredPath;
            JsonObject declared = plain.DeepClone().AsObject();
            declared["hasDefectEdits"] = true;
            JsonObject reviewed = DefectReviewTrackingCodec.Apply(
                declared,
                new DefectReviewMarkRecord(
                    recipe.RecipeRevision,
                    recipe.RecipeSha256,
                    identity.Sha256)).FrameRecord!;
            using (CatalogSession seed = CatalogSession.Open(roots).Session!)
            {
                Check(seed.Write(Catalog(plain)).IsSuccess,
                    "infrared_session_seed_catalog");
                Check(seed.WriteDefectRecipeAndCatalog(recipe, Catalog(declared)).IsSuccess,
                    "infrared_session_seed_mixed_recipe");
                Check(seed.Write(Catalog(reviewed)).IsSuccess,
                    "infrared_session_seed_review");
            }

            using (LibraryDocument document = LibraryDocument.Open(roots).Document!)
            {
                LibraryFrameSnapshot frame = document.Frames.Single();
                Check(frame.DefectRecipe is { RecipeRevision: 1 } &&
                      frame.DefectRecipeRevision == 1,
                    "infrared_session_open_restores_previous_session_recipe");
                Check(frame.InfraredPath == infraredPath &&
                      !InfraredCleanPolicy.ShouldRun(frame, alreadyAttempted: false),
                    "infrared_session_open_does_not_repeat_restored_ir_detection");

                JsonObject record = document.FrameRecord(frameIdText)!;
                using JsonDocument recordJson = JsonDocument.Parse(record.ToJsonString());
                Check(DefectReviewTrackingCodec.Read(recordJson.RootElement) is not null,
                    "infrared_session_open_restores_review_identity");

                DefectRecipeSnapshot revisionTwo = DefectRecipeSnapshot.Create(
                    frameId,
                    recipeRevision: 2,
                    identity,
                    [region]);
                Check(document.WriteDefectRecipe(frameIdText, revisionTwo).IsSuccess,
                    "infrared_session_open_preserves_next_revision");
            }

            using LibraryDocument reopened = LibraryDocument.Open(roots).Document!;
            Check(reopened.Frames.Single() is
                  { DefectRecipe: { RecipeRevision: 2 }, DefectRecipeRevision: 2 },
                "infrared_session_next_open_restores_new_session_recipe");
        }
        finally
        {
            if (Directory.Exists(isolatedBase) &&
                StoragePathPolicy.IsLexicallyContained(parent, isolatedBase))
            {
                Directory.Delete(isolatedBase, recursive: true);
            }
        }
    }

    private static DefectEditItem RegionItem()
    {
        byte[] mask = new byte[16];
        mask[5] = 255;
        return GrainMendRegionEdit.From(
            mask,
            4,
            4,
            20,
            10,
            0,
            0,
            20,
            10,
            1,
            automatic: false)!;
    }

    private static DefectEditItem InfraredItem()
    {
        byte[] mask = new byte[4 * 4 * 4];
        mask[0] = mask[1] = mask[2] = mask[3] = 255;
        return new DefectEditItem(
            Guid.NewGuid(),
            DefectEditKind.Infrared,
            Enabled: true,
            Strength: 1.0,
            new DefectEditLabel(DefectEditLabelKind.Infrared, 1),
            new DefectEditSummary(
                DefectEditSummaryKind.ClassBreakdown,
                new DefectClassBreakdown(
                    [new DefectClassCount(DefectClassification.Dust, 1)],
                    1.0)),
            new DefectSize(4.0, 4.0),
            [])
        {
            Clusters =
            [
                new DefectCluster(
                    new DefectRect(0.0, 0.0, 4.0, 4.0),
                    new DefectMask(false, mask),
                    4,
                    4),
            ],
        };
    }

    private static CatalogSnapshot Catalog(JsonObject record) => new(
        null,
        new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
        {
            [CatalogEntityTable.Frames] =
                [new CatalogEntityRow(record["id"]!.GetValue<string>(), record)],
        });
}
