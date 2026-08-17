using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// macOS <c>DefectLayerSection</c> 이 무엇을 내는지 고정합니다. 화면 없이 시험할 수 있어야
/// 문구·순서·완료 판정이 조용히 어긋나지 않습니다.
/// </summary>
internal static class DefectLayerSectionTests
{
    public static void Run()
    {
        VerifyEmptyFrameHidesTheSection();
        VerifyRowsFollowTheStoredOrder();
        VerifyScrollingStartsAfterFiveRows();
        VerifyDoneNeedsAMatchingReviewMark();
        VerifyTitlesAndSummariesUseTheMacFormats();
        VerifyMaskPreviewForgetsRemovedLayers();
    }

    private static void VerifyEmptyFrameHidesTheSection()
    {
        DefectLayerSectionState empty = DefectLayerProjection.Create(
            Frame(null),
            Text(),
            maskPreviewId: null,
            reviewed: null,
            isRemovingDefects: false);
        Check(!empty.Visible && empty.Count == 0 && empty.Rows.Count == 0,
            "defect_layer_section_hides_without_edits");
        Check(!DefectLayerProjection.Create(
                null, Text(), null, null, false).Visible,
            "defect_layer_section_hides_without_a_frame");
    }

    private static void VerifyRowsFollowTheStoredOrder()
    {
        LibraryFrameSnapshot frame = WithItems(
            Brush(strokeCount: 2, enabled: true, strength: 1.0),
            Clone(diameter: 48, enabled: false, strength: 0.4),
            Region(DefectEditLabelKind.Automatic, count: 9));
        DefectLayerSectionState state = DefectLayerProjection.Create(
            frame, Text(), null, null, false);
        Check(state.Visible && state.Count == 3, "defect_layer_section_counts_items");
        Check(state.Rows[0].DisplayIndex == 1 && state.Rows[2].DisplayIndex == 3,
            "defect_layer_rows_number_from_one");
        Check(state.Rows[0].Icon == DefectLayerIcon.Brush &&
            state.Rows[1].Icon == DefectLayerIcon.Clone &&
            state.Rows[2].Icon == DefectLayerIcon.Region,
            "defect_layer_rows_pick_the_kind_icon");
        // macOS 는 IR 도 scope 를 씁니다 — 브러시·복제만 따로입니다.
        Check(DefectLayerProjection.Create(
                    WithItems(Infrared(count: 4)), Text(), null, null, false)
                .Rows[0].Icon == DefectLayerIcon.Region,
            "defect_layer_infrared_shares_the_region_icon");
        Check(!state.Rows[1].Enabled && Math.Abs(state.Rows[1].Strength - 0.4) < 1e-9,
            "defect_layer_rows_carry_enabled_and_strength");
    }

    private static void VerifyScrollingStartsAfterFiveRows()
    {
        DefectEditItem[] five =
        [
            .. Enumerable.Range(0, 5).Select(_ => Brush(1, true, 1.0)),
        ];
        Check(!DefectLayerProjection.Create(WithItems(five), Text(), null, null, false).Scrolls,
            "defect_layer_section_does_not_scroll_at_the_limit");
        DefectLayerSectionState six = DefectLayerProjection.Create(
            WithItems([.. five, Brush(1, true, 1.0)]), Text(), null, null, false);
        Check(six.Scrolls &&
            Math.Abs(six.ScrollMaximumHeight -
                (DefectLayerProjection.EstimatedRowHeight * DefectLayerProjection.VisibleLayerLimit))
                < 1e-9,
            "defect_layer_section_scrolls_past_the_limit");
    }

    private static void VerifyDoneNeedsAMatchingReviewMark()
    {
        LibraryFrameSnapshot frame = WithItems(Region(DefectEditLabelKind.Automatic, 3));
        DefectRecipeSnapshot recipe = frame.DefectRecipe!;
        DefectLayerSectionState fresh = DefectLayerProjection.Create(
            frame, Text(), null, null, false);
        Check(fresh.DoneVisible && fresh.DoneEnabled && !fresh.Reviewed,
            "defect_layer_done_offers_itself_on_a_bound_recipe");

        DefectReviewMark exact = new(
            recipe.RecipeRevision,
            recipe.RecipeSha256,
            recipe.SourceIdentity!.Value.Sha256);
        Check(DefectLayerProjection.Create(frame, Text(), null, exact, false) is
            { Reviewed: true, DoneEnabled: false },
            "defect_layer_done_settles_on_an_exact_mark");
        // 원본이 바뀌면 같은 recipe 해시라도 검토 완료를 승계하지 않습니다.
        Check(!DefectLayerProjection.Create(
                frame,
                Text(),
                null,
                exact with { SourceIdentitySha256 = new string('f', 64) },
                false).Reviewed,
            "defect_layer_done_rejects_a_different_source");
        Check(!DefectLayerProjection.Create(
                frame, Text(), null, exact with { RecipeRevision = 99UL }, false).Reviewed,
            "defect_layer_done_rejects_a_different_revision");
        Check(!DefectLayerProjection.Create(frame, Text(), null, null, true).DoneEnabled,
            "defect_layer_done_waits_while_removing");
    }

