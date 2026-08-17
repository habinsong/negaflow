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

internal static class GrainMendRecipeTests
{
    public static void Run()
    {
        VerifyGrainMendRegionEdit();
        VerifyGrainMendReviewSession();
        VerifyGrainMendClassReview();
        VerifyGrainMendHudProjection();
        VerifyGrainMendWorkspaceStateAndOverlay();
        VerifyGrainMendDetectCoordinator();
    }

    /// <summary>
    /// 검출기가 분류를 냈을 때입니다. 성분 하나가 제외 단위여야 하고, 종류별 칩이 실제 개수와
    /// 평균 신뢰도를 내야 하며, 수락한 항목의 요약은 <b>남은 결함에서 다시 센 것</b>이어야
    /// 합니다 — 예전에는 "먼지 × 채택 화소" 를 지어냈습니다.
    /// </summary>
    private static void VerifyGrainMendClassReview()
    {
        const int width = 8;
        const int height = 6;
        byte[] rgba = new byte[width * height * 4];
        Mark(rgba, width, 1, 1);
        Mark(rgba, width, 6, 1);
        Mark(rgba, width, 2, 4);
        Mark(rgba, width, 3, 4);
        Mark(rgba, width, 4, 4);

        DefectPreviewComponent dustLeft = new(
            DefectClassification.Dust, 0.4, [Raw(1, 1)]);
        DefectPreviewComponent dustRight = new(
            DefectClassification.Dust, 0.6, [Raw(6, 1)]);
        DefectPreviewComponent scratch = new(
            DefectClassification.ScratchHorizontal,
            0.8,
            [Raw(2, 4), Raw(3, 4), Raw(4, 4)]);
        DefectEditItem item = new(
            Guid.Parse("3d0d9f7f-1a2b-4c3d-8e5f-6a7b8c9d0e1f"),
            DefectEditKind.Region,
            Enabled: true,
            Strength: 1.0,
            new DefectEditLabel(DefectEditLabelKind.Automatic, 3),
            new DefectEditSummary(
                DefectEditSummaryKind.ClassBreakdown,
                new DefectClassBreakdown(
                    [
                        new DefectClassCount(DefectClassification.Dust, 2),
                        new DefectClassCount(DefectClassification.ScratchHorizontal, 1),
                    ],
                    0.6)),
            new DefectSize(width, height),
            [dustLeft, dustRight, scratch])
        {
            RegionMask = new DefectMask(false, rgba),
            RegionRoi = new DefectRect(0.0, 0.0, width, height),
            RegionWidth = width,
            RegionHeight = height,
        };

        GrainMendReviewSession? review = GrainMendReviewSession.TryCreate(item);
        Check(review is { IsClassified: true, ComponentCount: 3, IncludedCount: 3 },
            "grain_mend_review_uses_the_detector_components_not_mask_blobs");
        if (review is null)
        {
            return;
        }

        IReadOnlyList<GrainMendClassSummary> summaries = review.ClassSummaries();
        Check(summaries.Count == 2 &&
            summaries[0] == new GrainMendClassSummary(
                DefectClassification.Dust, 2, 0.5, false) &&
            summaries[1] == new GrainMendClassSummary(
                DefectClassification.ScratchHorizontal, 1, 0.8, false),
            "grain_mend_review_summarises_each_class_in_definition_order");

        // 칩 한 번이면 그 종류가 통째로 빠집니다.
        Check(review.ToggleClass(DefectClassification.Dust) && review.IncludedCount == 1 &&
            review.ClassSummaries()[0].AllExcluded &&
            !review.ClassSummaries()[1].AllExcluded,
            "grain_mend_review_toggles_a_whole_class");

        DefectEditItem? accepted = review.BuildAcceptedEdit();
        Check(accepted is { Label.Value: 1, Preview.Count: 1 } &&
            accepted.Preview[0].Classification == DefectClassification.ScratchHorizontal &&
            accepted.Summary.ClassBreakdown is { MeanConfidence: 0.8 } breakdown &&
            breakdown.Counts.Count == 1 &&
            breakdown.Counts[0] == new DefectClassCount(
                DefectClassification.ScratchHorizontal, 1),
            "grain_mend_review_recounts_the_summary_from_the_survivors");
        Check(accepted is not null &&
            DefectMaskCodec.TryDecodeRgba8(
                accepted.RegionMask!, width, height, out byte[] selected) &&
            selected[((1 * width) + 1) * 4] == 0 &&
            selected[((1 * width) + 6) * 4] == 0 &&
            selected[((4 * width) + 3) * 4] == 255,
            "grain_mend_review_clears_only_the_excluded_class_pixels");

        Check(review.ToggleClass(DefectClassification.Dust) && review.IncludedCount == 3,
            "grain_mend_review_puts_a_class_back");

        // macOS nearestComponentID: 정확히 짚지 않아도 반경 안이면 잡습니다.
        Check(review.ToggleAtRaw(Raw(6, 0)) && review.IncludedCount == 2 &&
            review.IsExcludedAtRaw(Raw(6, 1)),
            "grain_mend_review_hits_a_component_near_the_click");

        // 분류가 없으면 종류별 칩도 없습니다 — 종류를 지어내지 않습니다.
        GrainMendReviewSession? unclassified = GrainMendReviewSession.TryCreate(
            item with { Preview = [] });
        Check(unclassified is { IsClassified: false } &&
            unclassified.ClassSummaries().Count == 0 &&
            !unclassified.ToggleClass(DefectClassification.Dust),
            "grain_mend_review_invents_no_class_without_a_detector_component");

        static DefectPoint Raw(int x, int y) =>
            new(x / (double)(width - 1), y / (double)(height - 1));

        static void Mark(byte[] rgba, int stride, int x, int y)
        {
            int offset = ((y * stride) + x) * 4;
            rgba[offset] = rgba[offset + 1] = rgba[offset + 2] = rgba[offset + 3] = 255;
        }
    }

