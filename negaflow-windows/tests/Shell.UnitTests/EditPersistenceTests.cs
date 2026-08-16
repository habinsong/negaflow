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
        VerifyBrushStrokeReachesTheEngine();
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
                new ToneLimits(5.0f, 1.0f, 0.0, 1.0),
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
            Check(panel.RemoveDefectEdits(DefectEditLabelKind.Automatic) ==
                    LibraryFrameError.None &&
                !panel.HasDefectEdits(DefectEditLabelKind.Automatic) &&
                panel.HasDefectEdits(DefectEditKind.Clone),
                "defect_editor_removes_only_the_selected_label");

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

            // 변위가 0 인 복제 도장은 아무 일도 하지 않으므로 남기지 않습니다.
            Check(DefectStrokeRecipeBuilder.AppendCloneStroke(
                    frameId,
                    new DefectSourceIdentity(8, new string('a', 64)),
                    null,
                    points,
                    DevelopPanelState.DefaultCloneDiameterPixels,
                    0.0,
                    0.0,
                    new DefectSize(4000, 3000)) is null,
                "clone_stroke_rejects_zero_offset");
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
