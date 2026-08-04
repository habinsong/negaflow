namespace Negaflow.Catalog;

public sealed record DevelopRouteSelection(
    SourceSignalKind SourceSignalKind,
    FilmType FilmType,
    FilmEmulation FilmEmulation,
    double FilmEmulationIntensity)
{
    public const double NewRecipeDefaultFilmEmulationIntensity = 0.5;

    public static DevelopRouteSelection FromProcess(
        DevelopmentProcess process,
        FilmEmulation filmEmulation = FilmEmulation.None,
        double filmEmulationIntensity = NewRecipeDefaultFilmEmulationIntensity)
    {
        return process switch
        {
            DevelopmentProcess.C41 => new(
                SourceSignalKind.FilmNegativeScan,
                FilmType.ColorNegative,
                filmEmulation,
                filmEmulationIntensity),
            DevelopmentProcess.E6 => new(
                SourceSignalKind.FilmPositiveScan,
                FilmType.ColorPositive,
                filmEmulation,
                filmEmulationIntensity),
            DevelopmentProcess.D76 => new(
                SourceSignalKind.FilmNegativeScan,
                FilmType.BlackAndWhiteNegative,
                filmEmulation,
                filmEmulationIntensity),
            DevelopmentProcess.BlackAndWhiteReversal => new(
                SourceSignalKind.FilmPositiveScan,
                FilmType.BlackAndWhitePositive,
                filmEmulation,
                filmEmulationIntensity),
            DevelopmentProcess.DigitalColor => new(
                SourceSignalKind.RenderedDigital,
                FilmType.ColorPositive,
                filmEmulation,
                filmEmulationIntensity),
            DevelopmentProcess.DigitalBlackAndWhite => new(
                SourceSignalKind.RenderedDigital,
                FilmType.BlackAndWhitePositive,
                filmEmulation,
                filmEmulationIntensity),
            _ => throw new ArgumentOutOfRangeException(nameof(process)),
        };
    }
}
