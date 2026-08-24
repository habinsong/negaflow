using System.Security.Cryptography;
using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.DevelopTestResults;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class DefectLayerFrameInteractionTests
{
    internal static void Run()
    {
        string testParent = Path.Combine(Path.GetTempPath(), "negaflow-gm-layer-tests");
        string isolatedBase = Path.Combine(testParent, Guid.NewGuid().ToString("N"));
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        Guid sourceId = Guid.Parse("2bd3d665-8c10-40dd-97cb-19aa4001ea31");
        string sourceIdText = sourceId.ToString("D");
        try
        {
            byte[] sourceBytes = [1, 3, 5, 7, 9, 11, 13, 15];
            string sourcePath = Path.Combine(isolatedBase, "scans", "FRAME_STATE.tif");
            Directory.CreateDirectory(Path.GetDirectoryName(sourcePath)!);
            File.WriteAllBytes(sourcePath, sourceBytes);
            DefectSourceIdentity sourceIdentity = new(
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
            using (CatalogSession seed = CatalogSession.Open(roots).Session!)
            {
                JsonObject payload = FrameRecord(sourceIdText, "FRAME_STATE.tif", 0.0);
                payload["rawScanPath"] = sourcePath;
                Check(seed.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] = [new(sourceIdText, payload)],
                    })).IsSuccess, "defect_layer_frame_state_seed_catalog");
            }

            using LibraryHostService host = new(
                new FakeDispatcher(accepts: true),
                new FakeExporter(_ => OkResult()));
            Check(host.Open(roots) == LibraryHostState.Open,
                "defect_layer_frame_state_host_open");
            DevelopPanelState panel = new(
                host,
                new ToneLimits(5.0f, 1.0f, 2.0f, 0.0, 1.0),
                new NegativeLimits(0.001f, 1.0f));
            Check(panel.Select(sourceIdText) &&
                  panel.AcceptDefectRegion(item) == LibraryFrameError.None &&
                  panel.MarkDefectRecipeReviewed() == LibraryFrameError.None,
                "defect_layer_frame_state_builds_reviewed_recipe_in_session");
            DefectRecipeSnapshot recipe = panel.SelectedFrame!.DefectRecipe!;
            Check(recipe.SourceIdentity == sourceIdentity,
                "defect_layer_frame_state_recipe_uses_source_identity");
            string? copyId = host.CreateVirtualCopy(sourceIdText);
            Check(copyId is not null &&
                  host.Frames.Single(frame => frame.Id == copyId).DefectRecipe?.Items.Single().Id ==
                      item.Id,
                "defect_layer_frame_state_virtual_copy_keeps_macos_item_id");
            if (copyId is null)
            {
                return;
            }

            Check(panel.Select(sourceIdText), "defect_layer_frame_state_select_source");
            DefectReviewMark reviewed = new(
                recipe.RecipeRevision,
                recipe.RecipeSha256,
                recipe.SourceIdentity!.Value.Sha256);
            Check(Projected(panel, reviewed) is { Reviewed: true, DoneEnabled: false },
                "defect_layer_frame_state_starts_with_matching_review");
            Check(panel.DefectLayers.SetStrength(item.Id, 1.0, live: true) ==
                      LibraryFrameError.None &&
                  !panel.DefectLayers.HasLiveStrength &&
                  Projected(panel, reviewed) is { Reviewed: true, DoneEnabled: false },
                "defect_layer_frame_state_live_noop_keeps_matching_review");
            panel.DefectLayers.ToggleMaskPreview(item.Id);
            Check(panel.DefectLayers.SetStrength(item.Id, 0.35, live: true) ==
                      LibraryFrameError.None,
                "defect_layer_frame_state_source_starts_pending_interaction");
            LibraryFrameSnapshot? sourceLivePreview = panel.DefectLayers.PreviewFrame;
            Check(panel.DefectLayers.MaskPreviewId == item.Id &&
                  Strength(sourceLivePreview) == 0.35 &&
                  Strength(panel.SelectedFrame) == 1.0,
                "defect_layer_frame_state_source_owns_pending_interaction");
            Check(ReferenceEquals(sourceLivePreview, panel.DefectLayers.PreviewFrame),
                "defect_layer_frame_state_reuses_live_preview_snapshot");
            Check(panel.DefectLayers.HasLiveStrength &&
                  panel.DefectLayers.PreviewFrame?.DefectRecipe?.RecipeRevision ==
                      recipe.RecipeRevision + 1UL &&
                  Projected(panel, reviewed) is
                    { Reviewed: false, DoneVisible: true, DoneEnabled: true },
                "defect_layer_frame_state_live_strength_publishes_new_review_identity");
            Check(panel.DefectLayers.SetStrength(item.Id, 0.0, live: true) ==
                      LibraryFrameError.None &&
                  Strength(panel.DefectLayers.PreviewFrame) == 0.0 &&
                  ProjectedStrength(panel) == 0.0,
                "defect_layer_frame_state_zero_strength_reaches_live_preview");
            Check(panel.DefectLayers.SetStrength(item.Id, 0.35, live: true) ==
                      LibraryFrameError.None,
                "defect_layer_frame_state_restores_live_strength_after_zero");

            Check(panel.CreateVirtualCopy(),
                "defect_layer_frame_state_create_copy_during_live_strength");
            LibraryFrameSnapshot? liveCopy = host.Frames.SingleOrDefault(
                frame => frame.VirtualCopyNumber == 2);
            Check(liveCopy is not null &&
                  liveCopy.DefectRecipe?.Items.Single().Id == item.Id &&
                  Strength(liveCopy) == 0.35 &&
                  host.ActiveFrameId == liveCopy.Id &&
                  panel.SelectedFrame?.Id == liveCopy.Id,
                "defect_layer_frame_state_live_copy_uses_current_strength");
            if (liveCopy is null)
            {
                return;
            }
            Check(panel.Select(liveCopy.Id) &&
                  panel.DefectLayers.MaskPreviewId is null &&
                  Strength(panel.DefectLayers.PreviewFrame) == 0.35,
                "defect_layer_frame_state_live_copy_starts_without_source_interaction");

            string? crossWorkspaceCopyId = host.CreateVirtualCopy(sourceIdText);
            LibraryFrameSnapshot? crossWorkspaceCopy = host.Frames.FirstOrDefault(
                frame => frame.Id == crossWorkspaceCopyId);
            Check(crossWorkspaceCopy is not null &&
                  crossWorkspaceCopy.DefectRecipe?.Items.Single().Id == item.Id &&
                  Strength(crossWorkspaceCopy) == 0.35,
                "defect_layer_frame_state_public_copy_path_uses_source_live_strength");

            Check(panel.Select(copyId) &&
                  panel.DefectLayers.MaskPreviewId is null &&
                  Strength(panel.DefectLayers.PreviewFrame) == 1.0,
                "defect_layer_frame_state_copy_starts_without_source_interaction");
            Check(panel.DefectLayers.SetStrength(item.Id, 0.35, live: false) ==
                      LibraryFrameError.None &&
                  Strength(panel.SelectedFrame) == 1.0,
                "defect_layer_frame_state_late_source_commit_does_not_edit_copy");

            panel.DefectLayers.ToggleMaskPreview(item.Id);
            Check(panel.DefectLayers.SetStrength(item.Id, 0.55, live: true) ==
                      LibraryFrameError.None,
                "defect_layer_frame_state_copy_sets_own_interaction");
            Check(panel.Select(sourceIdText) &&
                  panel.DefectLayers.MaskPreviewId == item.Id &&
                  Strength(panel.DefectLayers.PreviewFrame) == 0.35,
                "defect_layer_frame_state_source_interaction_survives_away_switch");
            Check(ProjectedStrength(panel) == 0.35,
                "defect_layer_frame_state_source_row_uses_live_strength_after_switch");
            Check(panel.Select(copyId) &&
                  panel.DefectLayers.MaskPreviewId == item.Id &&
                  Strength(panel.DefectLayers.PreviewFrame) == 0.55,
                "defect_layer_frame_state_copy_interaction_is_independent");
            Check(panel.Select(sourceIdText) &&
                  panel.DefectLayers.SetStrength(item.Id, 0.35, live: false) ==
                      LibraryFrameError.None &&
                  !panel.DefectLayers.HasLiveStrength &&
                  Strength(panel.SelectedFrame) == 0.35 &&
                  panel.SelectedFrame?.DefectRecipe?.RecipeRevision ==
                      recipe.RecipeRevision + 1UL &&
                  Projected(panel, reviewed) is
                    { Reviewed: false, DoneVisible: true, DoneEnabled: true },
                "defect_layer_frame_state_commit_reopens_unreviewed_done");

            DefectRecipeSnapshot committed = panel.SelectedFrame!.DefectRecipe!;
            DefectReviewMark committedReviewed = ReviewOf(committed);
            Check(Projected(panel, committedReviewed) is
                    { Reviewed: true, DoneEnabled: false },
                "defect_layer_frame_state_committed_recipe_accepts_exact_review");
            Check(panel.DefectLayers.SetStrength(item.Id, 1.0, live: true) ==
                      LibraryFrameError.None &&
                  panel.DefectLayers.SetStrength(item.Id, 0.35, live: true) ==
                      LibraryFrameError.None,
                "defect_layer_frame_state_live_gesture_returns_to_original_strength");
            DefectRecipeSnapshot returnedLive = panel.DefectLayers.PreviewFrame!.DefectRecipe!;
            Check(returnedLive.RecipeRevision == committed.RecipeRevision + 1UL &&
                  returnedLive.RecipeSha256 == committed.RecipeSha256 &&
                  Projected(panel, committedReviewed) is
                    { Reviewed: false, DoneVisible: true, DoneEnabled: true },
                "defect_layer_frame_state_returned_live_recipe_keeps_advanced_revision");

            Check(panel.MarkDefectRecipeReviewed() == LibraryFrameError.None &&
                  panel.SelectedFrame?.DefectReviewMark is { } liveMark &&
                  liveMark.RecipeRevision == returnedLive.RecipeRevision &&
                  liveMark.RecipeSha256 == returnedLive.RecipeSha256 &&
                  liveMark.SourceIdentitySha256 ==
                      returnedLive.SourceIdentity!.Value.Sha256,
                "defect_layer_frame_state_live_done_reviews_preview_identity");
            DefectReviewMark liveReviewed = ReviewOf(panel.SelectedFrame!.DefectReviewMark!.Value);
            Check(Projected(panel, liveReviewed) is { Reviewed: true, DoneEnabled: false },
                "defect_layer_frame_state_live_review_updates_done_state");
            LibraryFrameError returnedCommitError =
                panel.DefectLayers.SetStrength(item.Id, 0.35, live: false);
            DefectRecipeSnapshot? returnedCommit = panel.SelectedFrame?.DefectRecipe;
            Check(returnedCommitError == LibraryFrameError.None &&
                  returnedCommit is not null &&
                  returnedCommit.RecipeRevision == returnedLive.RecipeRevision &&
                  returnedCommit.RecipeSha256 == returnedLive.RecipeSha256 &&
                  Projected(panel, liveReviewed) is { Reviewed: true, DoneEnabled: false },
                "defect_layer_frame_state_returned_commit_preserves_live_review_identity");
            if (returnedCommit is null)
            {
                return;
            }

            string sidecarPath = Path.Combine(
                roots.DefectRecipeRoot,
                $"{sourceId:D}.json");
            Check(File.Exists(sidecarPath),
                "defect_layer_frame_state_persistence_failure_has_sidecar");
            using (FileStream sidecarLock = new(
                sidecarPath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read))
            {
                Check(panel.DefectLayers.SetStrength(item.Id, 0.6, live: true) ==
                          LibraryFrameError.None &&
                      Strength(panel.DefectLayers.PreviewFrame) == 0.6,
                    "defect_layer_frame_state_failed_commit_starts_live_preview");
                Check(panel.DefectLayers.SetStrength(item.Id, 0.6, live: false) ==
                          LibraryFrameError.InvalidDefectRecipe &&
                      !panel.DefectLayers.HasLiveStrength &&
                      panel.SelectedFrame?.DefectRecipe?.RecipeRevision ==
                          returnedCommit.RecipeRevision &&
                      Strength(panel.SelectedFrame) == 0.35 &&
                      Strength(panel.DefectLayers.PreviewFrame) == 0.35,
                    "defect_layer_frame_state_failed_commit_exposes_committed_preview");

                GrainMendStrokeSession failedBrush = new();
                failedBrush.ChangeFrame(sourceIdText);
                failedBrush.Select(GrainMendTool.Brush);
                Check(failedBrush.Begin(new DefectPoint(0.2, 0.2), false) &&
                      failedBrush.Continue(new DefectPoint(0.3, 0.3)) &&
                      failedBrush.Finish(panel, out _) &&
                      failedBrush.ApplyPaintedStrokes(
                          panel,
                          out LibraryFrameError failedBrushError) &&
                      failedBrushError != LibraryFrameError.None &&
                      failedBrush.HasPaintedStrokes,
                    "grain_mend_failed_brush_apply_keeps_the_painted_draft");
            }

            Check(host.EditFrameRecord(
                    copyId,
                    record =>
                    {
                        JsonObject updated = record.DeepClone().AsObject();
                        updated[LibraryFrameReader.IsPreviewScanName] = true;
                        return new LibraryFrameWriteResult(updated, LibraryFrameError.None);
                    }) == LibraryFrameError.None &&
                  panel.Select(copyId) &&
                  panel.SelectedFrame is { IsPreviewScan: true, DefectReviewMark: null } &&
                  Projected(panel) is { DoneVisible: true, DoneEnabled: true },
                "defect_layer_preview_scan_keeps_macos_done_projection");
            Check(panel.MarkDefectRecipeReviewed() == LibraryFrameError.None &&
                  panel.SelectedFrame is { IsPreviewScan: true, DefectReviewMark: null } &&
                  Projected(panel) is { Reviewed: false, DoneVisible: true, DoneEnabled: true },
                "defect_layer_preview_scan_done_does_not_write_review");
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

    private static double? Strength(LibraryFrameSnapshot? frame) =>
        frame?.DefectRecipe?.Items.Single().Strength;

    private static DefectLayerSectionState Projected(
        DevelopPanelState panel,
        DefectReviewMark? reviewed = null) =>
        DefectLayerProjection.Create(
            panel.DefectLayers.PreviewFrame,
            ProjectionText,
            panel.DefectLayers.MaskPreviewId,
            reviewed,
            isRemovingDefects: false);

    private static DefectReviewMark ReviewOf(DefectRecipeSnapshot recipe) =>
        new(
            recipe.RecipeRevision,
            recipe.RecipeSha256,
            recipe.SourceIdentity!.Value.Sha256);

    private static DefectReviewMark ReviewOf(DefectReviewMarkRecord mark) =>
        new(mark.RecipeRevision, mark.RecipeSha256, mark.SourceIdentitySha256);

    private static double? ProjectedStrength(DevelopPanelState panel) =>
        Projected(panel).Rows.Single().Strength;

    private static readonly DefectLayerText ProjectionText = new(
        "Layers",
        "%d",
        "%d",
        "%d",
        "%d",
        "%d",
        "Brush",
        "Clone",
        "%@ %.0f%%",
        new Dictionary<DefectClassification, string>(),
        "Strength",
        "Enable",
        "Disable",
        "Show Mask",
        "Hide Mask",
        "Delete",
        "Done");
}
