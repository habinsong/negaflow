using System.Globalization;
using System.Text.Json;
using static Negaflow.Catalog.LibraryJsonValueReader;
using static Negaflow.Catalog.LibraryFrameReader;

namespace Negaflow.Catalog;

internal static class LocalDodgeBurnJsonReader
{
    internal static bool TryReadLocalDodgeBurn(
        JsonElement parameters,
        out IReadOnlyList<LocalDodgeBurnAdjustment> adjustments)
    {
        adjustments = [];
        if (!parameters.TryGetProperty(LocalDodgeBurnName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Array ||
            element.GetArrayLength() > LocalDodgeBurnRecipe.MaximumAdjustments)
        {
            return false;
        }

        List<LocalDodgeBurnAdjustment> parsed = new(element.GetArrayLength());
        foreach (JsonElement adjustment in element.EnumerateArray())
        {
            if (!TryReadLocalDodgeBurnAdjustment(adjustment, out LocalDodgeBurnAdjustment? value))
            {
                return false;
            }
            parsed.Add(value!);
        }
        if (!LocalDodgeBurnRecipe.IsValid(parsed))
        {
            return false;
        }
        adjustments = parsed;
        return true;
    }

    internal static bool TryReadLocalDodgeBurnAdjustment(
        JsonElement element,
        out LocalDodgeBurnAdjustment? adjustment)
    {
        adjustment = null;
        if (element.ValueKind != JsonValueKind.Object)
        {
            return false;
        }

        Guid id = Guid.NewGuid();
        if (element.TryGetProperty(LocalDodgeBurnIdName, out JsonElement idElement) &&
            idElement.ValueKind != JsonValueKind.Null &&
            (idElement.ValueKind != JsonValueKind.String ||
             !Guid.TryParse(idElement.GetString(), out id)))
        {
            return false;
        }

        LocalDodgeBurnMode mode = LocalDodgeBurnMode.Dodge;
        if (element.TryGetProperty(LocalDodgeBurnModeName, out JsonElement modeElement) &&
            modeElement.ValueKind != JsonValueKind.Null)
        {
            if (modeElement.ValueKind != JsonValueKind.String)
            {
                return false;
            }
            mode = modeElement.GetString() switch
            {
                "dodge" => LocalDodgeBurnMode.Dodge,
                "burn" => LocalDodgeBurnMode.Burn,
                _ => (LocalDodgeBurnMode)(-1),
            };
        }

        if (!TryReadOptionalFiniteDouble(element, LocalDodgeBurnAmountName, 0.0, out double amount) ||
            !TryReadOptionalBoolean(element, LocalDodgeBurnEnabledName, true, out bool isEnabled) ||
            !element.TryGetProperty(LocalDodgeBurnMaskName, out JsonElement maskElement) ||
            !TryReadLocalDodgeBurnMask(maskElement, out LocalDodgeBurnMask? mask))
        {
            return false;
        }
        adjustment = new LocalDodgeBurnAdjustment(id, mode, amount, isEnabled, mask!);
        return true;
    }

    internal static bool TryReadLocalDodgeBurnMask(
        JsonElement element,
        out LocalDodgeBurnMask? mask)
    {
        mask = null;
        if (element.ValueKind != JsonValueKind.Object ||
            !element.TryGetProperty(LocalDodgeBurnKindName, out JsonElement kindElement) ||
            kindElement.ValueKind != JsonValueKind.String)
        {
            return false;
        }
        LocalDodgeBurnMaskKind kind = kindElement.GetString() switch
        {
            "brush" => LocalDodgeBurnMaskKind.Brush,
            "radial" => LocalDodgeBurnMaskKind.Radial,
            "linear" => LocalDodgeBurnMaskKind.Linear,
            "polygon" => LocalDodgeBurnMaskKind.Polygon,
            _ => (LocalDodgeBurnMaskKind)(-1),
        };
        if (!TryReadLocalDodgeBurnStrokes(element, out IReadOnlyList<LocalDodgeBurnStroke> strokes) ||
            !TryReadOptionalPoint(element, LocalDodgeBurnCenterName, new(0.5, 0.5), out LocalDodgeBurnPoint center) ||
            !TryReadOptionalFiniteDouble(element, LocalDodgeBurnRadiusName, 0.25, out double radius) ||
            !TryReadOptionalFiniteDouble(element, LocalDodgeBurnFeatherName, 0.25, out double feather) ||
            !TryReadOptionalPoint(element, LocalDodgeBurnStartName, new(0.5, 0.0), out LocalDodgeBurnPoint start) ||
            !TryReadOptionalPoint(element, LocalDodgeBurnEndName, new(0.5, 1.0), out LocalDodgeBurnPoint end) ||
            !TryReadLocalDodgeBurnPoints(element, LocalDodgeBurnPointsName, out IReadOnlyList<LocalDodgeBurnPoint> points))
        {
            return false;
        }
        mask = new LocalDodgeBurnMask(kind, strokes, center, radius, feather, start, end, points);
        return true;
    }

    internal static bool TryReadLocalDodgeBurnStrokes(
        JsonElement mask,
        out IReadOnlyList<LocalDodgeBurnStroke> strokes)
    {
        strokes = [];
        if (!mask.TryGetProperty(LocalDodgeBurnStrokesName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Array ||
            element.GetArrayLength() > LocalDodgeBurnRecipe.MaximumStrokesPerMask)
        {
            return false;
        }
        List<LocalDodgeBurnStroke> parsed = new(element.GetArrayLength());
        foreach (JsonElement stroke in element.EnumerateArray())
        {
            if (stroke.ValueKind != JsonValueKind.Object ||
                !TryReadLocalDodgeBurnPoints(stroke, LocalDodgeBurnPointsName, out IReadOnlyList<LocalDodgeBurnPoint> points) ||
                !TryReadOptionalFiniteDouble(stroke, LocalDodgeBurnThicknessName, 0.04, out double thickness) ||
                !TryReadOptionalFiniteDouble(stroke, LocalDodgeBurnFeatherName, 0.02, out double feather))
            {
                return false;
            }
            parsed.Add(new LocalDodgeBurnStroke(points, thickness, feather));
        }
        strokes = parsed;
        return true;
    }

    internal static bool TryReadLocalDodgeBurnPoints(
        JsonElement owner,
        string name,
        out IReadOnlyList<LocalDodgeBurnPoint> points)
    {
        points = [];
        if (!owner.TryGetProperty(name, out JsonElement element) || element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Array ||
            element.GetArrayLength() > LocalDodgeBurnRecipe.MaximumPoints)
        {
            return false;
        }
        List<LocalDodgeBurnPoint> parsed = new(element.GetArrayLength());
        foreach (JsonElement point in element.EnumerateArray())
        {
            if (!TryReadLocalDodgeBurnPoint(point, out LocalDodgeBurnPoint value))
            {
                return false;
            }
            parsed.Add(value);
        }
        points = parsed;
        return true;
    }

    internal static bool TryReadOptionalPoint(
        JsonElement owner,
        string name,
        LocalDodgeBurnPoint defaultValue,
        out LocalDodgeBurnPoint point)
    {
        point = defaultValue;
        return !owner.TryGetProperty(name, out JsonElement element) || element.ValueKind == JsonValueKind.Null
            ? true
            : TryReadLocalDodgeBurnPoint(element, out point);
    }

    internal static bool TryReadLocalDodgeBurnPoint(
        JsonElement element,
        out LocalDodgeBurnPoint point)
    {
        point = default;
        if (element.ValueKind != JsonValueKind.Object ||
            !element.TryGetProperty(PointCurveXName, out JsonElement xElement) ||
            !element.TryGetProperty(PointCurveYName, out JsonElement yElement) ||
            xElement.ValueKind != JsonValueKind.Number || yElement.ValueKind != JsonValueKind.Number ||
            !xElement.TryGetDouble(out double x) || !yElement.TryGetDouble(out double y) ||
            !double.IsFinite(x) || !double.IsFinite(y))
        {
            return false;
        }
        point = new LocalDodgeBurnPoint(x, y);
        return true;
    }

}
