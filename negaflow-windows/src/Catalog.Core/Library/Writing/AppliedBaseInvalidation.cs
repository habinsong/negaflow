using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

/// <summary>입력·베이스가 바뀌면 이전 렌더의 파생 측정값을 저장하지 않습니다.</summary>
internal static class AppliedBaseInvalidation
{
    private static readonly string[] ParameterKeys =
    [
        "inputGamma", "baseScale", LibraryFrameReader.ManualBaseName,
        LibraryFrameReader.BaseEstimationModeName, LibraryFrameReader.FilmStockDminIdName,
        LibraryFrameReader.LightSourceProfileIdName, LibraryFrameReader.ScannerProfileIdName,
    ];

    internal static void Apply(JsonObject before, JsonObject after)
    {
        if (!after.ContainsKey(LibraryFrameReader.BaseRgbName)) { return; }
        bool changed = !JsonNode.DeepEquals(before["filmType"], after["filmType"]) ||
            !JsonNode.DeepEquals(before["sourceSignalKind"], after["sourceSignalKind"]);
        var previous = before[LibraryFrameReader.ParametersName] as JsonObject;
        var current = after[LibraryFrameReader.ParametersName] as JsonObject;
        foreach (string key in ParameterKeys)
        {
            changed |= !JsonNode.DeepEquals(previous?[key], current?[key]);
        }
        if (changed) { after.Remove(LibraryFrameReader.BaseRgbName); }
    }
}
