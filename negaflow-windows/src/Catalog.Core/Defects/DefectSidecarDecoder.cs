using System.Text.Json;
using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

/// <summary>
/// sidecar JSON 을 읽어 defect recipe 항목으로 되돌립니다. 알 수 없는 필드나 범위를
/// 벗어난 값은 실패이며, 반쯤 읽은 결과를 내지 않습니다.
/// </summary>
internal static class DefectSidecarDecoder
{
    internal static bool TryReadItems(
        JsonArray nodes,
        out IReadOnlyList<DefectEditItem> items)
    {
        items = [];
        List<DefectEditItem> values = new(nodes.Count);
        foreach (JsonNode? node in nodes)
        {
            if (node is not JsonObject item ||
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
                !TryString(item["id"], out string? idText) ||
                !Guid.TryParseExact(idText, "D", out Guid id) ||
                !TryString(item["kind"], out string? kindText) ||
                !DefectSidecarNames.TryEditKind(kindText, out DefectEditKind kind) ||
                !TryBoolean(item["enabled"], out bool enabled) ||
                !TryDouble(item["strength"], out double strength) ||
                !TryReadLabel(item["label"], out DefectEditLabel label) ||
                !TryReadSummary(item["summary"], out DefectEditSummary summary) ||
                !TryReadNullableSize(item["baseSize"], out DefectSize? baseSize) ||
                item["preview"] is not JsonArray previewNodes ||
                !TryReadPreview(previewNodes, out IReadOnlyList<DefectPreviewComponent> preview) ||
                !TryReadNullableStrokes(
                    item["strokes"],
                    out IReadOnlyList<DefectStroke>? strokes) ||
                !TryReadNullableCloneStrokes(
                    item["cloneStrokes"],
                    out IReadOnlyList<DefectCloneStroke>? cloneStrokes) ||
                !TryReadNullableMask(item["regionMask"], out DefectMask? regionMask) ||
                !TryReadNullableRect(item["regionROI"], out DefectRect? regionRoi) ||
                !TryNullableInt32(item["regionWidth"], out int? regionWidth) ||
                !TryNullableInt32(item["regionHeight"], out int? regionHeight) ||
                !TryReadNullableClusters(
                    item["clusters"],
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
        JsonNode? node,
        out DefectSourceIdentity? identity)
    {
        identity = null;
        if (node is null)
        {
            return true;
        }
        if (node is not JsonObject value ||
            !HasExactProperties(value, "byteCount", "sha256") ||
            !TryUInt64(value["byteCount"], out ulong byteCount) ||
            !TryString(value["sha256"], out string? sha256))
        {
            return false;
        }
        identity = new DefectSourceIdentity(byteCount, sha256);
        return true;
    }

    internal static bool TryReadLabel(JsonNode? node, out DefectEditLabel label)
    {
        label = default;
        if (node is not JsonObject value ||
            !HasExactProperties(value, "kind", "value") ||
            !TryString(value["kind"], out string? kindText) ||
            !DefectSidecarNames.TryLabelKind(kindText, out DefectEditLabelKind kind) ||
            !TryInt32(value["value"], out int count))
        {
            return false;
        }
        label = new DefectEditLabel(kind, count);
        return true;
    }

    internal static bool TryReadSummary(
        JsonNode? node,
        out DefectEditSummary summary)
    {
        summary = null!;
        if (node is not JsonObject value ||
            !HasExactProperties(value, "kind", "classBreakdown") ||
            !TryString(value["kind"], out string? kindText) ||
            !DefectSidecarNames.TrySummaryKind(
                kindText,
                out DefectEditSummaryKind kind))
        {
            return false;
        }
        if (value["classBreakdown"] is null)
        {
            summary = new DefectEditSummary(kind);
            return true;
        }
        if (value["classBreakdown"] is not JsonObject breakdown ||
            !HasExactProperties(breakdown, "counts", "meanConfidence") ||
            breakdown["counts"] is not JsonArray countNodes ||
            !TryDouble(breakdown["meanConfidence"], out double confidence))
        {
            return false;
        }
        List<DefectClassCount> counts = new(countNodes.Count);
        foreach (JsonNode? countNode in countNodes)
        {
            if (countNode is not JsonObject count ||
                !HasExactProperties(count, "classification", "count") ||
                !TryString(count["classification"], out string? classText) ||
                !DefectSidecarNames.TryClassification(
                    classText,
                    out DefectClassification classification) ||
                !TryInt32(count["count"], out int countValue))
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

    internal static bool TryReadNullableSize(JsonNode? node, out DefectSize? size)
    {
        size = null;
        if (node is null)
        {
            return true;
        }
        if (node is not JsonObject value ||
            !HasExactProperties(value, "width", "height") ||
            !TryDouble(value["width"], out double width) ||
            !TryDouble(value["height"], out double height))
        {
            return false;
        }
        size = new DefectSize(width, height);
        return true;
    }

    internal static bool TryReadPreview(
        JsonArray nodes,
        out IReadOnlyList<DefectPreviewComponent> preview)
    {
        preview = [];
        if (nodes.Count > DefectRecipeValidator.MaximumPreviewComponentsPerItem)
        {
            return false;
        }
        List<DefectPreviewComponent> values = new(nodes.Count);
        foreach (JsonNode? node in nodes)
        {
            if (node is not JsonObject component ||
                !HasExactProperties(component, "classification", "confidence", "points") ||
                !TryString(component["classification"], out string? classText) ||
                !DefectSidecarNames.TryClassification(
                    classText,
                    out DefectClassification classification) ||
                !TryDouble(component["confidence"], out double confidence) ||
                component["points"] is not JsonArray pointNodes ||
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
        JsonNode? node,
        out IReadOnlyList<DefectStroke>? strokes)
    {
        strokes = null;
        if (node is null)
        {
            return true;
        }
        if (node is not JsonArray nodes ||
            nodes.Count > DefectRecipeValidator.MaximumStrokesPerItem)
        {
            return false;
        }
        List<DefectStroke> values = new(nodes.Count);
        foreach (JsonNode? strokeNode in nodes)
        {
            if (strokeNode is not JsonObject stroke ||
                !HasExactProperties(stroke, "points", "thickness") ||
                stroke["points"] is not JsonArray pointNodes ||
                !TryReadPoints(pointNodes, out IReadOnlyList<DefectPoint> points) ||
                !TryDouble(stroke["thickness"], out double thickness))
            {
                return false;
            }
            values.Add(new DefectStroke(points, thickness));
        }
        strokes = values.ToArray();
        return true;
    }

    internal static bool TryReadNullableCloneStrokes(
        JsonNode? node,
        out IReadOnlyList<DefectCloneStroke>? strokes)
    {
        strokes = null;
        if (node is null)
        {
            return true;
        }
        if (node is not JsonArray nodes ||
            nodes.Count > DefectRecipeValidator.MaximumStrokesPerItem)
        {
            return false;
        }
        List<DefectCloneStroke> values = new(nodes.Count);
        foreach (JsonNode? strokeNode in nodes)
        {
            if (strokeNode is not JsonObject stroke ||
                !HasExactProperties(
                    stroke,
                    "points",
                    "offsetX",
                    "offsetY",
                    "diameter",
                    "hardness") ||
                stroke["points"] is not JsonArray pointNodes ||
                !TryReadPoints(pointNodes, out IReadOnlyList<DefectPoint> points) ||
                !TryDouble(stroke["offsetX"], out double offsetX) ||
                !TryDouble(stroke["offsetY"], out double offsetY) ||
                !TryDouble(stroke["diameter"], out double diameter) ||
                !TryDouble(stroke["hardness"], out double hardness))
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

    internal static bool TryReadNullableMask(JsonNode? node, out DefectMask? mask)
    {
        mask = null;
        if (node is null)
        {
            return true;
        }
        if (!TryReadMask(node, out DefectMask value))
        {
            return false;
        }
        mask = value;
        return true;
    }

    internal static bool TryReadMask(JsonNode? node, out DefectMask mask)
    {
        mask = null!;
        if (node is not JsonObject value ||
            !HasExactProperties(value, "zlib", "data") ||
            !TryBoolean(value["zlib"], out bool zlib) ||
            !TryString(value["data"], out string? dataText))
        {
            return false;
        }
        mask = new DefectMask(zlib, Convert.FromBase64String(dataText));
        return true;
    }

    internal static bool TryReadNullableRect(JsonNode? node, out DefectRect? rect)
    {
        rect = null;
        if (node is null)
        {
            return true;
        }
        if (!TryReadRect(node, out DefectRect value))
        {
            return false;
        }
        rect = value;
        return true;
    }

    internal static bool TryReadRect(JsonNode? node, out DefectRect rect)
    {
        rect = default;
        if (node is not JsonObject value ||
            !HasExactProperties(value, "x", "y", "width", "height") ||
            !TryDouble(value["x"], out double x) ||
            !TryDouble(value["y"], out double y) ||
            !TryDouble(value["width"], out double width) ||
            !TryDouble(value["height"], out double height))
        {
            return false;
        }
        rect = new DefectRect(x, y, width, height);
        return true;
    }

    internal static bool TryReadNullableClusters(
        JsonNode? node,
        out IReadOnlyList<DefectCluster>? clusters)
    {
        clusters = null;
        if (node is null)
        {
            return true;
        }
        if (node is not JsonArray nodes ||
            nodes.Count > DefectRecipeValidator.MaximumClustersPerItem)
        {
            return false;
        }
        List<DefectCluster> values = new(nodes.Count);
        foreach (JsonNode? clusterNode in nodes)
        {
            if (clusterNode is not JsonObject cluster ||
                !(HasExactProperties(cluster, "roi", "mask", "width", "height") ||
                  HasExactProperties(
                      cluster,
                      "roi",
                      "mask",
                      "attenuationR16",
                      "width",
                      "height")) ||
                !TryReadRect(cluster["roi"], out DefectRect roi) ||
                !TryReadMask(cluster["mask"], out DefectMask mask) ||
                !TryReadNullableMask(
                    cluster["attenuationR16"],
                    out DefectMask? attenuation) ||
                !TryInt32(cluster["width"], out int width) ||
                !TryInt32(cluster["height"], out int height))
            {
                return false;
            }
            values.Add(new DefectCluster(roi, mask, width, height, attenuation));
        }
        clusters = values.ToArray();
        return true;
    }

    internal static bool TryReadPoints(
        JsonArray nodes,
        out IReadOnlyList<DefectPoint> points)
    {
        points = [];
        if (nodes.Count > DefectRecipeValidator.MaximumPointsPerStroke)
        {
            return false;
        }
        DefectPoint[] values = new DefectPoint[nodes.Count];
        for (int index = 0; index < nodes.Count; ++index)
        {
            if (nodes[index] is not JsonObject point ||
                !HasExactProperties(point, "x", "y") ||
                !TryDouble(point["x"], out double x) ||
                !TryDouble(point["y"], out double y))
            {
                return false;
            }
            values[index] = new DefectPoint(x, y);
        }
        points = values;
        return true;
    }

    internal static bool HasExactProperties(JsonObject value, params string[] names)
    {
        if (value.Count != names.Length)
        {
            return false;
        }
        HashSet<string> expected = new(names, StringComparer.Ordinal);
        return value.All(property => expected.Contains(property.Key));
    }

    internal static bool TryString(JsonNode? node, out string value)
    {
        value = string.Empty;
        return node is JsonValue jsonValue && jsonValue.TryGetValue(out value!);
    }

    internal static bool TryBoolean(JsonNode? node, out bool value)
    {
        value = false;
        return node is JsonValue jsonValue && jsonValue.TryGetValue(out value);
    }

    internal static bool TryDouble(JsonNode? node, out double value)
    {
        value = 0;
        return node is JsonValue jsonValue && jsonValue.TryGetValue(out value);
    }

    internal static bool TryInt32(JsonNode? node, out int value)
    {
        value = 0;
        return node is JsonValue jsonValue && jsonValue.TryGetValue(out value);
    }

    internal static bool TryUInt64(JsonNode? node, out ulong value)
    {
        value = 0;
        return node is JsonValue jsonValue && jsonValue.TryGetValue(out value);
    }

    internal static bool TryNullableInt32(JsonNode? node, out int? value)
    {
        value = null;
        if (node is null)
        {
            return true;
        }
        if (!TryInt32(node, out int decoded))
        {
            return false;
        }
        value = decoded;
        return true;
    }
}
