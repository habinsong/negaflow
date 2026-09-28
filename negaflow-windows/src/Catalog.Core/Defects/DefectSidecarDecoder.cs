using System.Text.Json;

namespace Negaflow.Catalog;

/// <summary>
/// sidecar JSON 을 읽어 defect recipe 항목으로 되돌립니다. 알 수 없는 필드나 범위를
/// 벗어난 값은 실패이며, 반쯤 읽은 결과를 내지 않습니다.
/// </summary>
/// <remarks>
/// <see cref="JsonElement"/> 를 그대로 읽습니다 - 예전 <c>JsonNode</c> 는 미리보기 점마다 노드를 만들어
/// 결함 기록 43장(22.5 MB)에 440 MB 를 할당했습니다. 규칙은 같고 중복 키는 파싱에서 거절합니다.
/// </remarks>
internal static class DefectSidecarDecoder
{
    internal static bool TryReadItems(
        JsonElement nodes,
        out IReadOnlyList<DefectEditItem> items)
    {
        items = [];
        List<DefectEditItem> values = new(nodes.GetArrayLength());
        foreach (JsonElement item in nodes.EnumerateArray())
        {
            if (item.ValueKind != JsonValueKind.Object ||
                !HasExactProperties(
                    item,
                    "id",
                    "kind",
                    "enabled",
                    "strength",
                    "label",
                    "summary",
                    "baseSize",
                    "preview",
                    "strokes",
                    "cloneStrokes",
                    "regionMask",
                    "regionROI",
                    "regionWidth",
                    "regionHeight",
                    "clusters") ||
                !TryString(Property(item, "id"), out string? idText) ||
                !Guid.TryParseExact(idText, "D", out Guid id) ||
                !TryString(Property(item, "kind"), out string? kindText) ||
                !DefectSidecarNames.TryEditKind(kindText, out DefectEditKind kind) ||
                !TryBoolean(Property(item, "enabled"), out bool enabled) ||
                !TryDouble(Property(item, "strength"), out double strength) ||
                !TryReadLabel(Property(item, "label"), out DefectEditLabel label) ||
                !TryReadSummary(Property(item, "summary"), out DefectEditSummary summary) ||
                !TryReadNullableSize(Property(item, "baseSize"), out DefectSize? baseSize) ||
                Property(item, "preview") is not { ValueKind: JsonValueKind.Array } previewNodes ||
                !TryReadPreview(previewNodes, out IReadOnlyList<DefectPreviewComponent> preview) ||
                !TryReadNullableStrokes(
                    Property(item, "strokes"),
                    out IReadOnlyList<DefectStroke>? strokes) ||
                !TryReadNullableCloneStrokes(
                    Property(item, "cloneStrokes"),
                    out IReadOnlyList<DefectCloneStroke>? cloneStrokes) ||
                !TryReadNullableMask(Property(item, "regionMask"), out DefectMask? regionMask) ||
                !TryReadNullableRect(Property(item, "regionROI"), out DefectRect? regionRoi) ||
                !TryNullableInt32(Property(item, "regionWidth"), out int? regionWidth) ||
                !TryNullableInt32(Property(item, "regionHeight"), out int? regionHeight) ||
                !TryReadNullableClusters(
                    Property(item, "clusters"),
                    out IReadOnlyList<DefectCluster>? clusters))
            {
                return false;
            }

            values.Add(new DefectEditItem(
                id,
                kind,
                enabled,
                strength,
                label,
                summary,
                baseSize,
                preview)
            {
                Strokes = strokes,
                CloneStrokes = cloneStrokes,
                RegionMask = regionMask,
                RegionRoi = regionRoi,
                RegionWidth = regionWidth,
                RegionHeight = regionHeight,
                Clusters = clusters,
            });
        }
        items = values.ToArray();
        return true;
    }

    internal static bool TryReadSourceIdentity(
        JsonElement node,
        out DefectSourceIdentity? identity)
    {
        identity = null;
        if (IsAbsent(node))
        {
            return true;
        }
        if (node.ValueKind != JsonValueKind.Object ||
            !HasExactProperties(node, "byteCount", "sha256") ||
            !TryUInt64(Property(node, "byteCount"), out ulong byteCount) ||
            !TryString(Property(node, "sha256"), out string? sha256))
        {
            return false;
        }
        identity = new DefectSourceIdentity(byteCount, sha256);
        return true;
    }

