using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

/// <summary>버전의 params와 프레임 상위 프로세스 필드를 함께 복원합니다.</summary>
internal static class DevelopVersionRouteCodec
{
    internal static void Capture(JsonObject entry, JsonObject frame)
    {
        foreach (string key in new[] { "filmType", "sourceSignalKind" })
        {
            if (frame[key] is { } value) { entry[key] = value.DeepClone(); }
        }
    }

    internal static bool Restore(JsonObject frame, JsonObject entry, JsonObject parameters)
    {
        JsonNode? filmNode = entry["filmType"] ?? parameters["filmType"];
        // 예전의 최소 recipe에는 프로세스가 없으므로 현재 프로세스를 유지합니다.
        if (filmNode is null) { return true; }
        if (filmNode is not JsonValue filmValue || !filmValue.TryGetValue<string>(out var name) ||
            !DevelopRouteJsonNames.TryParseFilmType(name, out var film)) { return false; }
        if (parameters["filmType"] is JsonNode parameterFilm && !JsonNode.DeepEquals(parameterFilm, filmNode)) { return false; }
        bool digital = false;
        if (parameters["isDigitalSource"] is JsonNode marker &&
            (marker is not JsonValue markerValue || !markerValue.TryGetValue(out digital))) { return false; }
        SourceSignalKind signal = digital ? SourceSignalKind.RenderedDigital
            : film is FilmType.ColorNegative or FilmType.BlackAndWhiteNegative
                ? SourceSignalKind.FilmNegativeScan : SourceSignalKind.FilmPositiveScan;
        if (entry["sourceSignalKind"] is JsonNode storedSignal)
        {
            if (storedSignal is not JsonValue value || !value.TryGetValue<string>(out var stored) ||
                !DevelopRouteJsonNames.TryParseSourceSignalKind(stored, out signal)) { return false; }
        }
        if (DevelopRouteRules.ResolveProcess(signal, film, out _) != DevelopRouteError.None ||
            digital != (signal == SourceSignalKind.RenderedDigital)) { return false; }
        frame["filmType"] = name;
        frame["sourceSignalKind"] = DevelopRouteJsonNames.FormatSourceSignalKind(signal);
        parameters["filmType"] = name;
        return true;
    }
}
