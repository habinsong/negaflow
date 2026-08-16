using System.Globalization;
using System.Text.Json;
using static Negaflow.Catalog.LibraryJsonValueReader;
using static Negaflow.Catalog.LibraryFrameReader;

namespace Negaflow.Catalog;

internal static class ToneRecipeJsonReader
{
    internal static bool TryReadTone(JsonElement parameters, out ToneAdjustment tone)
    {
        tone = default;
        if (!TryReadFiniteDouble(parameters, ExposureName, out double exposure) ||
            !TryReadFiniteDouble(parameters, ContrastName, out double contrast) ||
            !TryReadFiniteDouble(parameters, DensityName, out double density) ||
            !TryReadFiniteDouble(parameters, HighlightName, out double highlight) ||
            !TryReadFiniteDouble(parameters, ShadowName, out double shadow) ||
            !TryReadFiniteDouble(parameters, WhitesName, out double whites) ||
            !TryReadFiniteDouble(parameters, BlacksName, out double blacks) ||
            !TryReadFiniteDouble(parameters, CurveHighlightsName, out double highlights) ||
            !TryReadFiniteDouble(parameters, CurveLightsName, out double lights) ||
            !TryReadFiniteDouble(parameters, CurveDarksName, out double darks) ||
            !TryReadFiniteDouble(parameters, CurveShadowsName, out double shadows))
        {
            return false;
        }

        tone = new ToneAdjustment(
            exposure,
            contrast,
            highlights,
            lights,
            darks,
            shadows,
            density,
            highlight,
            shadow,
            whites,
            blacks);
        return true;
    }

}
