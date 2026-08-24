using System.Security.Cryptography;
using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.DevelopTestResults;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class VirtualCopyDefectReviewTests
{
    internal static void Run()
    {
        string testParent = Path.Combine(Path.GetTempPath(), "negaflow-gm-copy-review-tests");
        string isolatedBase = Path.Combine(testParent, Guid.NewGuid().ToString("N"));
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        Guid sourceId = Guid.Parse("3e879de7-7394-4378-a3ad-2847cd6c1efb");
        try
        {
            byte[] sourceBytes = [1, 2, 4, 8, 16, 32, 64, 128];
            string sourcePath = Path.Combine(isolatedBase, "scans", "COPY_REVIEW.tif");
            Directory.CreateDirectory(Path.GetDirectoryName(sourcePath)!);
            File.WriteAllBytes(sourcePath, sourceBytes);
            DefectSourceIdentity identity = new(
                (ulong)sourceBytes.Length,
                Convert.ToHexString(SHA256.HashData(sourceBytes)).ToLowerInvariant());
            DefectEditItem item = AutomaticItem();
            JsonObject plain = Record(sourceId, sourcePath);
            using (CatalogSession seed = CatalogSession.Open(roots).Session!)
            {
                Check(seed.Write(Catalog(plain)).IsSuccess,
                    "virtual_copy_review_seed_catalog");
            }

            string? copyId;
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
                      panel.Select(sourceId.ToString("D")) &&
                      panel.AcceptDefectRegion(item) == LibraryFrameError.None &&
                      panel.MarkDefectRecipeReviewed() == LibraryFrameError.None,
                    "virtual_copy_review_builds_reviewed_source_in_session");
                DefectRecipeSnapshot recipe = panel.SelectedFrame!.DefectRecipe!;
                copyId = host.CreateVirtualCopy(sourceId.ToString("D"));
                LibraryFrameSnapshot? source = host.Frames.SingleOrDefault(
                    frame => frame.Id == sourceId.ToString("D"));
                LibraryFrameSnapshot? copy = host.Frames.SingleOrDefault(
                    frame => frame.Id == copyId);
                Check(copyId is not null &&
                      source?.DefectReviewMark is not null &&
                      copy is { DefectReviewMark: null, DefectRecipe: { } copiedRecipe } &&
                      copiedRecipe.RecipeRevision == recipe.RecipeRevision &&
                      copiedRecipe.SourceIdentity == identity &&
                      copiedRecipe.RecipeSha256 == recipe.RecipeSha256 &&
                      copiedRecipe.Items.Single().Id == recipe.Items.Single().Id,
                    "virtual_copy_review_copies_recipe_not_review");
                Check(copyId is not null && HasTrackedEmptyReview(host.FrameRecord(copyId)),
                    "virtual_copy_review_starts_tracked_empty");

                int frameCount = host.Frames.Count;
                int sidecarCount = Directory.GetFiles(roots.DefectRecipeRoot, "*.json").Length;
                string blockedRoot = roots.DefectRecipeRoot;
                string savedRoot = $"{blockedRoot}.failure-fixture";
                Directory.Move(blockedRoot, savedRoot);
                File.WriteAllBytes(blockedRoot, [0]);
                try
                {
                    string? failedCopyId = host.CreateVirtualCopy(sourceId.ToString("D"));
                    Check(failedCopyId is null &&
                          host.Frames.Count == frameCount &&
                          Directory.GetFiles(savedRoot, "*.json").Length ==
                              sidecarCount &&
                          host.Frames.Single(frame =>
                              frame.Id == sourceId.ToString("D")).DefectRecipe?.RecipeSha256 ==
                              recipe.RecipeSha256,
                        "virtual_copy_recipe_write_failure_rolls_back_frame_and_sidecar");
                }
                finally
                {
                    File.Delete(blockedRoot);
                    Directory.Move(savedRoot, blockedRoot);
                }
            }

            using LibraryHostService reopened = new(
                new FakeDispatcher(accepts: true),
                new FakeExporter(_ => OkResult()),
                TestSourceMetadata);
            LibraryHostState reopenedState = reopened.Open(roots);
            LibraryFrameSnapshot? reopenedSource = reopened.Frames.SingleOrDefault(
                frame => frame.Id == sourceId.ToString("D"));
            LibraryFrameSnapshot? reopenedCopy = reopened.Frames.SingleOrDefault(
                frame => frame.Id == copyId);
            Check(reopenedState == LibraryHostState.Open &&
                  reopenedSource is { DefectReviewMark: not null, DefectRecipe: not null } &&
                  reopenedCopy is { DefectReviewMark: null, DefectRecipe: not null } &&
                  copyId is not null &&
                  HasTrackedEmptyReview(reopened.FrameRecord(copyId)),
                "virtual_copy_review_reopen_restores_recipes");
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

    private static bool HasTrackedEmptyReview(JsonObject? record) =>
        record?[DefectReviewTrackingCodec.TrackingName] is JsonObject tracking &&
        tracking.Count == 1 &&
        tracking["coverage"]?.GetValue<string>() == "tracked";

    private static JsonObject Record(Guid frameId, string sourcePath)
    {
        JsonObject record = FrameRecord(
            frameId.ToString("D"),
            Path.GetFileName(sourcePath),
            exposure: 0.0);
        record["rawScanPath"] = sourcePath;
        return record;
    }

    private static CatalogSnapshot Catalog(JsonObject record) =>
        new(null, new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
        {
            [CatalogEntityTable.Frames] =
            [new CatalogEntityRow(record["id"]!.GetValue<string>(), record)],
        });

    private static DefectEditItem AutomaticItem() =>
        GrainMendRegionEdit.From(
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
}