    private static void VerifyTitlesAndSummariesUseTheMacFormats()
    {
        DefectLayerText text = Text();
        Check(text.Title(new DefectEditLabel(DefectEditLabelKind.Automatic, 9)) ==
            "GrainMend · Auto · 9 defects", "defect_layer_title_fills_the_count");
        Check(text.Title(new DefectEditLabel(DefectEditLabelKind.Clone, 48)) ==
            "Clone stamp 48px", "defect_layer_clone_title_uses_pixels");
        Check(text.Summary(new DefectEditSummary(DefectEditSummaryKind.Brush, null)) ==
            "Custom region precision detect and repair", "defect_layer_brush_summary_is_fixed");
        // "%@ · confidence %.0f%%" — 분류 나열, 반올림한 백분율, 그리고 %% 는 % 하나입니다.
        string summary = text.Summary(new DefectEditSummary(
            DefectEditSummaryKind.ClassBreakdown,
            new DefectClassBreakdown(
                [
                    new DefectClassCount(DefectClassification.Dust, 7),
                    new DefectClassCount(DefectClassification.ScratchHorizontal, 2),
                ],
                0.824)));
        Check(summary == "Dust 7 · Horizontal Scratch 2 · confidence 82%",
            $"defect_layer_summary_matches_the_mac_format ({summary})");
    }

    private static void VerifyMaskPreviewForgetsRemovedLayers()
    {
        LibraryFrameSnapshot frame = WithItems(Brush(1, true, 1.0));
        Guid present = frame.DefectRecipe!.Items[0].Id;
        Check(DefectLayerProjection.SurvivingMaskPreview(frame, present) == present,
            "defect_layer_mask_preview_survives_its_layer");
        Check(DefectLayerProjection.SurvivingMaskPreview(frame, Guid.NewGuid()) is null,
            "defect_layer_mask_preview_drops_a_missing_layer");
        Check(DefectLayerProjection.Create(frame, Text(), present, null, false).Rows[0].MaskShown,
            "defect_layer_row_reports_its_mask_preview");
    }

    private static LibraryFrameSnapshot WithItems(params DefectEditItem[] items) =>
        Frame(null) with
        {
            DefectRecipe = DefectRecipeSnapshot.Create(
                Guid.NewGuid(),
                4UL,
                new DefectSourceIdentity(2048UL, new string('c', 64)),
                items),
        };

    private static DefectEditItem Brush(int strokeCount, bool enabled, double strength) =>
        new(
            Guid.NewGuid(),
            DefectEditKind.Brush,
            enabled,
            strength,
            new DefectEditLabel(DefectEditLabelKind.Brush, strokeCount),
            new DefectEditSummary(DefectEditSummaryKind.Brush, null),
            new DefectSize(100.0, 100.0),
            [])
        {
            Strokes = [new DefectStroke([new DefectPoint(0.4, 0.4), new DefectPoint(0.6, 0.6)], 0.02)],
        };

    private static DefectEditItem Clone(int diameter, bool enabled, double strength) =>
        new(
            Guid.NewGuid(),
            DefectEditKind.Clone,
            enabled,
            strength,
            new DefectEditLabel(DefectEditLabelKind.Clone, diameter),
            new DefectEditSummary(DefectEditSummaryKind.Clone, null),
            new DefectSize(100.0, 100.0),
            [])
        {
            CloneStrokes =
            [
                new DefectCloneStroke([new DefectPoint(0.5, 0.5)], 0.1, 0.1, diameter, 0.5),
            ],
        };

    private static DefectEditItem Region(DefectEditLabelKind label, int count)
    {
        const int width = 6;
        const int height = 5;
        byte[] rgba = new byte[width * height * 4];
        rgba[0] = rgba[1] = rgba[2] = rgba[3] = 255;
        return new DefectEditItem(
            Guid.NewGuid(),
            DefectEditKind.Region,
            Enabled: true,
            Strength: 1.0,
            new DefectEditLabel(label, count),
            new DefectEditSummary(
                DefectEditSummaryKind.ClassBreakdown,
                new DefectClassBreakdown(
                    [new DefectClassCount(DefectClassification.Dust, count)],
                    1.0)),
            new DefectSize(100.0, 100.0),
            [])
        {
            RegionMask = new DefectMask(false, rgba),
            RegionRoi = new DefectRect(0.0, 0.0, width, height),
            RegionWidth = width,
            RegionHeight = height,
        };
    }

    private static DefectEditItem Infrared(int count)
    {
        const int width = 4;
        const int height = 4;
        byte[] rgba = new byte[width * height * 4];
        rgba[0] = rgba[1] = rgba[2] = rgba[3] = 255;
        return new DefectEditItem(
            Guid.NewGuid(),
            DefectEditKind.Infrared,
            Enabled: true,
            Strength: 1.0,
            new DefectEditLabel(DefectEditLabelKind.Infrared, count),
            new DefectEditSummary(
                DefectEditSummaryKind.ClassBreakdown,
                new DefectClassBreakdown(
                    [new DefectClassCount(DefectClassification.Dust, count)],
                    0.9)),
            new DefectSize(100.0, 100.0),
            [])
        {
            Clusters =
            [
                new DefectCluster(
                    new DefectRect(0.0, 0.0, width, height),
                    new DefectMask(false, rgba),
                    width,
                    height),
            ],
        };
    }

    /// <summary>en-US resw 에 실제로 들어 있는 값과 같은 문구입니다.</summary>
    private static DefectLayerText Text() => new(
        "GrainMend Layers",
        "GrainMend · Auto · %d defects",
        "GrainMend · Guided · %d regions",
        "GrainMend · Brush · %d strokes",
        "Clone stamp %dpx",
        "GrainMend · IR · %d defects",
        "Custom region precision detect and repair",
        "Clones pixels from the sampled source",
        "%@ · confidence %.0f%%",
        new Dictionary<DefectClassification, string>
        {
            [DefectClassification.Dust] = "Dust",
            [DefectClassification.ScratchHorizontal] = "Horizontal Scratch",
        },
        "Strength",
        "Enable layer (apply repair)",
        "Disable layer (view before repair)",
        "Show Mask",
        "Hide Mask",
        "Delete Layer",
        "Done");
}
