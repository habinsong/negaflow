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
        VerifyInfraredHistoryAndFailedWritePreserveRedo();
        VerifyRowDeleteAndToolResetHistoryModes();
    }

    private static void VerifyInfraredDefectRecipeCoordinator()
    {
        Guid frameId = Guid.Parse("4fa76528-8ea7-49ef-af2a-cb1d24786216");
        InfraredDetectionResult detection = DetectionFixture();
        byte[] core = detection.Clusters.Single().CoreMaskRgba8;
        byte[] attenuation = detection.Clusters.Single().AttenuationR16;
        DefectSourceIdentity identity = new(1234, new string('a', 64));
        DefectRecipeSnapshot recipe = InfraredDefectRecipeCoordinator.CreateRecipe(
            frameId, identity, null, recipeRevision: 1, detection);
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
            Check(reopened.Frames.Single() is
                  { DefectRecipe: { RecipeRevision: 1 }, DefectRecipeRevision: 1 } &&
                  File.Exists(Path.Combine(
                      roots.DefectRecipeRoot,
                      $"{frameId:D}.json")),
                "infrared_recipe_restart_restores_persisted_layer");
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

    private static void VerifyInfraredHistoryAndFailedWritePreserveRedo()
    {
        string testParent = Path.Combine(AppContext.BaseDirectory, "infrared-history-tests");
        string isolatedBase = Path.Combine(testParent, $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        Guid frameA = Guid.Parse("21a796fc-4334-456f-a390-03bc78445cbf");
        Guid frameB = Guid.Parse("0462245e-903f-4052-bf1f-0fdd5e78dceb");
        string sourceA = Path.Combine(isolatedBase, "scans", "IR_A.tif");
        string sourceB = Path.Combine(isolatedBase, "scans", "IR_B.tif");
        InfraredDetectionResult detection = DetectionFixture();
        DefectEditItem automaticA = GrainMendRegionEdit.From(
            [0, 0, 0, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            4, 4, 20, 10, 0, 0, 20, 10, 1, automatic: true)!;
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(sourceA)!);
            File.WriteAllBytes(sourceA, [2, 4, 6, 8, 10, 12, 14, 16]);
            File.WriteAllBytes(sourceB, [2, 4, 6, 8, 10, 12, 14, 16]);
            Check(DefectSourceIdentityReader.TryRead(sourceA, out DefectSourceIdentity identity),
                "infrared_history_source_identity");
            using (CatalogSession seed = CatalogSession.Open(roots).Session!)
            {
                JsonObject payloadA = FrameRecord(frameA.ToString("D"), "IR_A.tif", 0.0);
                payloadA["rawScanPath"] = sourceA;
                JsonObject payloadB = FrameRecord(frameB.ToString("D"), "IR_B.tif", 0.0);
                payloadB["rawScanPath"] = sourceB;
                Check(seed.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] =
                        [
                            new CatalogEntityRow(
                                frameA.ToString("D"),
                                payloadA),
                            new CatalogEntityRow(
                                frameB.ToString("D"),
                                payloadB),
                        ],
                    })).IsSuccess, "infrared_history_seed");
            }

            using (LibraryDocument document = LibraryDocument.Open(roots).Document!)
            {
                DefectRecipeSnapshot autoRecipe = DefectRecipeSnapshot.Create(
                    frameA,
                    1,
                    identity,
                    [automaticA]);
                Check(document.WriteDefectRecipe(frameA.ToString("D"), autoRecipe).IsSuccess,
                    "infrared_history_auto_seed");

                InfraredDefectApplyResult applied =
                    InfraredDefectRecipeCoordinator.ApplyDetection(
                        document,
                        document.Frames.Single(frame => frame.Id == frameA.ToString("D")),
                        frameA,
                        identity,
                        detection);
                Check(applied.IsSuccess && applied.Recipe is
                      { RecipeRevision: 2, Items.Count: 2 },
                    "infrared_history_apply_revision_2");

                Check(document.Undo() == LibraryHostService.UndoActions.DefectEdit &&
                      document.Frames.Single(frame => frame.Id == frameA.ToString("D"))
                          .DefectRecipe is { } undoRecipe &&
                      undoRecipe.RecipeRevision == 3 &&
                      undoRecipe.Items.Any(item => item.Kind == DefectEditKind.Infrared),
                    "infrared_history_general_undo_preserves_ir_at_revision_3");
                string? redoActionBeforeFailure = document.RedoActionName;

                LibraryFrameSnapshot staleFrameB = document.Frames.Single(
                    frame => frame.Id == frameB.ToString("D"));
                Check(document.RemoveFrames([frameB.ToString("D")]).Count == 1,
                    "infrared_history_remove_frame_before_late_apply");
                InfraredDefectApplyResult failed =
                    InfraredDefectRecipeCoordinator.ApplyDetection(
                        document,
                        staleFrameB,
                        frameB,
                        identity,
                        detection);
                Check(failed.Status == InfraredDefectApplyStatus.PersistenceFailed &&
                      document.CanRedo &&
                      document.RedoActionName == redoActionBeforeFailure &&
                      document.Frames.All(frame => frame.Id != frameB.ToString("D")),
                    "infrared_history_failed_write_preserves_existing_redo");

                Check(document.Redo() == LibraryHostService.UndoActions.DefectEdit &&
                      document.Frames.Single(frame => frame.Id == frameA.ToString("D"))
                          .DefectRecipe is { } redoRecipe &&
                      redoRecipe.RecipeRevision == 4 &&
                      redoRecipe.Items.Any(item => item.Kind == DefectEditKind.Infrared),
                    "infrared_history_redo_survives_other_frame_failure");
            }

            using (LibraryDocument reopened = LibraryDocument.Open(roots).Document!)
            {
                Check(reopened.Frames.Single(frame => frame.Id == frameA.ToString("D"))
                          is { DefectRecipe: { RecipeRevision: 4 }, DefectRecipeRevision: 4 },
                    "infrared_history_restart_restores_recipe_at_revision_4");

                InfraredDefectApplyResult reapplied =
                    InfraredDefectRecipeCoordinator.ApplyDetection(
                        reopened,
                        reopened.Frames.Single(frame => frame.Id == frameA.ToString("D")),
                        frameA,
                        identity,
                        detection);
                Check(reapplied.Status == InfraredDefectApplyStatus.DetectionFailed &&
                      reopened.Frames.Single(frame => frame.Id == frameA.ToString("D"))
                          .DefectRecipe is { RecipeRevision: 4, Items.Count: 2 },
                    "infrared_history_restart_does_not_duplicate_ir");

                Check(LibraryDefectEditor.AppendStroke(
                        reopened,
                        frameA.ToString("D"),
                        (sourceIdentity, existing) => existing is null
                            ? null
                            : DefectRecipeSnapshot.Create(
                                frameA,
                                checked(existing.RecipeRevision + 1),
                                sourceIdentity,
                                existing.Items
                                    .Where(item => item.Kind != DefectEditKind.Infrared)
                                    .ToArray()),
                        LibraryDefectHistoryMode.Exact) == LibraryFrameError.None &&
                      reopened.Frames.Single(frame => frame.Id == frameA.ToString("D"))
                          is { DefectRecipe: { RecipeRevision: 5 } remaining, DefectRecipeRevision: 5 } &&
                      remaining.Items.All(item => item.Kind != DefectEditKind.Infrared),
                    "infrared_history_explicit_ir_delete_uses_revision_5");
                Check(reopened.Undo() == LibraryHostService.UndoActions.DefectEdit &&
                      reopened.Frames.Single(frame => frame.Id == frameA.ToString("D"))
                          .DefectRecipe is { RecipeRevision: 6 } restoredDelete &&
                      restoredDelete.Items.Any(item => item.Kind == DefectEditKind.Infrared),
                    "infrared_history_exact_undo_restores_ir_at_revision_6");
                Check(reopened.Redo() == LibraryHostService.UndoActions.DefectEdit &&
                      reopened.Frames.Single(frame => frame.Id == frameA.ToString("D"))
                          .DefectRecipe is { RecipeRevision: 7 } removedAgain &&
                      removedAgain.Items.All(item => item.Kind != DefectEditKind.Infrared),
                    "infrared_history_exact_redo_removes_ir_at_revision_7");
            }

            using LibraryDocument finalReopen = LibraryDocument.Open(roots).Document!;
            Check(finalReopen.Frames.Single(frame => frame.Id == frameA.ToString("D"))
                      .DefectRecipe is { RecipeRevision: 7 } persisted &&
                  persisted.Items.All(item => item.Kind != DefectEditKind.Infrared),
                "infrared_history_exact_redo_persists_remaining_recipe_after_restart");
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

    private static void VerifyRowDeleteAndToolResetHistoryModes()
    {
        string testParent = Path.Combine(AppContext.BaseDirectory, "defect-history-mode-tests");
        string isolatedBase = Path.Combine(testParent, $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        Guid frameId = Guid.Parse("a77ea3bb-40fb-46cc-a5e4-88667d46a33e");
        string frameIdText = frameId.ToString("D");
        string sourcePath = Path.Combine(isolatedBase, "scans", "MODE.tif");
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(sourcePath)!);
            File.WriteAllBytes(sourcePath, [9, 7, 5, 3, 1]);
            Check(DefectSourceIdentityReader.TryRead(
                    sourcePath,
                    out DefectSourceIdentity identity),
                "defect_history_mode_source_identity");
            using (CatalogSession seed = CatalogSession.Open(roots).Session!)
            {
                JsonObject payload = FrameRecord(frameIdText, "MODE.tif", 0.0);
                payload["rawScanPath"] = sourcePath;
                DefectRecipeSnapshot legacyEmpty = DefectRecipeSnapshot.Create(
                    frameId,
                    recipeRevision: 1,
                    sourceIdentity: identity,
                    items: []);
                payload = DefectReviewTrackingCodec.Apply(
                    payload,
                    new DefectReviewMarkRecord(
                        legacyEmpty.RecipeRevision,
                        legacyEmpty.RecipeSha256,
                        identity.Sha256)).FrameRecord!;
                Check(seed.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] = [new(frameIdText, payload)],
                    })).IsSuccess, "defect_history_mode_seed");
                JsonObject declared = (JsonObject)payload.DeepClone();
                declared["hasDefectEdits"] = true;
                Directory.CreateDirectory(roots.DefectRecipeRoot);
                File.WriteAllBytes(
                    Path.Combine(roots.DefectRecipeRoot, $"{frameId:D}.json"),
                    JsonSerializer.SerializeToUtf8Bytes(new JsonObject
                    {
                        ["version"] = 2,
                        ["frameID"] = frameIdText,
                        ["fingerprintVersion"] = legacyEmpty.FingerprintVersion,
                        ["recipeRevision"] = JsonValue.Create(legacyEmpty.RecipeRevision),
                        ["recipeSHA256"] = legacyEmpty.RecipeSha256,
                        ["sourceIdentity"] = new JsonObject
                        {
                            ["byteCount"] = JsonValue.Create(identity.ByteCount),
                            ["sha256"] = identity.Sha256,
                        },
                        ["items"] = new JsonArray(),
                    }));
                Check(seed.Write(new CatalogSnapshot(
                        null,
                        new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                        {
                            [CatalogEntityTable.Frames] = [new(frameIdText, declared)],
                        })).IsSuccess,
                    "defect_history_mode_legacy_empty_recipe_seed");
            }

            DefectEditItem automatic = GrainMendRegionEdit.From(
                [0, 0, 0, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
                4, 4, 20, 10, 0, 0, 20, 10, 1, automatic: true)!;
            DefectEditItem infrared = InfraredDefectRecipeCoordinator.CreateRecipe(
                frameId,
                identity,
                null,
                recipeRevision: 1,
                DetectionFixture()).Items.Single();

            using LibraryHostService host = new(
                new FakeDispatcher(accepts: true),
                new FakeExporter(_ => OkResult()),
                TestSourceMetadata);
            Check(host.Open(roots) == LibraryHostState.Open &&
                  host.Frames.Single() is
                      { DefectRecipe: null, DefectRecipeRevision: 2 } &&
                  !File.Exists(Path.Combine(roots.DefectRecipeRoot, $"{frameId:D}.json")) &&
                  HasTrackedEmptyDefectState(host, frameIdText),
                "defect_history_mode_open_repairs_legacy_empty_recipe_revision_2");
            DevelopPanelState panel = new(
                host,
                new ToneLimits(5.0f, 1.0f, 2.0f, 0.0, 1.0),
                new NegativeLimits(0.001f, 1.0f));
            Check(panel.Select(frameIdText) &&
                  panel.AcceptDefectRegion(automatic) == LibraryFrameError.None &&
                  host.Frames.Single().DefectRecipe?.RecipeRevision == 3,
                "defect_history_mode_auto_revision_3_after_legacy_cleanup");
            Check(panel.DefectLayers.Remove(automatic.Id) == LibraryFrameError.None &&
                  host.Frames.Single() is
                      { DefectRecipe: null, DefectRecipeRevision: 4 } &&
                  !File.Exists(Path.Combine(roots.DefectRecipeRoot, $"{frameId:D}.json")) &&
                  HasTrackedEmptyDefectState(host, frameIdText),
                "defect_history_mode_row_delete_removes_recipe_revision_4");
            Check(host.AppendDefectStroke(
                    frameIdText,
                    (sourceIdentity, existing, nextRevision) => DefectRecipeSnapshot.Create(
                        frameId,
                        nextRevision,
                        sourceIdentity,
                        existing is null ? [infrared] : [.. existing.Items, infrared])) ==
                    LibraryFrameError.None,
                "defect_history_mode_late_ir_revision_5");
            Check(host.Undo() == LibraryHostService.UndoActions.DefectEdit &&
                  host.Frames.Single().DefectRecipe is { RecipeRevision: 6 } irNoOp &&
                  irNoOp.Items.Single().Kind == DefectEditKind.Infrared,
                "defect_history_mode_ir_noop_undo_preserves_ir_revision_6");
            Check(host.Undo() == LibraryHostService.UndoActions.DefectEdit &&
                  host.Frames.Single().DefectRecipe is { RecipeRevision: 7 } exactUndo &&
                  exactUndo.Items.Single().Id == automatic.Id,
                "defect_history_mode_row_delete_undo_is_exact_revision_7");

            Check(panel.Select(frameIdText) &&
                  panel.RemoveDefectEdits(DefectEditLabelKind.Automatic) ==
                      LibraryFrameError.None &&
                  host.Frames.Single() is
                      { DefectRecipe: null, DefectRecipeRevision: 8 },
                "defect_history_mode_tool_reset_removes_recipe_revision_8");
            DefectEditItem laterInfrared = infrared with { Id = Guid.NewGuid() };
            Check(host.AppendDefectStroke(
                    frameIdText,
                    (sourceIdentity, existing, nextRevision) => DefectRecipeSnapshot.Create(
                        frameId,
                        nextRevision,
                        sourceIdentity,
                        existing is null
                            ? [laterInfrared]
                            : [.. existing.Items, laterInfrared])) == LibraryFrameError.None,
                "defect_history_mode_second_late_ir_revision_9");
            Check(host.Undo() == LibraryHostService.UndoActions.DefectEdit &&
                  host.Frames.Single().DefectRecipe is { RecipeRevision: 10 } secondIrNoOp &&
                  secondIrNoOp.Items.Single().Id == laterInfrared.Id,
                "defect_history_mode_second_ir_noop_undo_revision_10");
            Check(host.Undo() == LibraryHostService.UndoActions.DefectEdit &&
                  host.Frames.Single().DefectRecipe is { RecipeRevision: 11 } resetUndo &&
                  resetUndo.Items.Count == 2 &&
                  resetUndo.Items.Any(item => item.Id == automatic.Id) &&
                  resetUndo.Items.Any(item => item.Id == laterInfrared.Id),
                "defect_history_mode_tool_reset_undo_preserves_late_ir_revision_11");
            Check(panel.Select(frameIdText) &&
                  panel.RemoveNonInfraredDefectEdits() == LibraryFrameError.None,
                "defect_hud_reset_all_writes");
            Check(host.Frames.Single().DefectRecipe is { } irOnly &&
                  irOnly.Items.Count == 1 &&
                  irOnly.Items[0].Id == laterInfrared.Id,
                "defect_hud_reset_all_preserves_only_infrared");
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

    private static bool HasTrackedEmptyDefectState(
        LibraryHostService host,
        string frameId)
    {
        JsonObject? record = host.FrameRecord(frameId);
        return record is not null &&
            !record.ContainsKey("hasDefectEdits") &&
            record[DefectReviewTrackingCodec.TrackingName] is JsonObject tracking &&
            tracking.Count == 1 &&
            tracking["coverage"]?.GetValue<string>() == "tracked";
    }

    private static InfraredDetectionResult DetectionFixture()
    {
        byte[] core = new byte[4 * 3 * 4];
        core[4] = core[5] = core[6] = core[7] = 255;
        byte[] attenuation = new byte[4 * 3 * 2];
        attenuation[2] = 0x00;
        attenuation[3] = 0x80;
        return new InfraredDetectionResult(
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
    }

}
