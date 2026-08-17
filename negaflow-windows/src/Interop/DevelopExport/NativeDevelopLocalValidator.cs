namespace Negaflow.Interop;

using static NativeDevelopExportLimits;

/// <summary>로컬 닷지/번 검증입니다. 톤 검증과 다른 이유입니다.</summary>
internal static class NativeDevelopLocalValidator
{
    internal static void ValidateLocalDodgeBurn(
        IReadOnlyList<DevelopLocalDodgeBurnAdjustment> adjustments)
    {
        ArgumentNullException.ThrowIfNull(adjustments);
        if (adjustments.Count > MaximumLocalAdjustments)
        {
            throw new ArgumentException(
                "Local Dodge/Burn has too many adjustments.",
                nameof(adjustments));
        }

        int totalStrokes = 0;
        int totalPoints = 0;
        foreach (DevelopLocalDodgeBurnAdjustment adjustment in adjustments)
        {
            ArgumentNullException.ThrowIfNull(adjustment);
            ArgumentNullException.ThrowIfNull(adjustment.Mask);
            if (!Enum.IsDefined(adjustment.Mode) ||
                !Enum.IsDefined(adjustment.Mask.Kind) ||
                !double.IsFinite(adjustment.Amount) ||
                adjustment.Amount is < 0.0 or > 1.0 ||
                !FinitePoint(adjustment.Mask.Center) ||
                !FinitePoint(adjustment.Mask.Start) ||
                !FinitePoint(adjustment.Mask.End) ||
                !double.IsFinite(adjustment.Mask.Radius) ||
                adjustment.Mask.Radius is < 0.0 or > 2.0 ||
                !double.IsFinite(adjustment.Mask.Feather) ||
                adjustment.Mask.Feather is < 0.0 or > 1.0)
            {
                throw new ArgumentException(
                    "A Local Dodge/Burn adjustment is invalid.",
                    nameof(adjustments));
            }

            ArgumentNullException.ThrowIfNull(adjustment.Mask.Strokes);
            ArgumentNullException.ThrowIfNull(adjustment.Mask.Points);
            switch (adjustment.Mask.Kind)
            {
                case DevelopLocalDodgeBurnMaskKind.Brush:
                    if (adjustment.Mask.Points.Count != 0 ||
                        adjustment.Mask.Strokes.Count > MaximumLocalStrokesPerMask)
                    {
                        throw new ArgumentException(
                            "A Local Dodge/Burn brush payload is invalid.",
                            nameof(adjustments));
                    }
                    totalStrokes = checked(totalStrokes + adjustment.Mask.Strokes.Count);
                    foreach (DevelopLocalDodgeBurnStroke stroke in adjustment.Mask.Strokes)
                    {
                        ArgumentNullException.ThrowIfNull(stroke);
                        ArgumentNullException.ThrowIfNull(stroke.Points);
                        if (!double.IsFinite(stroke.Thickness) ||
                            stroke.Thickness is < 0.001 or > 0.25 ||
                            !double.IsFinite(stroke.Feather) ||
                            stroke.Feather is < 0.0 or > 0.25 ||
                            stroke.Points.Any(point => !FinitePoint(point)))
                        {
                            throw new ArgumentException(
                                "A Local Dodge/Burn brush stroke is invalid.",
                                nameof(adjustments));
                        }
                        totalPoints = checked(totalPoints + stroke.Points.Count);
                    }
                    break;
                case DevelopLocalDodgeBurnMaskKind.Polygon:
                    if (adjustment.Mask.Strokes.Count != 0 ||
                        adjustment.Mask.Points.Any(point => !FinitePoint(point)))
                    {
                        throw new ArgumentException(
                            "A Local Dodge/Burn polygon payload is invalid.",
                            nameof(adjustments));
                    }
                    totalPoints = checked(totalPoints + adjustment.Mask.Points.Count);
                    break;
                case DevelopLocalDodgeBurnMaskKind.Radial:
                case DevelopLocalDodgeBurnMaskKind.Linear:
                    if (adjustment.Mask.Strokes.Count != 0 ||
                        adjustment.Mask.Points.Count != 0)
                    {
                        throw new ArgumentException(
                            "A geometric Local Dodge/Burn mask contains unused arrays.",
                            nameof(adjustments));
                    }
                    break;
                default:
                    throw new ArgumentException(
                        "The Local Dodge/Burn mask kind is unknown.",
                        nameof(adjustments));
            }
            if (totalStrokes > MaximumLocalStrokes || totalPoints > MaximumLocalPoints)
            {
                throw new ArgumentException(
                    "Local Dodge/Burn exceeds the bounded stroke or point capacity.",
                    nameof(adjustments));
            }
        }
    }

    internal static bool FinitePoint(DevelopLocalDodgeBurnPoint point) =>
        double.IsFinite(point.X) && double.IsFinite(point.Y);
}