    /// <summary>
    /// 캔버스 위 캡슐이 언제 무엇을 내는지입니다. 창을 띄우지 않고 확인할 수 있어야 "검출은
    /// 됐는데 칩이 안 뜬다" 를 좁힐 수 있습니다.
    /// </summary>
    private static void VerifyGrainMendHudProjection()
    {
        Check(!GrainMendHudProjection
                .Create(false, false, null, null, GrainMendTool.None).IsVisible &&
            !GrainMendHudProjection
                .Create(true, false, null, null, GrainMendTool.None).IsVisible,
            "grain_mend_hud_stays_out_of_the_way_without_a_tool");
        Check(GrainMendHudProjection
                .Create(true, false, null, null, GrainMendTool.Guided).Mode ==
                GrainMendHudMode.Waiting,
            "grain_mend_hud_waits_for_a_guided_drag");
        GrainMendHudState detecting = GrainMendHudProjection.Create(
            true, true, DefectEditLabelKind.Automatic, null, GrainMendTool.None);
        Check(detecting is { Mode: GrainMendHudMode.Detecting, RemoveEnabled: false } &&
            detecting.Chips.Count == 0,
            "grain_mend_hud_offers_nothing_while_detecting");
    }

    private static void VerifyGrainMendRegionEdit()
    {
        const int width = 8;
        const int height = 6;
        byte[] mask = new byte[width * height];
        mask[0] = 255;                       // 왼쪽 위
        mask[(3 * width) + 5] = 128;         // 가운데 어딘가
        mask[mask.Length - 1] = 200;         // 오른쪽 아래
        DefectEditItem? item = GrainMendRegionEdit.From(
            mask,
            width,
            height,
            sourceWidth: 8U,
            sourceHeight: 6U,
            roiX: 0U,
            roiY: 0U,
            roiWidth: 8U,
            roiHeight: 6U,
            acceptedPixels: 3U,
            automatic: true);
        Check(item is not null, "grain_mend_region_edit_built");
        if (item is null)
        {
            return;
        }
        Check(item.Kind == DefectEditKind.Region &&
            item.Label.Kind == DefectEditLabelKind.Automatic && item.Label.Value == 3,
            "grain_mend_region_edit_labels_the_accepted_count");
        Check(item.RegionWidth == width && item.RegionHeight == height &&
            item.RegionRoi == new DefectRect(0.0, 0.0, width, height) &&
            item.BaseSize == new DefectSize(width, height),
            "grain_mend_region_edit_keeps_the_analysis_geometry");

        byte[] rgba = item.RegionMask!.Data;
        Check(rgba.Length == width * height * 4, "grain_mend_region_edit_is_rgba8");
        // 표시된 화소는 네 채널 모두에 값이 들어가고, 나머지는 손대지 않습니다.
        Check(rgba[0] == 255 && rgba[1] == 255 && rgba[2] == 255 && rgba[3] == 255,
            "grain_mend_region_edit_widens_the_first_pixel");
        int middle = ((3 * width) + 5) * 4;
        Check(rgba[middle] == 128 && rgba[middle + 3] == 128,
            "grain_mend_region_edit_keeps_partial_values");
        Check(rgba[4] == 0 && rgba[5] == 0 && rgba[6] == 0 && rgba[7] == 0,
            "grain_mend_region_edit_leaves_unmarked_pixels_clear");

        // 축소된 부분 검출 마스크는 원본 좌표계의 작은 창으로 되돌아가야 합니다. 여기서
        // y-up 저장 좌표까지 확인해, 가이드 결과가 위아래 뒤집혀 저장되는 회귀를 막습니다.
        byte[] guidedMask = new byte[10 * 10];
        guidedMask[(4 * 10) + 3] = 255;
        DefectEditItem? guided = GrainMendRegionEdit.From(
            guidedMask,
            width: 10,
            height: 10,
            sourceWidth: 1000U,
            sourceHeight: 800U,
            roiX: 200U,
            roiY: 160U,
            roiWidth: 400U,
            roiHeight: 240U,
            acceptedPixels: 1U,
            automatic: false);
        Check(guided is not null &&
            guided.RegionRoi == new DefectRect(312.0, 512.0, 56.0, 40.0) &&
            guided.BaseSize == new DefectSize(1000.0, 800.0),
            "grain_mend_region_edit_projects_a_guided_roi_to_raw_y_up");

        // 아무것도 못 찾았으면 항목을 만들지 않습니다.
        Check(GrainMendRegionEdit.From(
                new byte[width * height], width, height,
                8U, 6U, 0U, 0U, 8U, 6U, 0U, true) is null,
            "grain_mend_region_edit_skips_an_empty_mask");
        // 크기가 안 맞는 마스크는 닫히는 쪽으로 거절합니다.
        Check(GrainMendRegionEdit.From(
                new byte[7], width, height,
                8U, 6U, 0U, 0U, 8U, 6U, 3U, true) is null,
            "grain_mend_region_edit_rejects_a_mismatched_mask");

        // 저장까지 통과해야 실제로 쓸 수 있습니다.
        DefectRecipeSnapshot? recipe = DefectRecipeSnapshot.Create(
            Guid.NewGuid(),
            1UL,
            new DefectSourceIdentity(1024, new string('b', 64)),
            [item]);
        // 검증기가 마스크를 zlib 으로 줄여 담습니다. 그래서 길이가 아니라 되풀어 본 화소로
        // 확인합니다 — 줄이는 것 자체는 정상 동작입니다.
        Check(recipe.Items.Count == 1 &&
            DefectMaskCodec.TryDecodeRgba8(
                recipe.Items[0].RegionMask!, width, height, out byte[] stored) &&
            stored.Length == width * height * 4 &&
            stored[0] == 255 && stored[middle] == 128 && stored[4] == 0,
            "grain_mend_region_edit_survives_recipe_validation");
    }

