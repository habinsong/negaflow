namespace Negaflow.Shell.Develop;

/// <summary>macOS <c>CanvasCompareDivider</c> 비율·클립.</summary>
public sealed class CanvasCompareDividerState
{
    public const double MinimumFraction = 0.02;
    public const double MaximumFraction = 0.98;
    public const double GrabThickness = 18;
    public const double AdjustmentStep = 0.05;
    public const double HandleShort = 4;
    public const double HandleLong = 34;

    public double VerticalFraction { get; private set; } = 0.5;

    public double HorizontalFraction { get; private set; } = 0.5;

    public double? GrabOffset { get; private set; }

    public double Fraction(CanvasCompareOrientation orientation) =>
        orientation == CanvasCompareOrientation.Vertical ? VerticalFraction : HorizontalFraction;

    public void SetFraction(CanvasCompareOrientation orientation, double value)
    {
        if (!double.IsFinite(value))
        {
            return;
        }

        double clamped = Math.Min(Math.Max(value, MinimumFraction), MaximumFraction);
        if (orientation == CanvasCompareOrientation.Vertical)
        {
            VerticalFraction = clamped;
        }
        else
        {
            HorizontalFraction = clamped;
        }
    }

    public void Nudge(CanvasCompareOrientation orientation, double delta) =>
        SetFraction(orientation, Fraction(orientation) + delta);

    public double LinePosition(double axisOrigin, double axisLength, CanvasCompareOrientation orientation) =>
        axisOrigin + (Math.Max(axisLength, 1) * Fraction(orientation));

    public void BeginOrUpdateDrag(
        double pointer,
        double translation,
        double axisOrigin,
        double axisLength,
        CanvasCompareOrientation orientation)
    {
        double line = LinePosition(axisOrigin, axisLength, orientation);
        double measured = pointer - line;
        double offset = translation == 0 ? measured : (GrabOffset ?? measured);
        GrabOffset = offset;
        SetFraction(orientation, (pointer - offset - axisOrigin) / Math.Max(axisLength, 1));
    }

    public void EndDrag() => GrabOffset = null;

    /// <summary>
    /// macOS <c>splitVerticalImage</c> / <c>splitHorizontalImage</c> — after 는 전체,
    /// before 는 앞쪽 fraction 만 보이게 자른다.
    /// </summary>
    public static (double X, double Y, double Width, double Height) BeforeClip(
        double frameX,
        double frameY,
        double frameWidth,
        double frameHeight,
        CanvasCompareOrientation orientation,
        double fraction)
    {
        double clamped = Math.Min(Math.Max(fraction, MinimumFraction), MaximumFraction);
        return orientation == CanvasCompareOrientation.Vertical
            ? (frameX, frameY, frameWidth * clamped, frameHeight)
            : (frameX, frameY, frameWidth, frameHeight * clamped);
    }

    public bool HitTest(
        double x,
        double y,
        double frameX,
        double frameY,
        double frameWidth,
        double frameHeight,
        CanvasCompareOrientation orientation)
    {
        double half = GrabThickness / 2;
        if (orientation == CanvasCompareOrientation.Vertical)
        {
            double lineX = LinePosition(frameX, frameWidth, orientation);
            return x >= lineX - half && x <= lineX + half &&
                   y >= frameY && y <= frameY + frameHeight;
        }

        double lineY = LinePosition(frameY, frameHeight, orientation);
        return y >= lineY - half && y <= lineY + half &&
               x >= frameX && x <= frameX + frameWidth;
    }
}
