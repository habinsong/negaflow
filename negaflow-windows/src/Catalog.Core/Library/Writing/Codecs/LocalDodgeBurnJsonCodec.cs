using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

internal static class LocalDodgeBurnJsonCodec
{
    internal static bool IsValid(IReadOnlyList<LocalDodgeBurnAdjustment> adjustments) =>
        LocalDodgeBurnRecipe.IsValid(adjustments);

    internal static JsonArray Write(IReadOnlyList<LocalDodgeBurnAdjustment> adjustments)
    {
        JsonArray result = [];
        foreach (LocalDodgeBurnAdjustment adjustment in adjustments)
        {
            result.Add(new JsonObject
            {
                [LibraryFrameReader.LocalDodgeBurnIdName] = adjustment.Id.ToString(),
                [LibraryFrameReader.LocalDodgeBurnModeName] =
                    adjustment.Mode == LocalDodgeBurnMode.Dodge ? "dodge" : "burn",
                [LibraryFrameReader.LocalDodgeBurnAmountName] = adjustment.Amount,
                [LibraryFrameReader.LocalDodgeBurnEnabledName] = adjustment.IsEnabled,
                [LibraryFrameReader.LocalDodgeBurnMaskName] = WriteMask(adjustment.Mask),
            });
        }
        return result;
    }

    private static JsonObject WriteMask(LocalDodgeBurnMask mask) => new()
    {
        [LibraryFrameReader.LocalDodgeBurnKindName] = mask.Kind switch
        {
            LocalDodgeBurnMaskKind.Brush => "brush",
            LocalDodgeBurnMaskKind.Radial => "radial",
            LocalDodgeBurnMaskKind.Linear => "linear",
            LocalDodgeBurnMaskKind.Polygon => "polygon",
            _ => throw new ArgumentOutOfRangeException(nameof(mask)),
        },
        [LibraryFrameReader.LocalDodgeBurnStrokesName] = WriteStrokes(mask.Strokes),
        [LibraryFrameReader.LocalDodgeBurnCenterName] = WritePoint(mask.Center),
        [LibraryFrameReader.LocalDodgeBurnRadiusName] = mask.Radius,
        [LibraryFrameReader.LocalDodgeBurnFeatherName] = mask.Feather,
        [LibraryFrameReader.LocalDodgeBurnStartName] = WritePoint(mask.Start),
        [LibraryFrameReader.LocalDodgeBurnEndName] = WritePoint(mask.End),
        [LibraryFrameReader.LocalDodgeBurnPointsName] = WritePoints(mask.Points),
    };

    private static JsonArray WriteStrokes(IReadOnlyList<LocalDodgeBurnStroke> strokes)
    {
        JsonArray result = [];
        foreach (LocalDodgeBurnStroke stroke in strokes)
        {
            result.Add(new JsonObject
            {
                [LibraryFrameReader.LocalDodgeBurnPointsName] = WritePoints(stroke.Points),
                [LibraryFrameReader.LocalDodgeBurnThicknessName] = stroke.Thickness,
                [LibraryFrameReader.LocalDodgeBurnFeatherName] = stroke.Feather,
            });
        }
        return result;
    }

    private static JsonArray WritePoints(IReadOnlyList<LocalDodgeBurnPoint> points)
    {
        JsonArray result = [];
        foreach (LocalDodgeBurnPoint point in points)
        {
            result.Add(WritePoint(point));
        }
        return result;
    }

    private static JsonObject WritePoint(LocalDodgeBurnPoint point) => new()
    {
        [LibraryFrameReader.PointCurveXName] = point.X,
        [LibraryFrameReader.PointCurveYName] = point.Y,
    };
}
