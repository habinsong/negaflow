using System.Text.Json;

namespace Negaflow.Catalog;

public static class DevelopRouteReader
{
    public static DevelopRouteReadResult Read(JsonElement frameRecord)
    {
        if (frameRecord.ValueKind != JsonValueKind.Object)
        {
            return DevelopRouteReadResult.Failure(DevelopRouteError.FrameRecordNotObject);
        }

        DevelopRouteError error = ReadSourceTransport(frameRecord, out FrameSourceTransport transport);
        if (error != DevelopRouteError.None)
        {
            return DevelopRouteReadResult.Failure(error);
        }

        error = ReadRequiredFilmType(frameRecord, out FilmType filmType);
        if (error != DevelopRouteError.None)
        {
            return DevelopRouteReadResult.Failure(error);
        }

        if (!frameRecord.TryGetProperty("params", out JsonElement parameters))
        {
            return DevelopRouteReadResult.Failure(DevelopRouteError.MissingParameters);
        }
        if (parameters.ValueKind != JsonValueKind.Object)
        {
            return DevelopRouteReadResult.Failure(DevelopRouteError.ParametersNotObject);
        }

        error = ValidateParameterFilmType(parameters, filmType);
        if (error != DevelopRouteError.None)
        {
            return DevelopRouteReadResult.Failure(error);
        }

        error = ReadDigitalMarker(parameters, out bool? digitalMarker);
        if (error != DevelopRouteError.None)
        {
            return DevelopRouteReadResult.Failure(error);
        }

        error = ReadSourceSignal(
            frameRecord,
            filmType,
            digitalMarker,
            out SourceSignalKind sourceSignalKind,
            out bool usedLegacySourceSignal);
        if (error != DevelopRouteError.None)
        {
            return DevelopRouteReadResult.Failure(error);
        }

        error = DevelopRouteRules.ResolveProcess(
            sourceSignalKind,
            filmType,
            out DevelopmentProcess process);
        if (error != DevelopRouteError.None)
        {
            return DevelopRouteReadResult.Failure(error);
        }

        error = ReadFilmEmulation(parameters, out FilmEmulation filmEmulation);
        if (error != DevelopRouteError.None)
        {
            return DevelopRouteReadResult.Failure(error);
        }

        error = ReadFilmEmulationIntensity(
            parameters,
            out double filmEmulationIntensity,
            out bool usedLegacyIntensityDefault);
        if (error != DevelopRouteError.None)
        {
            return DevelopRouteReadResult.Failure(error);
        }

        return DevelopRouteReadResult.Success(new DevelopRouteSnapshot(
            transport,
            sourceSignalKind,
            process,
            filmType,
            filmEmulation,
            filmEmulationIntensity,
            usedLegacySourceSignal,
            usedLegacyIntensityDefault));
    }

    private static DevelopRouteError ReadSourceTransport(
        JsonElement frameRecord,
        out FrameSourceTransport transport)
    {
        transport = default;
        if (!frameRecord.TryGetProperty("sourceKind", out JsonElement sourceKind))
        {
            return DevelopRouteError.MissingSourceTransport;
        }
        if (sourceKind.ValueKind != JsonValueKind.String ||
            sourceKind.GetString() is not { } value ||
            !DevelopRouteJsonNames.TryParseSourceTransport(value, out transport))
        {
            return DevelopRouteError.InvalidSourceTransport;
        }
        return DevelopRouteError.None;
    }

    private static DevelopRouteError ReadRequiredFilmType(
        JsonElement frameRecord,
        out FilmType filmType)
    {
        filmType = default;
        if (!frameRecord.TryGetProperty("filmType", out JsonElement property))
        {
            return DevelopRouteError.MissingFilmType;
        }
        if (property.ValueKind != JsonValueKind.String ||
            property.GetString() is not { } value ||
            !DevelopRouteJsonNames.TryParseFilmType(value, out filmType))
        {
            return DevelopRouteError.InvalidFilmType;
        }
        return DevelopRouteError.None;
    }