    internal static bool TryReadLabel(JsonElement node, out DefectEditLabel label)
    {
        label = default;
        if (node.ValueKind != JsonValueKind.Object ||
            !HasExactProperties(node, "kind", "value") ||
            !TryString(Property(node, "kind"), out string? kindText) ||
            !DefectSidecarNames.TryLabelKind(kindText, out DefectEditLabelKind kind) ||
            !TryInt32(Property(node, "value"), out int count))
        {
            return false;
        }
        label = new DefectEditLabel(kind, count);
        return true;
    }

    internal static bool TryReadSummary(
        JsonElement node,
        out DefectEditSummary summary)
    {
        summary = null!;
        if (node.ValueKind != JsonValueKind.Object ||
            !HasExactProperties(node, "kind", "classBreakdown") ||
            !TryString(Property(node, "kind"), out string? kindText) ||
            !DefectSidecarNames.TrySummaryKind(
                kindText,
                out DefectEditSummaryKind kind))
        {
            return false;
        }
        JsonElement breakdown = Property(node, "classBreakdown");
        if (IsAbsent(breakdown))
        {
            summary = new DefectEditSummary(kind);
            return true;
        }
        if (breakdown.ValueKind != JsonValueKind.Object ||
            !HasExactProperties(breakdown, "counts", "meanConfidence") ||
            Property(breakdown, "counts") is not { ValueKind: JsonValueKind.Array } countNodes ||
            !TryDouble(Property(breakdown, "meanConfidence"), out double confidence))
        {
            return false;
        }
        List<DefectClassCount> counts = new(countNodes.GetArrayLength());
        foreach (JsonElement count in countNodes.EnumerateArray())
        {
            if (count.ValueKind != JsonValueKind.Object ||
                !HasExactProperties(count, "classification", "count") ||
                !TryString(Property(count, "classification"), out string? classText) ||
                !DefectSidecarNames.TryClassification(
                    classText,
                    out DefectClassification classification) ||
                !TryInt32(Property(count, "count"), out int countValue))
            {
                return false;
            }
            counts.Add(new DefectClassCount(classification, countValue));
        }
        summary = new DefectEditSummary(
            kind,
            new DefectClassBreakdown(counts.ToArray(), confidence));
        return true;
    }

    internal static bool TryReadNullableSize(JsonElement node, out DefectSize? size)
    {
        size = null;
        if (IsAbsent(node))
        {
            return true;
        }
        if (node.ValueKind != JsonValueKind.Object ||
            !HasExactProperties(node, "width", "height") ||
            !TryDouble(Property(node, "width"), out double width) ||
            !TryDouble(Property(node, "height"), out double height))
        {
            return false;
        }
        size = new DefectSize(width, height);
        return true;
    }

    internal static bool TryReadPreview(
        JsonElement nodes,
        out IReadOnlyList<DefectPreviewComponent> preview)
    {
        preview = [];
        if (nodes.GetArrayLength() > DefectRecipeValidator.MaximumPreviewComponentsPerItem)
        {
            return false;
        }
        List<DefectPreviewComponent> values = new(nodes.GetArrayLength());
        foreach (JsonElement component in nodes.EnumerateArray())
        {
            if (component.ValueKind != JsonValueKind.Object ||
                !HasExactProperties(component, "classification", "confidence", "points") ||
                !TryString(Property(component, "classification"), out string? classText) ||
                !DefectSidecarNames.TryClassification(
                    classText,
                    out DefectClassification classification) ||
                !TryDouble(Property(component, "confidence"), out double confidence) ||
                Property(component, "points") is not { ValueKind: JsonValueKind.Array } pointNodes ||
                !TryReadPoints(pointNodes, out IReadOnlyList<DefectPoint> points))
            {
                return false;
            }
            values.Add(new DefectPreviewComponent(classification, confidence, points));
        }
        preview = values.ToArray();
        return true;
    }

