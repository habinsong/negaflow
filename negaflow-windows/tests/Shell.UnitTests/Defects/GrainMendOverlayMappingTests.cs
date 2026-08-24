using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class GrainMendOverlayMappingTests
{
    private const int PreviewSize = 512;

    internal static void Run()
    {
        SourcePointBetweenPreviewCellsIsNotDropped();
        PreviewPointUsesDisplayPointScale();
        PreviewComponentsUseClassificationColors();
    }

    private static void SourcePointBetweenPreviewCellsIsNotDropped()
    {
        LibraryFrameSnapshot frame = Frame(new ManualBaseRgb(0.2, 0.2, 0.2)) with
        {
            SourceMetadata = new LibrarySourceMetadata(
                1024UL,
                1024U,
                1024U,
                3,
                16,
                1,
                1),
        };
        DefectPoint sourcePixel = new(2.0 / 1024.0, 2.0 / 1024.0);
        DefectPreviewComponent component = new(
            DefectClassification.Dust,
            1.0,
            [sourcePixel]);

        DefectDisplayLocator? locator = DefectDisplayLocator.Build(
            frame,
            PreviewSize,
            PreviewSize);
        Check(locator is not null && locator.TryLocate(sourcePixel, out int x, out int y) &&
              x == 1 && y == 1,
            "grain_mend_overlay_maps_source_point_without_fixed_grid_gap");

        byte[]? reviewOverlay = DefectMaskOverlayRenderer.RenderPreview(
            frame,
            PreviewSize,
            PreviewSize,
            [component],
            _ => false);
        int alpha = (((1 * PreviewSize) + 1) * 4) + 3;
        Check(reviewOverlay is not null && reviewOverlay[alpha] != 0,
            "grain_mend_review_overlay_keeps_point_between_preview_cells");

        DefectEditItem infrared = new(
            Guid.NewGuid(),
            DefectEditKind.Infrared,
            Enabled: true,
            Strength: 1.0,
            new DefectEditLabel(DefectEditLabelKind.Infrared, 1),
            new DefectEditSummary(
                DefectEditSummaryKind.ClassBreakdown,
                new DefectClassBreakdown(
                    [new DefectClassCount(DefectClassification.Dust, 1)],
                    1.0)),
            new DefectSize(1024.0, 1024.0),
            [component]);
        byte[]? infraredOverlay = DefectMaskOverlayRenderer.Render(
            frame,
            PreviewSize,
            PreviewSize,
            infrared);
        Check(infraredOverlay is not null && infraredOverlay[alpha] != 0,
            "grain_mend_infrared_overlay_keeps_point_between_preview_cells");
    }

    private static void PreviewPointUsesDisplayPointScale()
    {
        LibraryFrameSnapshot frame = Frame(new ManualBaseRgb(0.2, 0.2, 0.2)) with
        {
            SourceMetadata = new LibrarySourceMetadata(1024UL, 100U, 100U, 3, 16, 1, 1),
        };
        DefectPreviewComponent component = new(
            DefectClassification.Dust,
            1.0,
            [new DefectPoint(0.5, 0.5)]);

        byte[]? overlay = DefectMaskOverlayRenderer.RenderPreview(
            frame,
            100,
            100,
            [component],
            _ => false,
            bitmapPixelsPerDisplayPoint: 2.0);
        int painted = overlay is null
            ? 0
            : Enumerable.Range(0, overlay.Length / 4).Count(pixel => overlay[(pixel * 4) + 3] != 0);
        Check(painted == 36,
            "grain_mend_review_overlay_keeps_three_display_point_marker_when_bitmap_is_scaled");
    }

    private static void PreviewComponentsUseClassificationColors()
    {
        LibraryFrameSnapshot frame = Frame(new ManualBaseRgb(0.2, 0.2, 0.2)) with
        {
            SourceMetadata = new LibrarySourceMetadata(1024UL, 100U, 100U, 3, 16, 1, 1),
        };
        DefectPreviewComponent dust = new(
            DefectClassification.Dust,
            1.0,
            [new DefectPoint(0.25, 0.5)]);
        DefectPreviewComponent verticalScratch = new(
            DefectClassification.ScratchVertical,
            1.0,
            [new DefectPoint(0.75, 0.5)]);

        byte[]? overlay = DefectMaskOverlayRenderer.RenderPreview(
            frame,
            100,
            100,
            [dust, verticalScratch],
            _ => false);
        int dustPixel = ((50 * 100) + 25) * 4;
        int scratchPixel = ((50 * 100) + 74) * 4;
        Check(overlay is not null &&
              overlay[dustPixel] != overlay[scratchPixel] &&
              overlay[dustPixel + 1] != overlay[scratchPixel + 1],
            "grain_mend_review_overlay_uses_distinct_component_classification_colors");
    }
}
