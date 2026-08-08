using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

public static class DevelopRouteWriter
{
    public static DevelopRouteWriteResult Apply(
        JsonObject frameRecord,
        DevelopRouteSelection selection)
    {
        ArgumentNullException.ThrowIfNull(frameRecord);
        ArgumentNullException.ThrowIfNull(selection);

        if (!Enum.IsDefined(selection.SourceSignalKind))
        {
            return DevelopRouteWriteResult.Failure(DevelopRouteError.InvalidSourceSignal);
        }
        if (!Enum.IsDefined(selection.FilmType))
        {
            return DevelopRouteWriteResult.Failure(DevelopRouteError.InvalidFilmType);
        }
        if (!Enum.IsDefined(selection.FilmEmulation))
        {
            return DevelopRouteWriteResult.Failure(DevelopRouteError.InvalidFilmEmulation);
        }
        if (!double.IsFinite(selection.FilmEmulationIntensity) ||
            selection.FilmEmulationIntensity is < 0 or > 1)
        {
            return DevelopRouteWriteResult.Failure(
                DevelopRouteError.InvalidFilmEmulationIntensity);
        }

        DevelopRouteError error = DevelopRouteRules.ResolveProcess(
            selection.SourceSignalKind,
            selection.FilmType,
            out _);
        if (error != DevelopRouteError.None)
        {
            return DevelopRouteWriteResult.Failure(error);
        }

        if (!TryReadSourceTransport(frameRecord, out _))
        {
            return DevelopRouteWriteResult.Failure(
                frameRecord.ContainsKey("sourceKind")
                    ? DevelopRouteError.InvalidSourceTransport
                    : DevelopRouteError.MissingSourceTransport);
        }

        JsonObject updated = frameRecord.DeepClone().AsObject();
        JsonObject parameters;
        if (!updated.TryGetPropertyValue("params", out JsonNode? parameterNode) ||
            parameterNode is null)
        {
            parameters = [];
            updated["params"] = parameters;
        }
        else if (parameterNode is JsonObject parameterObject)
        {
            parameters = parameterObject;
        }
        else
        {
            return DevelopRouteWriteResult.Failure(DevelopRouteError.ParametersNotObject);
        }

        string filmType = DevelopRouteJsonNames.FormatFilmType(selection.FilmType);
        updated["sourceSignalKind"] = DevelopRouteJsonNames.FormatSourceSignalKind(
            selection.SourceSignalKind);
        updated["filmType"] = filmType;
        parameters["filmType"] = filmType;
        if (selection.SourceSignalKind == SourceSignalKind.RenderedDigital)
        {
            parameters["isDigitalSource"] = true;
        }
        else
        {
            parameters.Remove("isDigitalSource");
        }
        parameters["filmEmulation"] = DevelopRouteJsonNames.FormatFilmEmulation(
            selection.FilmEmulation);
        parameters["filmEmulationIntensity"] = selection.FilmEmulationIntensity;

        return DevelopRouteWriteResult.Success(updated);
    }

    private static bool TryReadSourceTransport(
        JsonObject frameRecord,
        out FrameSourceTransport sourceTransport)
    {
        sourceTransport = default;
        if (!frameRecord.TryGetPropertyValue("sourceKind", out JsonNode? sourceNode) ||
            sourceNode is not JsonValue sourceValue ||
            !sourceValue.TryGetValue<string>(out string? sourceKind) ||
            sourceKind is null)
        {
            return false;
        }
        return DevelopRouteJsonNames.TryParseSourceTransport(sourceKind, out sourceTransport);
    }
}
