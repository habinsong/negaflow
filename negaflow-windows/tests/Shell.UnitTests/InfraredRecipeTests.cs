using System.Text.Json;
using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;
using Negaflow.Shell.Print;
using Negaflow.Shell.Shortcuts;
using static Negaflow.Shell.UnitTests.DevelopTestResults;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class InfraredRecipeTests
{
    public static void Run()
    {
        VerifyInfraredDefectRecipeCoordinator();
    }

    private static void VerifyInfraredDefectRecipeCoordinator()
    {
        Guid frameId = Guid.Parse("4fa76528-8ea7-49ef-af2a-cb1d24786216");
        byte[] core = new byte[4 * 3 * 4];
        core[4] = core[5] = core[6] = core[7] = 255;
        byte[] attenuation = new byte[4 * 3 * 2];
        attenuation[2] = 0x00;
        attenuation[3] = 0x80;
        InfraredDetectionResult detection = new(
            InfraredDetectionStatus.Ok,
            20,
            10,
            3,
            -2,
            InfraredAlignmentStatus.Aligned,
            32,
            1,
            0.9,
            0.2,
            0.01,
            1.2,
            2,
            2,
            [new InfraredDetectionCluster(5, 4, 4, 3, core, attenuation)],
            [
                new InfraredDetectedComponent(
                    InfraredDefectClass.Dust,
                    0.8,
                    1,
                    [new InfraredPreviewPoint(10, 5)]),
                new InfraredDetectedComponent(
                    InfraredDefectClass.ScratchVertical,
                    0.6,
                    4,
                    [new InfraredPreviewPoint(4, 2)]),
            ]);
        DefectSourceIdentity identity = new(1234, new string('a', 64));
        DefectRecipeSnapshot recipe = InfraredDefectRecipeCoordinator.CreateRecipe(
            frameId, identity, null, detection);
        DefectEditItem item = recipe.Items.Single();
        Check(recipe.RecipeRevision == 1 && recipe.SourceIdentity == identity,
            "infrared_recipe_identity_revision");
        Check(item.Kind == DefectEditKind.Infrared &&
              item.Label == new DefectEditLabel(DefectEditLabelKind.Infrared, 2) &&
              item.BaseSize == new DefectSize(20, 10),
            "infrared_recipe_item_contract");
        Check(item.Clusters?.Single().Roi == new DefectRect(5, 4, 4, 3) &&
              DefectMaskCodec.TryDecodeRgba8(item.Clusters.Single().Mask, 4, 3, out byte[] decodedCore) &&
              decodedCore.SequenceEqual(core) &&
              DefectMaskCodec.TryDecodeR16LittleEndian(
                  item.Clusters.Single().AttenuationR16!, 4, 3, out byte[] decodedAttenuation) &&
              decodedAttenuation.SequenceEqual(attenuation),
            "infrared_recipe_cluster_payloads");
        Check(item.Preview[0].Points.Single() == new DefectPoint(0.5, 0.5) &&
              item.Summary.ClassBreakdown?.Counts.Count == 2 &&
              item.Summary.ClassBreakdown.MeanConfidence == 0.7,
            "infrared_recipe_preview_summary");

        string parent = Path.Combine(AppContext.BaseDirectory, "infrared-recipe-tests");
        string isolatedBase = Path.Combine(parent, $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        try
        {
            using (CatalogSession session = CatalogSession.Open(roots).Session!)
            {
                Check(session.ReadOrCreate().IsSuccess, "infrared_recipe_catalog_create");
                JsonObject payload = FrameRecord(frameId.ToString("D"), "IR_0001.tif", 0);
                Check(session.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] =
                        [new CatalogEntityRow(frameId.ToString("D"), payload)],
                    })).IsSuccess, "infrared_recipe_catalog_seed");
            }
            using (LibraryDocument document = LibraryDocument.Open(roots).Document!)
            {
                LibraryDefectRecipeWriteResult written =
                    document.WriteDefectRecipe(frameId.ToString("D"), recipe);
                Check(written.IsSuccess &&
                      document.Frames.Single().DefectRecipe?.RecipeRevision == 1,
                    "infrared_recipe_sidecar_catalog_commit");
                DevelopRequestResult request = DevelopRequestFactory.Create(
                    document.Frames.Single(), Path.Combine(isolatedBase, "preview.png"));
                Check(request.IsSuccess &&
                      request.Request?.DefectInfrared.Count == 1 &&
                      request.Request.DefectInfrared[0].Clusters.Count == 1,
                    "infrared_recipe_reaches_shared_develop_request");
            }
            using LibraryDocument reopened = LibraryDocument.Open(roots).Document!;
            Check(reopened.Frames.Single().DefectRecipe?.Items.Single().Kind ==
                  DefectEditKind.Infrared,
                "infrared_recipe_restart_roundtrip");
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

}
