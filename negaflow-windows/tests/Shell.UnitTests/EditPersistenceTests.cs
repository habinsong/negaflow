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

internal static class EditPersistenceTests
{
    public static void Run()
    {
        VerifyEditsSurviveClose();
        VerifyAutoGuidedHistoryPersistsMonotonicRevisions();
        VerifyInterleavedHistoryKeepsLatestDefectRecipes();
        VerifyFirstDefectCrashOrphanRollsBackOnRestart();
        VerifyBrushStrokeReachesTheEngine();
    }

    private static void VerifyAutoGuidedHistoryPersistsMonotonicRevisions()
    {
        string testParent = Path.Combine(AppContext.BaseDirectory, "grain-mend-history-tests");
        string isolatedBase = Path.Combine(
            testParent,
            $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        Guid frameId = Guid.Parse("816b79a1-1584-4ee3-a46d-9c76853ed3c8");
        string frameIdText = frameId.ToString("D");
        string sourcePath = Path.Combine(isolatedBase, "scans", "AUTO_0001.tif");
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(sourcePath)!);
            File.WriteAllBytes(sourcePath, [1, 3, 5, 7, 9, 11, 13, 15]);
            using (CatalogSession seed = CatalogSession.Open(roots).Session!)
            {
                JsonObject payload = FrameRecord(frameIdText, "AUTO_0001.tif", 0.0);
                payload["rawScanPath"] = sourcePath;
                Check(seed.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] =
                        [new CatalogEntityRow(frameIdText, payload)],
                    })).IsSuccess, "grain_mend_history_seed");
            }

            DefectEditItem automatic = GrainMendRegionEdit.From(
                [0, 0, 0, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
                4,
                4,
                100,
                100,
                0,
                0,
                100,
                100,
                1,
                automatic: true)!;
            DefectEditItem guided = GrainMendRegionEdit.From(
                [0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 0, 0, 0, 0, 0, 0],
                4,
                4,
                100,
                100,
                0,
                0,
                100,
                100,
                1,
                automatic: false)!;

            using (LibraryHostService host = new(
                new FakeDispatcher(accepts: true),
                new FakeExporter(_ => OkResult()),
                TestSourceMetadata))
            {
                Check(host.Open(roots) == LibraryHostState.Open, "grain_mend_history_open");
                DevelopPanelState panel = new(
                    host,
                    new ToneLimits(5.0f, 1.0f, 2.0f, 0.0, 1.0),
                    new NegativeLimits(0.001f, 1.0f));
                Check(panel.Select(frameIdText), "grain_mend_history_select");
                Check(panel.AcceptDefectRegion(automatic) == LibraryFrameError.None &&
                      host.Frames.Single().DefectRecipe is
                          { RecipeRevision: 1, Items.Count: 1 },
                    "grain_mend_history_auto_revision_1");

                Check(host.Undo() == LibraryHostService.UndoActions.DefectEdit,
                    "grain_mend_history_undo_auto");
                Check(panel.Select(frameIdText), "grain_mend_history_reselect_after_auto_undo");
                Check(host.Frames.Single() is
                      { DefectRecipe: null, DefectRecipeRevision: 2 },
                    "grain_mend_history_undo_removes_recipe_at_revision_2");

                Check(panel.AcceptDefectRegion(guided) == LibraryFrameError.None &&
                      host.Frames.Single().DefectRecipe is { } guidedRecipe &&
                      guidedRecipe.RecipeRevision == 3 &&
                      guidedRecipe.Items.Single().Label.Kind == DefectEditLabelKind.Guided,
                    "grain_mend_history_next_guided_succeeds_at_revision_3");
                Check(host.Undo() == LibraryHostService.UndoActions.DefectEdit,
                    "grain_mend_history_undo_guided");
                Check(panel.Select(frameIdText), "grain_mend_history_reselect_after_guided_undo");
                Check(host.Frames.Single() is
                      { DefectRecipe: null, DefectRecipeRevision: 4 },
                    "grain_mend_history_second_undo_removes_recipe_at_revision_4");

                string? redoActionBeforeFailure = host.RedoActionName;
                LibraryFrameError failed = host.AppendDefectStroke(
                    frameIdText,
                    (identity, existing) => existing is null
                        ? null
                        : DefectRecipeSnapshot.Create(
                            frameId,
                            existing.RecipeRevision,
                            identity,
                            [automatic]));
                Check(failed == LibraryFrameError.InvalidDefectRecipe &&
                      host.CanRedo &&
                      host.RedoActionName == redoActionBeforeFailure &&
                      host.Frames.Single() is
                          { DefectRecipe: null, DefectRecipeRevision: 4 },
                    "grain_mend_history_failed_auto_preserves_existing_redo");

                Check(host.Redo() == LibraryHostService.UndoActions.DefectEdit,
                    "grain_mend_history_redo_guided_after_failed_auto");
                Check(host.Frames.Single().DefectRecipe is { } redone &&
                      redone.RecipeRevision == 5 &&
                      redone.Items.Single().Label.Kind == DefectEditLabelKind.Guided,
                    "grain_mend_history_redo_writes_exact_revision_5");

                Check(host.Edit(
                        frameIdText,
                        new LibraryFrameEdit(
                            new ToneAdjustment(2.5, 0, 0, 0, 0, 0),
                            null)) == LibraryFrameError.None &&
                      host.HasUnsavedChanges,
                    "grain_mend_history_dirty_catalog_before_existing_defect_write");
                LibraryFrameError dirtyConflict = host.AppendDefectStroke(
                    frameIdText,
                    (identity, existing) => existing is null
                        ? null
                        : DefectRecipeSnapshot.Create(
                            frameId,
                            existing.RecipeRevision,
                            identity,
                            [automatic]));
                Check(dirtyConflict == LibraryFrameError.InvalidDefectRecipe &&
                      !host.HasUnsavedChanges &&
                      host.Frames.Single().Tone.Exposure == 2.5 &&
                      host.Frames.Single().DefectRecipe is { } unchanged &&
                      unchanged.RecipeRevision == 5 &&
                      unchanged.Items.Single().Label.Kind == DefectEditLabelKind.Guided,
                    "grain_mend_history_dirty_catalog_flushes_before_sidecar_attempt");
            }

            using LibraryDocument reopened = LibraryDocument.Open(roots).Document!;
            Check(reopened.Frames.Single() is
                  { DefectRecipe: { RecipeRevision: 5 }, DefectRecipeRevision: 5 } &&
                  reopened.Frames.Single().Tone.Exposure == 2.5,
                "grain_mend_history_recipe_persists_after_restart");
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

    private static void VerifyInterleavedHistoryKeepsLatestDefectRecipes()
    {
        string testParent = Path.Combine(AppContext.BaseDirectory, "grain-mend-interleaved-history-tests");
        string isolatedBase = Path.Combine(testParent, $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        Guid frameA = Guid.Parse("4e741eb1-94ef-41d7-a42c-63dc596cb7fe");
        Guid frameB = Guid.Parse("c4366bbd-ff6f-41ae-b855-64bbe10c9628");
        Guid frameC = Guid.Parse("8c4f333b-f629-4bdc-b053-8b7631db03fc");
        string idA = frameA.ToString("D");
        string idB = frameB.ToString("D");
        string idC = frameC.ToString("D");
        string sourceA = Path.Combine(isolatedBase, "scans", "A.tif");
        string sourceB = Path.Combine(isolatedBase, "scans", "B.tif");
        string sourceC = Path.Combine(isolatedBase, "scans", "C.tif");
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(sourceA)!);
            File.WriteAllBytes(sourceA, [1, 2, 3, 4]);
            File.WriteAllBytes(sourceB, [5, 6, 7, 8]);
            File.WriteAllBytes(sourceC, [9, 10, 11, 12]);
            using (CatalogSession seed = CatalogSession.Open(roots).Session!)
            {
                JsonObject payloadA = FrameRecord(idA, "A.tif", 0.0);
                payloadA["rawScanPath"] = sourceA;
                JsonObject payloadB = FrameRecord(idB, "B.tif", 0.0);
                payloadB["rawScanPath"] = sourceB;
                JsonObject payloadC = FrameRecord(idC, "C.tif", 0.0);
                payloadC["rawScanPath"] = sourceC;
                Check(seed.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] =
                        [new(idA, payloadA), new(idB, payloadB), new(idC, payloadC)],
                    })).IsSuccess, "grain_mend_interleaved_seed");
            }

            DefectEditItem automatic = GrainMendRegionEdit.From(
                [0, 0, 0, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
                4, 4, 100, 100, 0, 0, 100, 100, 1, automatic: true)!;
            DefectEditItem guided = GrainMendRegionEdit.From(
                [0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 0, 0, 0, 0, 0, 0],
                4, 4, 100, 100, 0, 0, 100, 100, 1, automatic: false)!;

            using (LibraryHostService host = new(
                new FakeDispatcher(accepts: true),
                new FakeExporter(_ => OkResult()),
                TestSourceMetadata))
            {
                Check(host.Open(roots) == LibraryHostState.Open, "grain_mend_interleaved_open");
                DevelopPanelState panel = new(
                    host,
                    new ToneLimits(5.0f, 1.0f, 2.0f, 0.0, 1.0),
                    new NegativeLimits(0.001f, 1.0f));
                Check(panel.Select(idA) &&
                      panel.AcceptDefectRegion(automatic) == LibraryFrameError.None,
                    "grain_mend_interleaved_auto_a_revision_1");
                Check(panel.Select(idB) &&
                      panel.AcceptDefectRegion(guided) == LibraryFrameError.None,
                    "grain_mend_interleaved_guided_b_revision_1");

                Check(host.Undo() == LibraryHostService.UndoActions.DefectEdit &&
                      host.Frames.Single(frame => frame.Id == idA).DefectRecipe?.RecipeRevision == 1 &&
                      host.Frames.Single(frame => frame.Id == idB) is
                          { DefectRecipe: null, DefectRecipeRevision: 2 },
                    "grain_mend_interleaved_undo_b_keeps_a_revision_1");
                Check(host.Undo() == LibraryHostService.UndoActions.DefectEdit &&
                      host.Frames.Single(frame => frame.Id == idA) is
                          { DefectRecipe: null, DefectRecipeRevision: 2 } &&
                      host.Frames.Single(frame => frame.Id == idB) is
                          { DefectRecipe: null, DefectRecipeRevision: 2 },
                    "grain_mend_interleaved_undo_a_keeps_b_revision_2");
                Check(host.Redo() == LibraryHostService.UndoActions.DefectEdit &&
                      host.Frames.Single(frame => frame.Id == idA).DefectRecipe?.RecipeRevision == 3,
                    "grain_mend_interleaved_redo_a_revision_3");
                Check(host.Redo() == LibraryHostService.UndoActions.DefectEdit &&
                      host.Frames.Single(frame => frame.Id == idA).DefectRecipe?.RecipeRevision == 3 &&
                      host.Frames.Single(frame => frame.Id == idB).DefectRecipe?.RecipeRevision == 3,
                    "grain_mend_interleaved_redo_b_does_not_rewind_a");

                Check(panel.Select(idA) &&
                      panel.AcceptDefectRegion(guided with { Id = Guid.NewGuid() }) == LibraryFrameError.None &&
                      host.Frames.Single(frame => frame.Id == idA).DefectRecipe is
                          { RecipeRevision: 4, Items.Count: 2 },
                    "grain_mend_interleaved_next_a_edit_reaches_revision_4");
                Check(host.EditUndoable(
                        idA,
                        LibraryHostService.UndoActions.DevelopAdjustment,
                        new LibraryFrameEdit(
                            new ToneAdjustment(1.0, 0, 0, 0, 0, 0),
                            null)) == LibraryFrameError.None,
                    "grain_mend_interleaved_tone_edit");
                Check(host.Undo() == LibraryHostService.UndoActions.DevelopAdjustment,
                    "grain_mend_interleaved_undo_tone");
                Check(host.Undo() == LibraryHostService.UndoActions.DefectEdit &&
                      host.Frames.Single(frame => frame.Id == idA).DefectRecipe?.RecipeRevision == 5,
                    "grain_mend_interleaved_undo_defect_after_tone");
                Check(host.Redo() == LibraryHostService.UndoActions.DefectEdit &&
                      host.Frames.Single(frame => frame.Id == idA).DefectRecipe?.RecipeRevision == 6,
                    "grain_mend_interleaved_redo_defect_after_tone");
                Check(host.Redo() == LibraryHostService.UndoActions.DevelopAdjustment &&
                      host.Frames.Single(frame => frame.Id == idA).DefectRecipe?.RecipeRevision == 6 &&
                      host.Frames.Single(frame => frame.Id == idB).DefectRecipe?.RecipeRevision == 3,
                    "grain_mend_interleaved_redo_tone_keeps_latest_recipes");
                Check(panel.Select(idB) &&
                      panel.AcceptDefectRegion(automatic with { Id = Guid.NewGuid() }) ==
                          LibraryFrameError.None &&
                      host.Frames.Single(frame => frame.Id == idB).DefectRecipe is
                          { RecipeRevision: 4, Items.Count: 2 },
                    "grain_mend_interleaved_next_b_edit_reaches_revision_4");
            }

            using (LibraryHostService reopened = new(
                       new FakeDispatcher(accepts: true),
                       new FakeExporter(_ => OkResult()),
                       TestSourceMetadata))
            {
                Check(reopened.Open(roots) == LibraryHostState.Open &&
                      reopened.Frames.Single(frame => frame.Id == idA) is
                          { DefectRecipe: { RecipeRevision: 6 }, DefectRecipeRevision: 6 } &&
                      reopened.Frames.Single(frame => frame.Id == idB) is
                          { DefectRecipe: { RecipeRevision: 4 }, DefectRecipeRevision: 4 } &&
                      reopened.Frames.Single(frame => frame.Id == idC).DefectRecipe is null,
                    "grain_mend_interleaved_recipes_persist_after_restart");

                Check(reopened.EditUndoable(
                        idC,
                        LibraryHostService.UndoActions.DevelopAdjustment,
                        new LibraryFrameEdit(
                            new ToneAdjustment(1.25, 0, 0, 0, 0, 0),
                            null)) == LibraryFrameError.None,
                    "grain_mend_generic_before_first_defect_tone");
                DevelopPanelState reversePanel = new(
                    reopened,
                    new ToneLimits(5.0f, 1.0f, 2.0f, 0.0, 1.0),
                    new NegativeLimits(0.001f, 1.0f));
                Check(reversePanel.Select(idC) &&
                      reversePanel.AcceptDefectRegion(automatic with { Id = Guid.NewGuid() }) ==
                          LibraryFrameError.None &&
                      reopened.Frames.Single(frame => frame.Id == idC).DefectRecipe is
                          { RecipeRevision: 1, Items.Count: 1 },
                    "grain_mend_generic_first_defect_revision_1");
                Check(reopened.Undo() == LibraryHostService.UndoActions.DefectEdit &&
                      reopened.Frames.Single(frame => frame.Id == idC) is
                          { DefectRecipe: null, DefectRecipeRevision: 2 },
                    "grain_mend_generic_defect_undo_removes_recipe_revision_2");
                Check(reopened.Undo() == LibraryHostService.UndoActions.DevelopAdjustment &&
                      reopened.Frames.Single(frame => frame.Id == idC) is
                          { DefectRecipe: null, DefectRecipeRevision: 2 },
                    "grain_mend_generic_undo_preserves_removed_recipe_revision_2");
                Check(reversePanel.Select(idC) &&
                      reversePanel.AcceptDefectRegion(guided with { Id = Guid.NewGuid() }) ==
                          LibraryFrameError.None &&
                      reopened.Frames.Single(frame => frame.Id == idC).DefectRecipe is
                          { RecipeRevision: 3, Items.Count: 1 } latest &&
                      latest.Items.Single().Label.Kind == DefectEditLabelKind.Guided,
                    "grain_mend_generic_next_guided_revision_3");

                Check(reopened.RemoveFrames([idA]) == 1 &&
                      reopened.Undo() == LibraryHostService.UndoActions.RemoveFrames &&
                      reopened.Frames.Single(frame => frame.Id == idA).DefectRecipe is
                          { RecipeRevision: 6 },
                    "grain_mend_removed_frame_undo_restores_persisted_recipe");
                Check(reopened.Redo() == LibraryHostService.UndoActions.RemoveFrames &&
                      reopened.Frames.All(frame => frame.Id != idA) &&
                      reopened.Undo() == LibraryHostService.UndoActions.RemoveFrames &&
                      reopened.Frames.Single(frame => frame.Id == idA).DefectRecipe is
                          { RecipeRevision: 6 },
                    "grain_mend_removed_frame_redo_undo_restores_persisted_recipe");
            }

            using LibraryDocument final = LibraryDocument.Open(roots).Document!;
            Check(final.Frames.Single(frame => frame.Id == idC) is
                  { DefectRecipe: { RecipeRevision: 3 }, DefectRecipeRevision: 3 },
                "grain_mend_generic_reverse_order_recipe_persists");
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

    private static void VerifyFirstDefectCrashOrphanRollsBackOnRestart()
    {
        string testParent = Path.Combine(AppContext.BaseDirectory, "grain-mend-orphan-recovery-tests");
        string isolatedBase = Path.Combine(testParent, $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        Guid frameId = Guid.Parse("d550f74f-1297-408a-ab5e-23eb364cd2a1");
        string frameIdText = frameId.ToString("D");
        string sourcePath = Path.Combine(isolatedBase, "scans", "ORPHAN.tif");
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(sourcePath)!);
            File.WriteAllBytes(sourcePath, [10, 20, 30, 40]);
            Check(DefectSourceIdentityReader.TryRead(
                    sourcePath,
                    out DefectSourceIdentity identity),
                "grain_mend_orphan_source_identity");
            DefectEditItem orphanAutomatic = GrainMendRegionEdit.From(
                [0, 0, 0, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
                4, 4, 100, 100, 0, 0, 100, 100, 1, automatic: true)!;
            DefectEditItem replacementGuided = GrainMendRegionEdit.From(
                [0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 0, 0, 0, 0, 0, 0],
                4, 4, 100, 100, 0, 0, 100, 100, 1, automatic: false)!;

            using (CatalogSession crashed = CatalogSession.Open(roots).Session!)
            {
                JsonObject payload = FrameRecord(frameIdText, "ORPHAN.tif", 0.0);
                payload["rawScanPath"] = sourcePath;
                Check(crashed.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] = [new(frameIdText, payload)],
                    })).IsSuccess, "grain_mend_orphan_catalog_seed");
                Check(crashed.WriteDefectRecipe(DefectRecipeSnapshot.Create(
                        frameId,
                        1,
                        identity,
                        [orphanAutomatic])).IsSuccess,
                    "grain_mend_orphan_sidecar_published_without_catalog_commit");
            }

            using (LibraryHostService host = new(
                new FakeDispatcher(accepts: true),
                new FakeExporter(_ => OkResult()),
                TestSourceMetadata))
            {
                Check(host.Open(roots) == LibraryHostState.Open &&
                      host.Frames.Single().DefectRecipe is null,
                    "grain_mend_orphan_restart_rolls_back_uncommitted_sidecar");
                DevelopPanelState panel = new(
                    host,
                    new ToneLimits(5.0f, 1.0f, 2.0f, 0.0, 1.0),
                    new NegativeLimits(0.001f, 1.0f));
                Check(panel.Select(frameIdText) &&
                      panel.AcceptDefectRegion(replacementGuided) == LibraryFrameError.None &&
                      host.Frames.Single().DefectRecipe is { RecipeRevision: 1 } written &&
                      written.Items.Single().Label.Kind == DefectEditLabelKind.Guided,
                    "grain_mend_orphan_next_revision_1_edit_succeeds");
            }

            using LibraryDocument reopened = LibraryDocument.Open(roots).Document!;
            Check(reopened.Frames.Single() is
                  { DefectRecipe: { RecipeRevision: 1 }, DefectRecipeRevision: 1 },
                "grain_mend_orphan_replacement_persists_after_restart");
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

    private static void VerifyEditsSurviveClose()
    {
        string testParent = Path.Combine(AppContext.BaseDirectory, "edit-persistence-tests");
        string isolatedBase = Path.Combine(
            testParent,
            $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        try
        {
            using (CatalogSession seed = CatalogSession.Open(roots).Session!)
            {
                Check(seed.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] =
                        [new("frame-1", FrameRecord("frame-1", "IMG_0001.tif", 0.0))],
                    })).IsSuccess, "edit_persistence_seed");
            }

            using (LibraryHostService host = new(
                new FakeDispatcher(accepts: true),
                new FakeExporter(_ => OkResult()),
                TestSourceMetadata))
            {
                Check(host.Open(roots) == LibraryHostState.Open, "edit_persistence_open");
                Check(host.Edit(
                        "frame-1",
                        new LibraryFrameEdit(
                            new ToneAdjustment(2.25, 0, 0, 0, 0, 0),
                            null)) == LibraryFrameError.None,
                    "edit_persistence_edit");
                // 예약된 저장이 울리기 전에 닫습니다. macOS 도 1.5 초를 기다리므로 그 사이에
                // 닫는 것이 가장 흔한 데이터 손실 상황입니다.
            }

            using LibraryDocument reopened = LibraryDocument.Open(roots).Document!;
            Check(reopened.Frames.Single().Tone.Exposure == 2.25,
                "edit_persistence_close_writes_pending_edit");
            Check(!reopened.IsDirty, "edit_persistence_load_is_not_dirty");
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

    /// <summary>
    /// 캔버스 획 하나가 sidecar 와 catalog 를 지나 엔진 요청까지 가는지 봅니다. 이 경로가
    /// 이어져야 GrainMend 브러시가 실제로 사진을 고칩니다.
    /// </summary>
    private static void VerifyBrushStrokeReachesTheEngine()
    {
        string testParent = Path.Combine(AppContext.BaseDirectory, "brush-stroke-tests");
        string isolatedBase = Path.Combine(
            testParent,
            $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        Guid frameId = Guid.Parse("2f8a1d4c-7b90-4a1e-9f33-51c2b0d6ee71");
        string sourcePath = Path.Combine(isolatedBase, "scans", "BRUSH_0001.tif");
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(sourcePath)!);
            File.WriteAllBytes(sourcePath, [1, 2, 3, 4, 5, 6, 7, 8]);

            using (CatalogSession seed = CatalogSession.Open(roots).Session!)
            {
                JsonObject payload = FrameRecord(frameId.ToString("D"), "BRUSH_0001.tif", 0.0);
                payload["rawScanPath"] = sourcePath;
                payload["sourceMetadata"] = new JsonObject
                {
                    ["fileBytes"] = 8,
                    ["pixelWidth"] = 100,
                    ["pixelHeight"] = 100,
                    ["samplesPerPixel"] = 3,
                    ["bitsPerSample"] = 16,
                    ["sampleFormat"] = 1,
                    ["orientation"] = 1,
                };
                Check(seed.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] =
                        [new CatalogEntityRow(frameId.ToString("D"), payload)],
                    })).IsSuccess, "brush_stroke_seed");
            }

            using LibraryHostService host = new(
                new FakeDispatcher(accepts: true),
                new FakeExporter(_ => OkResult()),
                TestSourceMetadata);
            Check(host.Open(roots) == LibraryHostState.Open, "brush_stroke_open");
            DevelopPanelState panel = new(
                host,
                new ToneLimits(5.0f, 1.0f, 2.0f, 0.0, 1.0),
                new NegativeLimits(0.001f, 1.0f));
            Check(panel.Select(frameId.ToString("D")), "defect_editor_selects_frame");

            DefectPoint[] points =
            [
                new(0.25, 0.25),
                new(0.30, 0.28),
                new(0.35, 0.31),
            ];
            Check(panel.AddBrushStroke(points) == LibraryFrameError.None,
                "brush_stroke_appends");

            LibraryFrameSnapshot brushed = host.Frames.Single();
            Check(brushed.DefectRecipe?.Items.Count == 1 &&
                brushed.DefectRecipe.Items[0].Kind == DefectEditKind.Brush &&
                brushed.DefectRecipe.Items[0].Strokes?.Single().Points.Count == 3,
                "brush_stroke_lands_in_the_recipe");

            DevelopRequestResult request = DevelopRequestFactory.Create(
                brushed,
                Path.Combine(isolatedBase, "brush.png"));
            Check(request.Request?.DefectBrushes.Count == 1 &&
                request.Request.DefectEditOrder.Count == 1 &&
                request.Request.DefectSourceIdentity is not null,
                "brush_stroke_reaches_the_develop_request");

            // 두 번째 획은 개정 번호를 올리며 앞의 획을 지우지 않습니다.
            Check(panel.AddBrushStroke(
                    [new DefectPoint(0.6, 0.6), new DefectPoint(0.65, 0.62)]) ==
                    LibraryFrameError.None,
                "brush_stroke_second_appends");
            Check(host.Frames.Single().DefectRecipe is { } second &&
                second.Items.Count == 2 && second.RecipeRevision == 2UL,
                "brush_stroke_keeps_previous_edits");

            // 도구별 초기화: 브러시 편집만 지우고 나머지는 남습니다.
            Check(panel.AddCloneStroke(
                    [new DefectPoint(0.4, 0.4), new DefectPoint(0.42, 0.41)],
                    new DefectPoint(0.45, 0.45)) == LibraryFrameError.None,
                "clone_stroke_appends");
            Check(host.Frames.Single().DefectRecipe?.Items.Count == 3,
                "clone_stroke_joins_brush_edits");
            Check(host.Frames.Single().DefectRecipe?.Items[^1].CloneStrokes?.Single().Diameter ==
                    DevelopPanelState.DefaultCloneDiameterPixels,
                "clone_stroke_uses_the_macos_pixel_diameter");
            Check(host.Frames.Single().DefectRecipe?.Items[^1].Label ==
                    new DefectEditLabel(
                        DefectEditLabelKind.Clone,
                        (int)DevelopPanelState.DefaultCloneDiameterPixels),
                "clone_stroke_label_uses_the_pixel_diameter");

            Check(panel.RemoveDefectEdits(DefectEditKind.Brush) == LibraryFrameError.None,
                "brush_reset_writes");
            Check(host.Frames.Single().DefectRecipe is { } afterReset &&
                afterReset.Items.Count == 1 &&
                afterReset.Items[0].Kind == DefectEditKind.Clone,
                "brush_reset_keeps_clone_edits");

            Check(panel.TryMapDisplayRectToRaw(
                    new DefectRect(0.2, 0.3, 0.4, 0.5),
                    out DefectRect mappedRect) &&
                Near(mappedRect.X, 0.2) && Near(mappedRect.Y, 0.3) &&
                Near(mappedRect.Width, 0.4) && Near(mappedRect.Height, 0.5),
                "defect_editor_maps_identity_display_rect_to_raw");

            DefectEditItem acceptedRegion = GrainMendRegionEdit.From(
                [0, 0, 0, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
                4,
                4,
                100,
                100,
                0,
                0,
                100,
                100,
                1,
                automatic: true)!;
            Check(panel.AcceptDefectRegion(acceptedRegion) == LibraryFrameError.None &&
                panel.HasDefectEdits(DefectEditLabelKind.Automatic),
                "defect_editor_accepts_reviewed_region");
            DefectEditItem guidedRegion = acceptedRegion with
            {
                Id = Guid.NewGuid(),
                Label = acceptedRegion.Label with { Kind = DefectEditLabelKind.Guided },
            };
            Check(panel.AcceptDefectRegion(guidedRegion) == LibraryFrameError.None &&
                panel.HasDefectEdits(DefectEditLabelKind.Guided),
                "defect_editor_accepts_guided_region_beside_automatic");
            Check(panel.RemoveDefectEdits(DefectEditKind.Region) ==
                    LibraryFrameError.None &&
                !panel.HasDefectEdits(DefectEditLabelKind.Automatic) &&
                !panel.HasDefectEdits(DefectEditLabelKind.Guided) &&
                panel.HasDefectEdits(DefectEditKind.Clone),
                "defect_editor_region_reset_removes_auto_and_guided");

            LibraryFrameError firstCloneError = panel.AddCloneStroke(
                    [new DefectPoint(0.2, 0.5)],
                    new DefectPoint(0.8, 0.5),
                    alignedRawOffset: null,
                    out DefectPoint firstOffset,
                    diameter: DevelopPanelState.DefaultCloneDiameterPixels,
                    hardness: DefectStrokeRecipeBuilder.DefaultCloneHardness);
            Check(firstCloneError == LibraryFrameError.None,
                $"clone_panel_commits_the_first_aligned_stroke_{firstCloneError}");
            LibraryFrameError secondCloneError = panel.AddCloneStroke(
                    [new DefectPoint(0.4, 0.5)],
                    new DefectPoint(0.8, 0.5),
                    firstOffset,
                    out DefectPoint secondOffset,
                    diameter: DevelopPanelState.DefaultCloneDiameterPixels,
                    hardness: DefectStrokeRecipeBuilder.DefaultCloneHardness);
            Check(secondCloneError == LibraryFrameError.None,
                $"clone_panel_commits_the_next_aligned_stroke_{secondCloneError}");
            DefectEditItem[] alignedItems =
            [.. host.Frames.Single().DefectRecipe!.Items.Where(item =>
                item.Kind == DefectEditKind.Clone)];
            Check(alignedItems.Length >= 2,
                "clone_panel_persists_both_aligned_strokes");
            Check(alignedItems.Length >= 2 &&
                firstOffset == secondOffset &&
                alignedItems[^2].CloneStrokes!.Single().OffsetX ==
                    alignedItems[^1].CloneStrokes!.Single().OffsetX &&
                alignedItems[^2].CloneStrokes!.Single().OffsetY ==
                    alignedItems[^1].CloneStrokes!.Single().OffsetY,
                "clone_panel_keeps_the_first_raw_offset_across_strokes");

            // macOS는 변위가 0인 항목도 ordered recipe에 남기고 renderer에서 no-op으로 처리합니다.
            DefectRecipeSnapshot? zeroOffset = DefectStrokeRecipeBuilder.AppendCloneStroke(
                    frameId,
                    new DefectSourceIdentity(8, new string('a', 64)),
                    null,
                    [new DefectPoint(0.4, 0.4), new DefectPoint(0.40005, 0.40005)],
                    DevelopPanelState.DefaultCloneDiameterPixels,
                    0.0,
                    0.0,
                    new DefectSize(4000, 3000));
            Check(zeroOffset?.Items.Single().CloneStrokes?.Single() is
                    { OffsetX: 0.0, OffsetY: 0.0, Points.Count: 2 },
                "clone_stroke_keeps_zero_offset_and_close_input_points");

            GrainMendStrokeSession brushSession = new();
            brushSession.ChangeFrame(frameId.ToString("D"));
            brushSession.Select(GrainMendTool.Brush);
            Check(brushSession.Begin(new DefectPoint(0.2, 0.2), false) &&
                  brushSession.Continue(new DefectPoint(0.20005, 0.20005)) &&
                  brushSession.Finish(panel, out _) &&
                  brushSession.Begin(new DefectPoint(0.6, 0.6), false) &&
                  brushSession.Continue(new DefectPoint(0.7, 0.7)) &&
                  brushSession.Finish(panel, out _) &&
                  brushSession.HasPaintedStrokes,
                "brush_draft_collects_two_complete_strokes");
            DefectRecipeSnapshot beforeBatch = host.Frames.Single().DefectRecipe!;
            Check(brushSession.ApplyPaintedStrokes(panel, out LibraryFrameError batchError) &&
                  batchError == LibraryFrameError.None &&
                  !brushSession.HasPaintedStrokes,
                "brush_draft_applies_in_one_product_call");
            DefectRecipeSnapshot afterBatch = host.Frames.Single().DefectRecipe!;
            Check(afterBatch.RecipeRevision == beforeBatch.RecipeRevision + 1UL &&
                  afterBatch.Items.Count == beforeBatch.Items.Count + 1 &&
                  afterBatch.Items[^1] is
                  {
                      Kind: DefectEditKind.Brush,
                      Label: { Kind: DefectEditLabelKind.Brush, Value: 2 },
                      Strokes.Count: 2,
                  } &&
                  afterBatch.Items[^1].Strokes![0].Points.Count == 2,
                "brush_batch_is_one_item_one_revision_and_preserves_close_points");
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

}
