namespace Negaflow.Catalog;

public sealed record DevelopRouteSnapshot(
    FrameSourceTransport SourceTransport,
    SourceSignalKind SourceSignalKind,
    DevelopmentProcess DevelopmentProcess,
    FilmType FilmType,
    FilmEmulation FilmEmulation,
    double FilmEmulationIntensity,
    bool UsedLegacySourceSignal,
    bool UsedLegacyIntensityDefault)
{
    public bool IsDigitalSource => SourceSignalKind == SourceSignalKind.RenderedDigital;

    public FilmLookSource FilmLookSource => IsDigitalSource
        ? FilmLookSource.RenderedDigital
        : FilmLookSource.FilmScan;
}