    private static DevelopRouteError ValidateParameterFilmType(
        JsonElement parameters,
        FilmType frameFilmType)
    {
        FilmType parameterFilmType = FilmType.ColorNegative;
        if (parameters.TryGetProperty("filmType", out JsonElement property))
        {
            if (property.ValueKind != JsonValueKind.String ||
                property.GetString() is not { } value ||
                !DevelopRouteJsonNames.TryParseFilmType(value, out parameterFilmType))
            {
                return DevelopRouteError.InvalidFilmType;
            }
        }

        return parameterFilmType == frameFilmType
            ? DevelopRouteError.None
            : DevelopRouteError.MismatchedFilmType;
    }

    private static DevelopRouteError ReadDigitalMarker(
        JsonElement parameters,
        out bool? digitalMarker)
    {
        digitalMarker = null;
        if (!parameters.TryGetProperty("isDigitalSource", out JsonElement property) ||
            property.ValueKind == JsonValueKind.Null)
        {
            return DevelopRouteError.None;
        }
        if (property.ValueKind == JsonValueKind.True)
        {
            digitalMarker = true;
            return DevelopRouteError.None;
        }
        if (property.ValueKind == JsonValueKind.False)
        {
            digitalMarker = false;
            return DevelopRouteError.None;
        }
        return DevelopRouteError.InvalidDigitalSourceMarker;
    }

    private static DevelopRouteError ReadSourceSignal(
        JsonElement frameRecord,
        FilmType filmType,
        bool? digitalMarker,
        out SourceSignalKind sourceSignalKind,
        out bool usedLegacySourceSignal)
    {
        sourceSignalKind = default;
        usedLegacySourceSignal = true;

        if (!frameRecord.TryGetProperty("sourceSignalKind", out JsonElement property) ||
            property.ValueKind == JsonValueKind.Null)
        {
            sourceSignalKind = digitalMarker == true
                ? SourceSignalKind.RenderedDigital
                : IsNegative(filmType)
                    ? SourceSignalKind.FilmNegativeScan
                    : SourceSignalKind.FilmPositiveScan;
            return DevelopRouteError.None;
        }

        usedLegacySourceSignal = false;
        if (property.ValueKind != JsonValueKind.String ||
            property.GetString() is not { } value ||
            !DevelopRouteJsonNames.TryParseSourceSignalKind(value, out sourceSignalKind))
        {
            return DevelopRouteError.InvalidSourceSignal;
        }

        if (sourceSignalKind == SourceSignalKind.RenderedDigital)
        {
            return digitalMarker == true
                ? DevelopRouteError.None
                : DevelopRouteError.SourceSignalMarkerMismatch;
        }
        return digitalMarker == true
            ? DevelopRouteError.SourceSignalMarkerMismatch
            : DevelopRouteError.None;
    }

    private static DevelopRouteError ReadFilmEmulation(
        JsonElement parameters,
        out FilmEmulation filmEmulation)
    {
        filmEmulation = FilmEmulation.None;
        if (!parameters.TryGetProperty("filmEmulation", out JsonElement property) ||
            property.ValueKind == JsonValueKind.Null)
        {
            return DevelopRouteError.None;
        }
        if (property.ValueKind != JsonValueKind.String ||
            property.GetString() is not { } value ||
            !DevelopRouteJsonNames.TryParseFilmEmulation(value, out filmEmulation))
        {
            return DevelopRouteError.InvalidFilmEmulation;
        }
        return DevelopRouteError.None;
    }

    private static DevelopRouteError ReadFilmEmulationIntensity(
        JsonElement parameters,
        out double intensity,
        out bool usedLegacyDefault)
    {
        intensity = 1.0;
        usedLegacyDefault = true;
        if (!parameters.TryGetProperty("filmEmulationIntensity", out JsonElement property) ||
            property.ValueKind == JsonValueKind.Null)
        {
            return DevelopRouteError.None;
        }
        usedLegacyDefault = false;
        if (property.ValueKind != JsonValueKind.Number ||
            !property.TryGetDouble(out intensity) ||
            !double.IsFinite(intensity) ||
            intensity is < 0 or > 1)
        {
            return DevelopRouteError.InvalidFilmEmulationIntensity;
        }
        return DevelopRouteError.None;
    }

    private static bool IsNegative(FilmType filmType) => filmType is
        FilmType.ColorNegative or FilmType.BlackAndWhiteNegative;
}
