using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

internal static class GrainMendGuidedGestureTests
{
    internal static void Run()
    {
        GrainMendGuidedGestureResult nearTap = GrainMendGuidedGesture.Complete(
            new CropDisplayPoint(0.2, 0.2),
            new CropDisplayPoint(0.2121, 0.2121),
            300.0,
            300.0);
        Check(nearTap.Kind == GrainMendGuidedGestureKind.Tap && nearTap.Region is null,
            "grain_mend_guided_uses_six_point_tap_boundary_before_roi_extent");

        GrainMendGuidedGestureResult exactBoundary = GrainMendGuidedGesture.Complete(
            new CropDisplayPoint(0.25, 0.25),
            new CropDisplayPoint(0.265625, 0.25),
            384.0,
            384.0);
        Check(exactBoundary.Kind == GrainMendGuidedGestureKind.Ignored,
            "grain_mend_guided_six_point_boundary_is_not_a_tap");

        GrainMendGuidedGestureResult region = GrainMendGuidedGesture.Complete(
            new CropDisplayPoint(0.4, 0.5),
            new CropDisplayPoint(0.2, 0.3),
            300.0,
            300.0);
        Check(region is { Kind: GrainMendGuidedGestureKind.Region, Region: { } roi } &&
              Near(roi.X, 0.2) && Near(roi.Y, 0.3) &&
              Near(roi.Width, 0.2) && Near(roi.Height, 0.2),
            "grain_mend_guided_emits_normalized_roi_after_tap_boundary");

        GrainMendGuidedGestureResult tooThin = GrainMendGuidedGesture.Complete(
            new CropDisplayPoint(0.1, 0.1),
            new CropDisplayPoint(0.112, 0.2),
            1000.0,
            1000.0);
        Check(tooThin.Kind == GrainMendGuidedGestureKind.Ignored && tooThin.Region is null,
            "grain_mend_guided_requires_roi_extent_strictly_above_point_zero_one_two");
    }
}
