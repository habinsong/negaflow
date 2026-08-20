using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>macOS <c>CanvasCompareToggle</c> · <c>CanvasCompareDivider</c> · clip.</summary>
internal static class CanvasCompareHudTests
{
    public static void Run()
    {
        Check(CanvasCompareHudPolicy.ItemSpacing == 2, "compare_hud_spacing_2");
        Check(CanvasCompareHudPolicy.SurfacePadding == 2, "compare_hud_padding_2");
        Check(CanvasCompareHudPolicy.SurfaceCornerRadius == 10, "compare_hud_corner_10");
        Check(CanvasCompareHudPolicy.ButtonHeight == 24, "compare_hud_height_24");
        Check(CanvasCompareHudPolicy.IconButtonWidth == 26, "compare_hud_icon_width_26");
        Check(CanvasCompareHudPolicy.IconSize == 12, "compare_hud_icon_12");
        Check(CanvasCompareHudPolicy.TextHorizontalPadding == 9, "compare_hud_text_pad_9");
        Check(CanvasCompareHudPolicy.ActiveFillOpacity == 0.16, "compare_hud_active_fill");
        Check(CanvasCompareHudPolicy.InactiveContentOpacity == 0.65, "compare_hud_inactive");
        Check(
            CanvasCompareHudPolicy.SplitOrientation(CanvasCompareMode.SplitVertical) ==
            CanvasCompareOrientation.Vertical,
            "compare_split_v_orientation");
        Check(
            CanvasCompareHudPolicy.SplitOrientation(CanvasCompareMode.Developed) is null,
            "compare_developed_has_no_split");

        CanvasCompareDividerState divider = new();
        Check(divider.VerticalFraction == 0.5 && divider.HorizontalFraction == 0.5, "divider_starts_half");
        divider.SetFraction(CanvasCompareOrientation.Vertical, 0);
        Check(divider.VerticalFraction == 0.02, "divider_clamps_min");
        divider.SetFraction(CanvasCompareOrientation.Vertical, 2);
        Check(divider.VerticalFraction == 0.98, "divider_clamps_max");
        divider.SetFraction(CanvasCompareOrientation.Horizontal, 0.25);
        Check(divider.HorizontalFraction == 0.25, "divider_horizontal_independent");
        Check(divider.LinePosition(100, 200, CanvasCompareOrientation.Vertical) == 100 + (200 * 0.98),
            "divider_line_uses_fraction");

        divider.SetFraction(CanvasCompareOrientation.Vertical, 0.5);
        Check(
            divider.HitTest(200, 150, 100, 50, 200, 200, CanvasCompareOrientation.Vertical),
            "divider_hit_on_line");
        Check(
            !divider.HitTest(100, 150, 100, 50, 200, 200, CanvasCompareOrientation.Vertical),
            "divider_miss_away_from_line");

        divider.BeginOrUpdateDrag(pointer: 180, translation: 0, axisOrigin: 100, axisLength: 200,
            CanvasCompareOrientation.Vertical);
        Check(divider.GrabOffset is not null, "divider_grab_offset_on_press");
        divider.BeginOrUpdateDrag(pointer: 220, translation: 40, axisOrigin: 100, axisLength: 200,
            CanvasCompareOrientation.Vertical);
        Check(divider.VerticalFraction == 0.7, "divider_drag_keeps_grab");
        divider.EndDrag();
        Check(divider.GrabOffset is null, "divider_end_clears_grab");

        (double x, double y, double w, double h) = CanvasCompareDividerState.BeforeClip(
            10, 20, 400, 300, CanvasCompareOrientation.Vertical, 0.25);
        Check(x == 10 && y == 20 && w == 100 && h == 300, "before_clip_vertical_leading");
        (x, y, w, h) = CanvasCompareDividerState.BeforeClip(
            10, 20, 400, 300, CanvasCompareOrientation.Horizontal, 0.5);
        Check(x == 10 && y == 20 && w == 400 && h == 150, "before_clip_horizontal_top");

        LibraryFrameSnapshot frame = TestFrameFactory.Frame(manualBase: null);
        LibraryFrameSnapshot unedited = ExportFlatMaster.Neutralize(frame);
        Check(unedited.Tone.Exposure == 0, "unedited_before_strips_tone");
        Check(unedited.DefectRecipe is null, "unedited_before_strips_defects");
        Check(unedited.DevelopTarget == DevelopTarget.Main, "unedited_before_is_main");

        CanvasCompareState state = new();
        state.CanCompare = true;
        state.Select(CanvasCompareMode.SplitVertical);
        Check(state.Divider.VerticalFraction == 0.5, "select_split_keeps_default_fraction");
        Check(
            CanvasCompareHudPolicy.SplitOrientation(state.ActiveMode) ==
            CanvasCompareOrientation.Vertical,
            "active_split_feeds_clip");
    }
}