    /// <summary>
    /// 자동/가이드 검출 결과는 저장 전에 성분별로 제외할 수 있어야 합니다. 이 검사는
    /// y-up recipe ROI와 top-first raw 클릭 좌표가 같은 성분을 가리키는지도 함께 고정합니다.
    /// </summary>
    private static void VerifyGrainMendReviewSession()
    {
        const int width = 6;
        const int height = 4;
        byte[] rgba = new byte[width * height * 4];
        int first = ((1 * width) + 1) * 4;
        int second = ((2 * width) + 4) * 4;
        // 네이티브 GrainMend 검출 마스크의 표시값은 1입니다. 255만 표시로 보는 회귀를 막습니다.
        rgba[first] = rgba[first + 1] = rgba[first + 2] = rgba[first + 3] = 1;
        rgba[second] = rgba[second + 1] = rgba[second + 2] = rgba[second + 3] = 192;
        DefectEditItem item = new(
            Guid.Parse("d28b5cbf-4d47-4860-8917-4c6a3e2c46b0"),
            DefectEditKind.Region,
            Enabled: true,
            Strength: 1.0,
            new DefectEditLabel(DefectEditLabelKind.Automatic, 2),
            new DefectEditSummary(
                DefectEditSummaryKind.ClassBreakdown,
                new DefectClassBreakdown(
                    [new DefectClassCount(DefectClassification.Dust, 2)], 1.0)),
            new DefectSize(width, height),
            [])
        {
            RegionMask = new DefectMask(false, rgba),
            RegionRoi = new DefectRect(0.0, 0.0, width, height),
            RegionWidth = width,
            RegionHeight = height,
        };

        GrainMendReviewSession? review = GrainMendReviewSession.TryCreate(item);
        Check(review is not null && review.ComponentCount == 2 && review.IncludedCount == 2,
            "grain_mend_review_discovers_separate_components");
        if (review is null)
        {
            return;
        }

        DefectPoint firstRaw = new(1.0 / (width - 1), 1.0 / (height - 1));
        DefectPoint secondRaw = new(4.0 / (width - 1), 2.0 / (height - 1));
        Check(review.ToggleAtRaw(firstRaw) && review.IsExcludedAtRaw(firstRaw) &&
              review.IncludedCount == 1,
            "grain_mend_review_excludes_clicked_component");
        DefectEditItem? accepted = review.BuildAcceptedEdit();
        Check(accepted is not null && accepted.Label.Value == 1 &&
              DefectMaskCodec.TryDecodeRgba8(accepted.RegionMask!, width, height, out byte[] selected) &&
              selected[first] == 0 && selected[second] == 192,
            "grain_mend_review_persists_only_included_components");
        Check(review.ToggleAtRaw(secondRaw) && review.BuildAcceptedEdit() is null,
            "grain_mend_review_rejects_an_empty_acceptance");
    }

