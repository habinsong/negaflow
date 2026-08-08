namespace Negaflow.Catalog;

public enum DevelopRouteError
{
    None,
    FrameRecordNotObject,
    MissingSourceTransport,
    InvalidSourceTransport,
    MissingFilmType,
    InvalidFilmType,
    MissingParameters,
    ParametersNotObject,
    MismatchedFilmType,
    InvalidDigitalSourceMarker,
    InvalidSourceSignal,
    UnsupportedSourceSignal,
    SourceSignalMarkerMismatch,
    SourceSignalFilmTypeMismatch,
    InvalidFilmEmulation,
    InvalidFilmEmulationIntensity,
}
