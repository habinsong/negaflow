namespace Negaflow.Catalog;

internal static class DevelopRouteRules
{
    public static DevelopRouteError ResolveProcess(
        SourceSignalKind sourceSignalKind,
        FilmType filmType,
        out DevelopmentProcess process)
    {
        process = default;

        switch (sourceSignalKind, filmType)
        {
            case (SourceSignalKind.FilmNegativeScan, FilmType.ColorNegative):
                process = DevelopmentProcess.C41;
                return DevelopRouteError.None;
            case (SourceSignalKind.FilmNegativeScan, FilmType.BlackAndWhiteNegative):
                process = DevelopmentProcess.D76;
                return DevelopRouteError.None;
            case (SourceSignalKind.FilmPositiveScan, FilmType.ColorPositive):
                process = DevelopmentProcess.E6;
                return DevelopRouteError.None;
            case (SourceSignalKind.FilmPositiveScan, FilmType.BlackAndWhitePositive):
                process = DevelopmentProcess.BlackAndWhiteReversal;
                return DevelopRouteError.None;
            case (SourceSignalKind.RenderedDigital, FilmType.ColorPositive):
                process = DevelopmentProcess.DigitalColor;
                return DevelopRouteError.None;
            case (SourceSignalKind.RenderedDigital, FilmType.BlackAndWhitePositive):
                process = DevelopmentProcess.DigitalBlackAndWhite;
                return DevelopRouteError.None;
            case (SourceSignalKind.SceneLinearDigital, _):
            case (SourceSignalKind.Unknown, _):
                return DevelopRouteError.UnsupportedSourceSignal;
            default:
                return DevelopRouteError.SourceSignalFilmTypeMismatch;
        }
    }
}
