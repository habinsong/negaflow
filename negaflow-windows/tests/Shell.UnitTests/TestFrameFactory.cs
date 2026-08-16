using System.Text.Json.Nodes;
using Negaflow.Catalog;

namespace Negaflow.Shell.UnitTests;

internal static class TestFrameFactory
{
    public static LibraryFrameSnapshot Frame(
        ManualBaseRgb? manualBase,
        SourceSignalKind signal = SourceSignalKind.FilmNegativeScan,
        FilmType filmType = FilmType.ColorNegative,
        FilmEmulation emulation = FilmEmulation.Portra400,
        BaseRecipe? baseRecipe = null,
        PointCurveRecipe? pointCurves = null,
        string? displayName = null,
        string? sourcePath = null) =>
        new(
            "frame-1",
            sourcePath ?? @"C:\scans\IMG_0001.tif",
            displayName ?? "Roll 01 / 1",
            new DevelopRouteSnapshot(
                FrameSourceTransport.Scanner,
                signal,
                signal == SourceSignalKind.RenderedDigital
                    ? DevelopmentProcess.DigitalColor
                    : DevelopmentProcess.C41,
                filmType,
                emulation,
                0.75,
                UsedLegacySourceSignal: false,
                UsedLegacyIntensityDefault: false),
            manualBase,
            new ToneAdjustment(1.5, -0.25, 0.1, 0.2, 0.3, 0.4, 0.5, -0.6, 0.7, -0.8, 0.9))
        {
            Base = baseRecipe ?? (manualBase is null
                ? BaseRecipe.Auto
                : new BaseRecipe(BaseEstimationMode.Manual, null, null, null)),
            PointCurves = pointCurves ?? PointCurveRecipe.Identity,
        };

    public static JsonObject FrameRecord(
        string id,
        string fileName,
        double exposure,
        int scanIndex = 1) =>
        new()
        {
            ["id"] = id,
            ["rawScanPath"] = $@"C:\scans\{fileName}",
            ["scanIndex"] = scanIndex,
            ["sourceKind"] = "scanner",
            ["filmType"] = "colorNegative",
            ["futureFrameValue"] = "preserve-me",
            ["params"] = new JsonObject
            {
                ["filmType"] = "colorNegative",
                ["manualBaseRGB"] = new JsonArray(0.21, 0.22, 0.23),
                ["exposure"] = exposure,
            },
        };

    public static LibrarySourceMetadata? TestSourceMetadata(string path) =>
        File.Exists(path)
            ? path.Contains("incompatible", StringComparison.OrdinalIgnoreCase)
                ? new LibrarySourceMetadata(5, 3, 2, 3, 16, 1, 1)
                : new LibrarySourceMetadata(4, 2, 2, 3, 16, 1, 1)
            : null;
}
