using System.Security.Cryptography;
using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.DevelopTestResults;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class SourceRelinkDefectTests
{
    internal static void Run()
    {
        string testParent = Path.Combine(Path.GetTempPath(), "negaflow-gm-relink-tests");
        string isolatedBase = Path.Combine(testParent, Guid.NewGuid().ToString("N"));
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        Guid firstId = Guid.Parse("a87b3bb5-29f3-4a2b-8f40-a49ac83d5089");
        Guid secondId = Guid.Parse("cdb345fc-5ec2-4da8-a15a-b5d629897125");
        try
        {
            string oldPath = Path.Combine(isolatedBase, "old", "same-byte.tif");
            string newPath = Path.Combine(isolatedBase, "new", "same-byte.tif");
            Directory.CreateDirectory(Path.GetDirectoryName(oldPath)!);
            Directory.CreateDirectory(Path.GetDirectoryName(newPath)!);
            byte[] sourceBytes = [2, 4, 6, 8, 10, 12, 14, 16];
            File.WriteAllBytes(oldPath, sourceBytes);
            File.Copy(oldPath, newPath);
            DefectSourceIdentity identity = new(
                (ulong)sourceBytes.Length,
                Convert.ToHexString(SHA256.HashData(sourceBytes)).ToLowerInvariant());
            DefectEditItem item = GrainMendRegionEdit.From(
                [0, 0, 0, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
                4,
                4,
                20,
                10,
                0,
                0,
                20,
                10,
                1,
                automatic: true)!;
            JsonObject firstPlain = Record(firstId, oldPath, scanIndex: 1);
            JsonObject secondPlain = Record(secondId, oldPath, scanIndex: 2);
            using (CatalogSession seed = CatalogSession.Open(roots).Session!)
            {
                Check(seed.Write(Catalog(firstPlain, secondPlain)).IsSuccess,
                    "source_relink_defect_seed_catalog");
            }

            using (LibraryHostService host = new(
                       new FakeDispatcher(accepts: true),
                       new FakeExporter(_ => OkResult()),
                       TestSourceMetadata))
            {
                DevelopPanelState panel = new(
                    host,
                    new ToneLimits(5.0f, 1.0f, 2.0f, 0.0, 1.0),
                    new NegativeLimits(0.001f, 1.0f));
                Check(host.Open(roots) == LibraryHostState.Open &&
                      panel.Select(firstId.ToString("D")) &&
                      panel.AcceptDefectRegion(item) == LibraryFrameError.None &&
                      panel.MarkDefectRecipeReviewed() == LibraryFrameError.None,
                    "source_relink_defect_builds_first_reviewed_recipe");
                DefectRecipeSnapshot firstRecipe = panel.SelectedFrame!.DefectRecipe!;
                Check(panel.Select(secondId.ToString("D")) &&
                      panel.AcceptDefectRegion(item) == LibraryFrameError.None &&
                      panel.MarkDefectRecipeReviewed() == LibraryFrameError.None &&
                      host.Frames.Count == 2 &&
                      host.Frames.All(frame => frame.DefectReviewMark is not null),
                    "source_relink_defect_builds_second_reviewed_recipe");
                DefectRecipeSnapshot secondRecipe = panel.SelectedFrame!.DefectRecipe!;
                SourceRelinkPlan plan = SourceRelinkPlanner.FilePlan(oldPath, newPath)!;
                string secondSidecar = Path.Combine(
                    roots.DefectRecipeRoot,
                    $"{secondId:D}.json");
                using (FileStream sidecarLock = new(
                           secondSidecar,
                           FileMode.Open,
                           FileAccess.Read,
                           FileShare.Read))
                {
                    LibrarySourceRelinkResult failed = host.Relink(plan);
                    Check(!failed.IsSuccess &&
                          failed.SidecarError != DefectSidecarError.None &&
                           failed.UpdatedFrameCount == 0 &&
                           host.Frames.All(frame =>
                               frame.SourcePath == oldPath &&
                               frame.DefectRecipe?.RecipeRevision == 1 &&
                               frame.DefectReviewMark is not null),
                        "source_relink_defect_sidecar_failure_restores_family_state");
                }
                LibrarySourceRelinkResult result = host.Relink(plan);
                Check(result.IsSuccess &&
                      result.UpdatedSourceCount == 1 &&
                      result.UpdatedFrameCount == 2 &&
                      result.SidecarError == DefectSidecarError.None &&
                      host.Frames.All(frame =>
                          frame.SourcePath == newPath &&
                           frame.DefectRecipe is
                           {
                               RecipeRevision: 2,
                               SourceIdentity: { } rebound,
                          } &&
                          rebound == identity &&
                          frame.DefectRecipe.RecipeSha256 ==
                              (frame.Id == firstId.ToString("D")
                                  ? firstRecipe.RecipeSha256
                                  : secondRecipe.RecipeSha256) &&
                          frame.DefectReviewMark is null),
                    "source_relink_defect_rebinds_family_and_clears_review");
            }

            using LibraryHostService reopened = new(
                new FakeDispatcher(accepts: true),
                new FakeExporter(_ => OkResult()),
                TestSourceMetadata);
            Check(reopened.Open(roots) == LibraryHostState.Open &&
                  reopened.Frames.Count == 2 &&
                  reopened.Frames.All(frame =>
                      frame.SourcePath == newPath &&
                      frame.DefectRecipe is { RecipeRevision: 2 } &&
                      frame.DefectReviewMark is null),
                "source_relink_defect_reopen_restores_recipes");
        }
        finally
        {
            if (Directory.Exists(isolatedBase) &&
                StoragePathPolicy.IsLexicallyContained(testParent, isolatedBase))
            {
                Directory.Delete(isolatedBase, recursive: true);
            }
        }
    }

    private static JsonObject Record(Guid frameId, string sourcePath, int scanIndex)
    {
        JsonObject record = FrameRecord(
            frameId.ToString("D"),
            Path.GetFileName(sourcePath),
            exposure: 0.0,
            scanIndex);
        record["rawScanPath"] = sourcePath;
        return record;
    }

    private static CatalogSnapshot Catalog(params JsonObject[] records) =>
        new(null, new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
        {
            [CatalogEntityTable.Frames] = records.Select(record =>
                new CatalogEntityRow(record["id"]!.GetValue<string>(), record)).ToArray(),
        });
}