    internal static bool TryReadNullableStrokes(
        JsonElement node,
        out IReadOnlyList<DefectStroke>? strokes)
    {
        strokes = null;
        if (IsAbsent(node))
        {
            return true;
        }
        if (node.ValueKind != JsonValueKind.Array ||
            node.GetArrayLength() > DefectRecipeValidator.MaximumStrokesPerItem)
        {
            return false;
        }
        List<DefectStroke> values = new(node.GetArrayLength());
        foreach (JsonElement stroke in node.EnumerateArray())
        {
            if (stroke.ValueKind != JsonValueKind.Object ||
                !HasExactProperties(stroke, "points", "thickness") ||
                Property(stroke, "points") is not { ValueKind: JsonValueKind.Array } pointNodes ||
                !TryReadPoints(pointNodes, out IReadOnlyList<DefectPoint> points) ||
                !TryDouble(Property(stroke, "thickness"), out double thickness))
            {
                return false;
            }
            values.Add(new DefectStroke(points, thickness));
        }
        strokes = values.ToArray();
        return true;
    }

    internal static bool TryReadNullableCloneStrokes(
        JsonElement node,
        out IReadOnlyList<DefectCloneStroke>? strokes)
    {
        strokes = null;
        if (IsAbsent(node))
        {
            return true;
        }
        if (node.ValueKind != JsonValueKind.Array ||
            node.GetArrayLength() > DefectRecipeValidator.MaximumStrokesPerItem)
        {
            return false;
        }
        List<DefectCloneStroke> values = new(node.GetArrayLength());
        foreach (JsonElement stroke in node.EnumerateArray())
        {
            if (stroke.ValueKind != JsonValueKind.Object ||
                !HasExactProperties(
                    stroke,
                    "points",
                    "offsetX",
                    "offsetY",
                    "diameter",
                    "hardness") ||
                Property(stroke, "points") is not { ValueKind: JsonValueKind.Array } pointNodes ||
                !TryReadPoints(pointNodes, out IReadOnlyList<DefectPoint> points) ||
                !TryDouble(Property(stroke, "offsetX"), out double offsetX) ||
                !TryDouble(Property(stroke, "offsetY"), out double offsetY) ||
                !TryDouble(Property(stroke, "diameter"), out double diameter) ||
                !TryDouble(Property(stroke, "hardness"), out double hardness))
            {
                return false;
            }
            values.Add(new DefectCloneStroke(
                points,
                offsetX,
                offsetY,
                diameter,
                hardness));
        }
        strokes = values.ToArray();
        return true;
    }

    internal static bool TryReadNullableMask(JsonElement node, out DefectMask? mask)
    {
        mask = null;
        if (IsAbsent(node))
        {
            return true;
        }
        bool read = TryReadMask(node, out DefectMask value);
        mask = read ? value : null;
        return read;
    }

    internal static bool TryReadMask(JsonElement node, out DefectMask mask)
    {
        mask = null!;
        if (node.ValueKind != JsonValueKind.Object ||
            !HasExactProperties(node, "zlib", "data") ||
            !TryBoolean(Property(node, "zlib"), out bool zlib) ||
            !TryString(Property(node, "data"), out string? dataText))
        {
            return false;
        }
        mask = new DefectMask(zlib, Convert.FromBase64String(dataText));
        return true;
    }

    internal static bool TryReadNullableRect(JsonElement node, out DefectRect? rect)
    {
        rect = null;
        if (IsAbsent(node))
        {
            return true;
        }
        bool read = TryReadRect(node, out DefectRect value);
        rect = read ? value : null;
        return read;
    }

    internal static bool TryReadRect(JsonElement node, out DefectRect rect)
    {
        rect = default;
        if (node.ValueKind != JsonValueKind.Object ||
            !HasExactProperties(node, "x", "y", "width", "height") ||
            !TryDouble(Property(node, "x"), out double x) ||
            !TryDouble(Property(node, "y"), out double y) ||
            !TryDouble(Property(node, "width"), out double width) ||
            !TryDouble(Property(node, "height"), out double height))
        {
            return false;
        }
        rect = new DefectRect(x, y, width, height);
        return true;
    }

