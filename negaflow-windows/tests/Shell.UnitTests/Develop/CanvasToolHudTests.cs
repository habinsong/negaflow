using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>macOS <c>CanvasToolHUD.applyZoomPercent</c> · <c>CanvasHUDPlacement</c>.</summary>
internal static class CanvasToolHudTests
{
    public static void Run()
    {
        Check(CanvasToolHudPolicy.ItemSpacing == 4, "hud_spacing_4");
        Check(CanvasToolHudPolicy.SurfacePadding == 3, "hud_padding_3");
        Check(CanvasToolHudPolicy.SurfaceCornerRadius == 10, "hud_corner_10");
        Check(CanvasToolHudPolicy.ButtonSize == 22, "hud_button_22");
        Check(CanvasToolHudPolicy.IconSize == 13, "hud_icon_13");
        Check(CanvasToolHudPolicy.ButtonCornerRadius == 7, "hud_button_corner_7");
        Check(CanvasToolHudPolicy.PercentWidth == 46, "hud_percent_width_46");
        Check(CanvasToolHudPolicy.EditorWidth == 176, "hud_editor_width_176");
        Check(CanvasToolHudPolicy.EditorFieldWidth == 72, "hud_editor_field_72");
        Check(CanvasToolHudPolicy.ZoomStep == 1.25, "hud_zoom_step_1_25");

        Check(CanvasToolHudPolicy.TryParseZoomPercent(" 80% ", out double eighty) && eighty == 80,
            "hud_parse_strips_percent");
        Check(CanvasToolHudPolicy.TryParseZoomPercent("3", out double floor) && floor == 5,
            "hud_parse_clamps_min_5");
        Check(CanvasToolHudPolicy.TryParseZoomPercent("9999", out double ceil) && ceil == 1600,
            "hud_parse_clamps_max_1600");
        Check(!CanvasToolHudPolicy.TryParseZoomPercent("x", out _), "hud_parse_rejects_text");
        Check(!CanvasToolHudPolicy.TryParseZoomPercent("", out _), "hud_parse_rejects_empty");

        const double imageWidth = 1000;
        const double imageHeight = 800;
        const double canvasWidth = 500;
        const double canvasHeight = 400;
        CanvasViewportState viewport = new();
        Check(
            viewport.TryApplyZoomPercentText("250", imageWidth, imageHeight, canvasWidth, canvasHeight) &&
            viewport.Scale == 2.5 &&
            viewport.ZoomText == "250%",
            "hud_apply_percent_sets_scale");
        Check(
            viewport.TryApplyZoomPercentText("3", imageWidth, imageHeight, canvasWidth, canvasHeight) &&
            viewport.Scale == CanvasViewportState.MinScale &&
            viewport.ZoomText == "20%",
            "hud_apply_percent_then_viewport_min");
        Check(
            viewport.TryApplyZoomPercentText("1600", imageWidth, imageHeight, canvasWidth, canvasHeight) &&
            viewport.Scale == CanvasViewportState.MaxScale &&
            viewport.ZoomText == "1200%",
            "hud_apply_percent_then_viewport_max");
        Check(
            !viewport.TryApplyZoomPercentText("nope", imageWidth, imageHeight, canvasWidth, canvasHeight) &&
            viewport.Scale == CanvasViewportState.MaxScale,
            "hud_apply_percent_keeps_scale_on_reject");

        CanvasHudChrome black = CanvasHudChrome.For(CanvasBackgroundKind.Black);
        Check(black.ContentWhite == 0.97 && black.SurfaceWhite == 0.20, "hud_chrome_black");
        Check(CanvasHudChrome.For(CanvasBackgroundKind.Gray).SurfaceWhite == 0.30, "hud_chrome_gray");
        Check(CanvasHudChrome.For(CanvasBackgroundKind.White) is { ContentWhite: 0.12, SurfaceWhite: 0.86 },
            "hud_chrome_white");
        Check(CanvasHudChrome.StrokeOpacity == 0.22, "hud_chrome_stroke_022");

        CanvasHudOrigins wide = CanvasHudPlacement.DefaultOrigins(
            800,
            500,
            CanvasHudPlacement.DefaultCompareWidth,
            CanvasHudPlacement.DefaultCompareHeight,
            CanvasHudPlacement.DefaultZoomWidth,
            CanvasHudPlacement.DefaultZoomHeight);
        Check(wide.CompareX == 12 && wide.CompareY == 12, "hud_default_compare_top_left");
        Check(wide.ZoomX == 800 - 12 - 136 && wide.ZoomY == 12, "hud_default_zoom_top_right");

        PreviewFrame frame;
        Check(
            PreviewFrame.TryFromViewport(500, 400, 1000, 800, 2, 0, 0, out frame) &&
            frame.Width == 1000 * CanvasViewportGeometry.FitScale(1000, 800, 500, 400) * 2,
            "preview_frame_uses_fitted_scale");

        CanvasHudInteractionState hud = new();
        Check(CanvasHudInteractionState.MinimumDragDistance == 4, "hud_drag_min_distance_4");
        CanvasHudOrigins resolved = hud.Resolve(800, 500);
        Check(resolved.CompareX == 12 && resolved.CompareY == 12, "hud_resolve_default_compare");
        Check(resolved.ZoomX == 800 - 12 - 136 && resolved.ZoomY == 12, "hud_resolve_default_zoom");

        hud.BeginOrUpdateDrag(
            CanvasHudKind.Zoom,
            translationX: -10,
            translationY: 40,
            currentOriginX: resolved.ZoomX,
            currentOriginY: resolved.ZoomY,
            canvasWidth: 800,
            canvasHeight: 500);
        Check(hud.ZoomDragStartX == resolved.ZoomX && hud.ZoomDragStartY == resolved.ZoomY,
            "hud_drag_records_start");
        Check(hud.ZoomOriginX == resolved.ZoomX - 10 && hud.ZoomOriginY == resolved.ZoomY + 40,
            "hud_drag_applies_translation");

        hud.BeginOrUpdateDrag(
            CanvasHudKind.Zoom,
            translationX: -30,
            translationY: 40,
            currentOriginX: resolved.ZoomX,
            currentOriginY: resolved.ZoomY,
            canvasWidth: 800,
            canvasHeight: 500);
        Check(hud.ZoomOriginX == resolved.ZoomX - 30 && hud.ZoomOriginY == resolved.ZoomY + 40,
            "hud_drag_translation_is_from_start");

        hud.EndDrag(CanvasHudKind.Zoom);
        Check(hud.ZoomDragStartX is null && hud.ZoomDragStartY is null, "hud_end_drag_clears_start");
        Check(hud.ZoomOriginX == resolved.ZoomX - 30, "hud_end_drag_keeps_origin");

        hud.BeginOrUpdateDrag(
            CanvasHudKind.Zoom,
            translationX: 0,
            translationY: -400,
            currentOriginX: hud.Resolve(800, 500).ZoomX,
            currentOriginY: hud.Resolve(800, 500).ZoomY,
            canvasWidth: 800,
            canvasHeight: 500);
        Check(hud.ZoomOriginY == 12, "hud_drag_clamps_to_margin");

        CanvasHudInteractionState collide = new();
        CanvasHudOrigins start = collide.Resolve(800, 500);
        collide.BeginOrUpdateDrag(
            CanvasHudKind.Zoom,
            translationX: start.CompareX - start.ZoomX,
            translationY: 0,
            currentOriginX: start.ZoomX,
            currentOriginY: start.ZoomY,
            canvasWidth: 800,
            canvasHeight: 500);
        Check(
            collide.ZoomOriginX is { } movedX &&
            (movedX + collide.ZoomWidth <= start.CompareX - CanvasHudPlacement.CollisionGap ||
             movedX >= start.CompareX + collide.CompareWidth + CanvasHudPlacement.CollisionGap ||
             collide.ZoomOriginY >= start.CompareY + collide.CompareHeight + CanvasHudPlacement.CollisionGap),
            "hud_drag_avoids_other_hud");
    }
}
