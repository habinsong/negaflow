using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

public enum GrainMendGuidedGestureKind
{
    Ignored,
    Tap,
    Region,
}

public readonly record struct GrainMendGuidedGestureResult(
    GrainMendGuidedGestureKind Kind,
    DefectRect? Region = null);

/// <summary>macOS RegionROIGestureLayer의 release 시 탭·Guided ROI 판정입니다.</summary>
public static class GrainMendGuidedGesture
{
    public const double TapDistance = 6.0;
    public const double MinimumRegionExtent = 0.012;

    public static GrainMendGuidedGestureResult Complete(
        CropDisplayPoint start,
        CropDisplayPoint end,
        double frameWidth,
        double frameHeight)
    {
        if (!Valid(start) || !Valid(end) ||
            !double.IsFinite(frameWidth) || !double.IsFinite(frameHeight) ||
            frameWidth <= 0.0 || frameHeight <= 0.0)
        {
            return default;
        }

        double dx = (end.X - start.X) * frameWidth;
        double dy = (end.Y - start.Y) * frameHeight;
        if (double.Hypot(dx, dy) < TapDistance)
        {
            return new GrainMendGuidedGestureResult(GrainMendGuidedGestureKind.Tap);
        }

        double width = Math.Abs(end.X - start.X);
        double height = Math.Abs(end.Y - start.Y);
        if (width <= MinimumRegionExtent || height <= MinimumRegionExtent)
        {
            return default;
        }
        return new GrainMendGuidedGestureResult(
            GrainMendGuidedGestureKind.Region,
            new DefectRect(
                Math.Min(start.X, end.X),
                Math.Min(start.Y, end.Y),
                width,
                height));
    }

    private static bool Valid(CropDisplayPoint point) =>
        double.IsFinite(point.X) && double.IsFinite(point.Y);
}