    internal static bool TryReadNullableClusters(
        JsonElement node,
        out IReadOnlyList<DefectCluster>? clusters)
    {
        clusters = null;
        if (IsAbsent(node))
        {
            return true;
        }
        if (node.ValueKind != JsonValueKind.Array ||
            node.GetArrayLength() > DefectRecipeValidator.MaximumClustersPerItem)
        {
            return false;
        }
        List<DefectCluster> values = new(node.GetArrayLength());
        foreach (JsonElement cluster in node.EnumerateArray())
        {
            if (cluster.ValueKind != JsonValueKind.Object ||
                !(HasExactProperties(cluster, "roi", "mask", "width", "height") ||
                  HasExactProperties(
                      cluster,
                      "roi",
                      "mask",
                      "attenuationR16",
                      "width",
                      "height")) ||
                !TryReadRect(Property(cluster, "roi"), out DefectRect roi) ||
                !TryReadMask(Property(cluster, "mask"), out DefectMask mask) ||
                !TryReadNullableMask(
                    Property(cluster, "attenuationR16"),
                    out DefectMask? attenuation) ||
                !TryInt32(Property(cluster, "width"), out int width) ||
                !TryInt32(Property(cluster, "height"), out int height))
            {
                return false;
            }
            values.Add(new DefectCluster(roi, mask, width, height, attenuation));
        }
        clusters = values.ToArray();
        return true;
    }

    internal static bool TryReadPoints(
        JsonElement nodes,
        out IReadOnlyList<DefectPoint> points)
    {
        points = [];
        int count = nodes.GetArrayLength();
        if (count > DefectRecipeValidator.MaximumPointsPerStroke)
        {
            return false;
        }
        DefectPoint[] values = new DefectPoint[count];
        int index = 0;
        foreach (JsonElement point in nodes.EnumerateArray())
        {
            if (point.ValueKind != JsonValueKind.Object ||
                !HasExactProperties(point, "x", "y") ||
                !TryDouble(Property(point, "x"), out double x) ||
                !TryDouble(Property(point, "y"), out double y))
            {
                return false;
            }
            values[index++] = new DefectPoint(x, y);
        }
        points = values;
        return true;
    }

    /// <summary>키 집합이 정확히 <paramref name="names"/> 인지 봅니다. 키 이름을 문자열로 만들지 않습니다.</summary>
    internal static bool HasExactProperties(JsonElement value, params string[] names)
    {
        int count = 0;
        foreach (JsonProperty property in value.EnumerateObject())
        {
            if (++count > names.Length || !IsOneOf(property, names))
            {
                return false;
            }
        }
        return count == names.Length;
    }

    private static bool IsOneOf(JsonProperty property, string[] names)
    {
        foreach (string name in names)
        {
            if (property.NameEquals(name))
            {
                return true;
            }
        }
        return false;
    }

    /// <summary>키가 없으면 <see cref="JsonValueKind.Undefined"/> 인 값을 돌려줍니다.</summary>
    internal static JsonElement Property(JsonElement value, string name) =>
        value.TryGetProperty(name, out JsonElement found) ? found : default;

    /// <summary>예전 <c>JsonNode</c> 의 <c>null</c> 자리입니다 - 빠진 키와 JSON null.</summary>
    internal static bool IsAbsent(JsonElement node) =>
        node.ValueKind is JsonValueKind.Undefined or JsonValueKind.Null;

    internal static bool TryString(JsonElement node, out string value)
    {
        value = node.ValueKind == JsonValueKind.String ? node.GetString()! : string.Empty;
        return node.ValueKind == JsonValueKind.String;
    }

    internal static bool TryBoolean(JsonElement node, out bool value)
    {
        value = node.ValueKind == JsonValueKind.True;
        return node.ValueKind is JsonValueKind.True or JsonValueKind.False;
    }

    internal static bool TryDouble(JsonElement node, out double value)
    {
        value = 0;
        return node.ValueKind == JsonValueKind.Number && node.TryGetDouble(out value);
    }

    internal static bool TryInt32(JsonElement node, out int value)
    {
        value = 0;
        return node.ValueKind == JsonValueKind.Number && node.TryGetInt32(out value);
    }

    internal static bool TryUInt64(JsonElement node, out ulong value)
    {
        value = 0;
        return node.ValueKind == JsonValueKind.Number && node.TryGetUInt64(out value);
    }

    internal static bool TryNullableInt32(JsonElement node, out int? value)
    {
        value = null;
        if (IsAbsent(node))
        {
            return true;
        }
        bool read = TryInt32(node, out int decoded);
        value = read ? decoded : null;
        return read;
    }
}
