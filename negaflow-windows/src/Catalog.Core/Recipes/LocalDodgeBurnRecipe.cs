namespace Negaflow.Catalog;

public enum LocalDodgeBurnMode
{
    Dodge,
    Burn,
}

public enum LocalDodgeBurnMaskKind
{
    Brush,
    Radial,
    Linear,
    Polygon,
}

public readonly record struct LocalDodgeBurnPoint(double X, double Y);

public sealed record LocalDodgeBurnStroke(
    IReadOnlyList<LocalDodgeBurnPoint> Points,
    double Thickness = 0.04,
    double Feather = 0.02);

public sealed record LocalDodgeBurnMask(
    LocalDodgeBurnMaskKind Kind,
    IReadOnlyList<LocalDodgeBurnStroke> Strokes,
    LocalDodgeBurnPoint Center,
    double Radius,
    double Feather,
    LocalDodgeBurnPoint Start,
    LocalDodgeBurnPoint End,
    IReadOnlyList<LocalDodgeBurnPoint> Points)
{
    public static LocalDodgeBurnMask Brush(IReadOnlyList<LocalDodgeBurnStroke> strokes) =>
        new(
            LocalDodgeBurnMaskKind.Brush,
            strokes,
            new(0.5, 0.5),
            0.25,
            0.25,
            new(0.5, 0.0),
            new(0.5, 1.0),
            []);

    public static LocalDodgeBurnMask Radial(
        LocalDodgeBurnPoint center,
        double radius,
        double feather) =>
        new(
            LocalDodgeBurnMaskKind.Radial,
            [],
            center,
            radius,
            feather,
            new(0.5, 0.0),
            new(0.5, 1.0),
            []);

    public static LocalDodgeBurnMask Linear(
        LocalDodgeBurnPoint start,
        LocalDodgeBurnPoint end,
        double feather) =>
        new(
            LocalDodgeBurnMaskKind.Linear,
            [],
            new(0.5, 0.5),
            0.25,
            feather,
            start,
            end,
            []);

    public static LocalDodgeBurnMask Polygon(
        IReadOnlyList<LocalDodgeBurnPoint> points,
        double feather) =>
        new(
            LocalDodgeBurnMaskKind.Polygon,
            [],
            new(0.5, 0.5),
            0.25,
            feather,
            new(0.5, 0.0),
            new(0.5, 1.0),
            points);
}

public sealed record LocalDodgeBurnAdjustment(
    Guid Id,
    LocalDodgeBurnMode Mode,
    double Amount,
    bool IsEnabled,
    LocalDodgeBurnMask Mask);

internal static class LocalDodgeBurnRecipe
{
    internal const int MaximumAdjustments = 64;
    internal const int MaximumStrokesPerMask = 128;
    internal const int MaximumPoints = 4096;

    internal static bool IsValid(IReadOnlyList<LocalDodgeBurnAdjustment>? adjustments)
    {
        if (adjustments is null || adjustments.Count > MaximumAdjustments)
        {
            return false;
        }

        int totalPoints = 0;
        foreach (LocalDodgeBurnAdjustment? adjustment in adjustments)
        {
            if (adjustment is null ||
                !Enum.IsDefined(adjustment.Mode) ||
                !double.IsFinite(adjustment.Amount) || adjustment.Amount is < 0.0 or > 1.0 ||
                !IsValidMask(adjustment.Mask, ref totalPoints))
            {
                return false;
            }
        }
        return true;
    }

    private static bool IsValidMask(LocalDodgeBurnMask? mask, ref int totalPoints)
    {
        if (mask is null || !Enum.IsDefined(mask.Kind) ||
            mask.Strokes is null || mask.Points is null ||
            !IsFinite(mask.Center) || !IsFinite(mask.Start) || !IsFinite(mask.End) ||
            !double.IsFinite(mask.Radius) || mask.Radius is < 0.0 or > 2.0 ||
            !double.IsFinite(mask.Feather) || mask.Feather is < 0.0 or > 1.0)
        {
            return false;
        }

        switch (mask.Kind)
        {
            case LocalDodgeBurnMaskKind.Brush:
                if (mask.Points.Count != 0 || mask.Strokes.Count > MaximumStrokesPerMask)
                {
                    return false;
                }
                foreach (LocalDodgeBurnStroke? stroke in mask.Strokes)
                {
                    if (stroke is null || stroke.Points is null ||
                        !double.IsFinite(stroke.Thickness) || stroke.Thickness is < 0.001 or > 0.25 ||
                        !double.IsFinite(stroke.Feather) || stroke.Feather is < 0.0 or > 0.25 ||
                        !AddPoints(stroke.Points, ref totalPoints))
                    {
                        return false;
                    }
                }
                return true;
            case LocalDodgeBurnMaskKind.Polygon:
                return mask.Strokes.Count == 0 && AddPoints(mask.Points, ref totalPoints);
            case LocalDodgeBurnMaskKind.Radial:
            case LocalDodgeBurnMaskKind.Linear:
                return mask.Strokes.Count == 0 && mask.Points.Count == 0;
            default:
                return false;
        }
    }

    private static bool AddPoints(IReadOnlyList<LocalDodgeBurnPoint> points, ref int totalPoints)
    {
        if (points.Count > MaximumPoints - totalPoints || points.Any(point => !IsFinite(point)))
        {
            return false;
        }
        totalPoints += points.Count;
        return true;
    }

    private static bool IsFinite(LocalDodgeBurnPoint point) =>
        double.IsFinite(point.X) && double.IsFinite(point.Y);
}
