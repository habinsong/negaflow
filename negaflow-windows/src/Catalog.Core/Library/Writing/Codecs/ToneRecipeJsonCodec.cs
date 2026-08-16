using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

internal static class ToneRecipeJsonCodec
{
    internal static bool IsValid(ToneAdjustment tone) =>
        double.IsFinite(tone.Exposure) && double.IsFinite(tone.Contrast) &&
        double.IsFinite(tone.Density) && double.IsFinite(tone.Highlight) &&
        double.IsFinite(tone.Shadow) && double.IsFinite(tone.Whites) &&
        double.IsFinite(tone.Blacks) && double.IsFinite(tone.CurveHighlights) &&
        double.IsFinite(tone.CurveLights) && double.IsFinite(tone.CurveDarks) &&
        double.IsFinite(tone.CurveShadows);

    internal static void Write(JsonObject parameters, ToneAdjustment tone)
    {
        parameters[LibraryFrameReader.ExposureName] = tone.Exposure;
        parameters[LibraryFrameReader.ContrastName] = tone.Contrast;
        parameters[LibraryFrameReader.DensityName] = tone.Density;
        parameters[LibraryFrameReader.HighlightName] = tone.Highlight;
        parameters[LibraryFrameReader.ShadowName] = tone.Shadow;
        parameters[LibraryFrameReader.WhitesName] = tone.Whites;
        parameters[LibraryFrameReader.BlacksName] = tone.Blacks;
        parameters[LibraryFrameReader.CurveHighlightsName] = tone.CurveHighlights;
        parameters[LibraryFrameReader.CurveLightsName] = tone.CurveLights;
        parameters[LibraryFrameReader.CurveDarksName] = tone.CurveDarks;
        parameters[LibraryFrameReader.CurveShadowsName] = tone.CurveShadows;
    }
}