    private static void VerifyGrainMendWorkspaceStateAndOverlay()
    {
        GrainMendWorkspaceState state = new();
        state.BeginDetection();
        Check(state.IsDetecting && !state.IsReviewing,
            "grain_mend_workspace_begins_without_a_persisted_edit");
        state.EndDetection();

        byte[] rgba = new byte[2 * 2 * 4];
        rgba[0] = rgba[1] = rgba[2] = rgba[3] = 1;
        DefectEditItem edit = new(
            Guid.NewGuid(),
            DefectEditKind.Region,
            Enabled: true,
            Strength: 1.0,
            new DefectEditLabel(DefectEditLabelKind.Guided, 1),
            new DefectEditSummary(DefectEditSummaryKind.ClassBreakdown),
            new DefectSize(2, 2),
            [])
        {
            RegionMask = new DefectMask(false, rgba),
            RegionRoi = new DefectRect(0, 0, 2, 2),
            RegionWidth = 2,
            RegionHeight = 2,
        };
        DefectRect roi = new(0.1, 0.2, 0.3, 0.4);
        Check(state.SetDetectedEdit(edit, roi) && state.IsReviewing &&
            state.PendingReview?.IncludedCount == 1,
            "grain_mend_workspace_owns_unaccepted_review_state");

        state.SetSensitivity("frame-a", automatic: false, 99.0);
        Check(state.Sensitivity("frame-a", automatic: false) == GrainMendSensitivity.Maximum &&
            state.Sensitivity("frame-a", automatic: true) == GrainMendSensitivity.Default &&
            state.TakeSensitivityRedetectionRoi() == roi,
            "grain_mend_workspace_keeps_frame_and_mode_specific_sensitivity");
        state.SetMicroSpecks(
            "frame-a",
            automatic: false,
            enabled: false,
            automaticDefault: true,
            guidedDefault: true);
        Check(!state.MicroSpecks("frame-a", false, true, true) &&
            state.MicroSpecks("frame-a", true, true, true),
            "grain_mend_workspace_keeps_auto_and_guided_micro_specks_separate");

        LibraryFrameSnapshot frame = Frame(new ManualBaseRgb(0.2, 0.2, 0.2));
        byte[]? included = GrainMendOverlayRenderer.Render(
            frame, 2, 2, edit, state.PendingReview);
        Check(included is not null && included[3] == 200,
            "grain_mend_overlay_marks_an_included_component");
        Check(state.ToggleReviewAtRaw(new DefectPoint(0, 0)),
            "grain_mend_workspace_toggles_the_review_component");
        byte[]? excluded = GrainMendOverlayRenderer.Render(frame, 2, 2, edit, state.PendingReview);
        Check(excluded is not null && excluded[3] == 100,
            "grain_mend_overlay_marks_an_excluded_component");
        Check(state.BuildAcceptedEdit() is null,
            "grain_mend_workspace_refuses_an_empty_acceptance");
        state.ClearPending();
        Check(!state.IsReviewing && state.PendingRawRoi is null,
            "grain_mend_workspace_clears_unaccepted_state");
    }

    /// <summary>
    /// 자동·가이드 검출 한 번입니다. 요점은 <b>저장하지 않는다</b>는 것입니다 — macOS 는 버튼을
    /// 누르는 것만으로 사진을 바꾸지 않고, 찾은 것을 보여 준 뒤 받아들여야 반영합니다.
    /// </summary>
    private static void VerifyGrainMendDetectCoordinator()
    {
        int callerThreadId = Environment.CurrentManagedThreadId;
        FakeDispatcher dispatcher = new(accepts: true);
        FakeExporter exporter = new(_ => OkResult());
        const uint width = 40U;
        const uint height = 30U;
        exporter.DetectBehaviour = mask =>
        {
            // 몇 화소만 표시해 둡니다. 나머지는 호출부가 넘긴 버퍼 그대로입니다.
            Array.Clear(mask, 0, (int)(width * height));
            mask[0] = 1;
            mask[(int)width + 3] = 90;
            return new GrainMendDetectionResult(
                OkResult(), width, height, 2UL, width * height,
                width, height, 0U, 0U, width, height);
        };

        GrainMendDetectCoordinator coordinator = new(exporter, dispatcher);
        GrainMendDetectOutcome? seen = null;
        Check(
            coordinator.RunAsync(
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2)),
                new DefectRect(0.0, 0.0, 1.0, 1.0),
                outcome => seen = outcome).GetAwaiter().GetResult(),
            "grain_mend_detect_delivers");
        Check(exporter.DetectCallCount == 1 && exporter.DetectThreadId != callerThreadId,
            "grain_mend_detect_runs_off_the_calling_thread");
        Check(seen is { Kind: DevelopExportOutcomeKind.Completed, Edit: not null } &&
            seen.Width == width && seen.Height == height,
            "grain_mend_detect_reports_the_analysis_size");
        Check(seen?.Edit?.Kind == DefectEditKind.Region &&
            seen.Edit.Label.Kind == DefectEditLabelKind.Automatic &&
            seen.Edit.Label.Value == 2,
            "grain_mend_detect_labels_a_whole_frame_run_automatic");
        Check(exporter.LastDetectOptions is
            { DustSensitivity: 1.0, ScratchSensitivity: 1.0, ProtectDetail: 0.6,
                RejectStructureLines: true, DetectMicroSpecks: true },
            "grain_mend_detect_defaults_to_mac_auto_sensitivity_structure_rejection_and_micro_specks");

        // 부분 ROI 는 가이드입니다.
        seen = null;
        Check(
            coordinator.RunAsync(
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2)),
                new DefectRect(0.1, 0.1, 0.5, 0.5),
                outcome => seen = outcome).GetAwaiter().GetResult() &&
            seen?.Edit?.Label.Kind == DefectEditLabelKind.Guided &&
            exporter.LastDetectRoi == new DefectRect(0.1, 0.1, 0.5, 0.5),
            "grain_mend_detect_labels_a_partial_roi_guided");
        GrainMendDetectionOptions minimumGuided = GrainMendSensitivity.ToDetectionOptions(0.7, false);
        Check(
            coordinator.RunAsync(
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2)),
                new DefectRect(0.1, 0.1, 0.5, 0.5),
                minimumGuided,
                outcome => seen = outcome).GetAwaiter().GetResult() &&
            exporter.LastDetectOptions == new GrainMendDetectionOptions(0.0, 0.1, 0.6, false, true),
            "grain_mend_detect_forwards_guided_slider_tuning_without_structure_rejection");

        // 아무것도 못 찾으면 항목이 없고, 그것은 실패가 아닙니다.
        exporter.DetectBehaviour = mask =>
        {
            Array.Clear(mask, 0, (int)(width * height));
            return new GrainMendDetectionResult(
                OkResult(), width, height, 0UL, width * height,
                width, height, 0U, 0U, width, height);
        };
        seen = null;
        Check(
            coordinator.RunAsync(
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2)),
                new DefectRect(0.0, 0.0, 1.0, 1.0),
                outcome => seen = outcome).GetAwaiter().GetResult() &&
            seen is { FoundNothing: true },
            "grain_mend_detect_finding_nothing_is_not_a_failure");

        // 엔진이 실패하면 그대로 전합니다 — 조용히 빈 결과로 만들지 않습니다.
        exporter.DetectBehaviour = null;
        seen = null;
        Check(
            coordinator.RunAsync(
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2)),
                new DefectRect(0.0, 0.0, 1.0, 1.0),
                outcome => seen = outcome).GetAwaiter().GetResult() &&
            seen is { Kind: DevelopExportOutcomeKind.Faulted } &&
            seen.FaultMessage == "detector_unavailable",
            "grain_mend_detect_reports_engine_failure");

        // 현상할 수 없는 frame 은 네이티브까지 가지 않습니다.
        int before = exporter.DetectCallCount;
        seen = null;
        Check(
            coordinator.RunAsync(
                Frame(null, SourceSignalKind.SceneLinearDigital),
                new DefectRect(0.0, 0.0, 1.0, 1.0),
                outcome => seen = outcome).GetAwaiter().GetResult() &&
            seen is { Kind: DevelopExportOutcomeKind.Refused } &&
            exporter.DetectCallCount == before,
            "grain_mend_detect_refuses_before_calling_the_engine");
    }

}
