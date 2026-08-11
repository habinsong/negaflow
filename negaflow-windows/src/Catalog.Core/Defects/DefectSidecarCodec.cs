using System.Text.Json;
using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

internal static class DefectSidecarNames
{
    public static string EditKind(DefectEditKind value) => value switch
    {
        DefectEditKind.Brush => "brush",
        DefectEditKind.Region => "region",
        DefectEditKind.Infrared => "infrared",
        DefectEditKind.Clone => "clone",
        _ => throw new ArgumentOutOfRangeException(nameof(value)),
    };

    public static bool TryEditKind(string? value, out DefectEditKind result)
    {
        result = value switch
        {
            "brush" => DefectEditKind.Brush,
            "region" => DefectEditKind.Region,
            "infrared" => DefectEditKind.Infrared,
            "clone" => DefectEditKind.Clone,
            _ => default,
        };
        return value is "brush" or "region" or "infrared" or "clone";
    }

    public static string Classification(DefectClassification value) => value switch
    {
        DefectClassification.Dust => "dust",
        DefectClassification.Pinhole => "pinhole",
        DefectClassification.ScratchHorizontal => "scratchHorizontal",
        DefectClassification.ScratchVertical => "scratchVertical",
        DefectClassification.ScratchDiagonal => "scratchDiagonal",
        DefectClassification.EmulsionDamage => "emulsionDamage",
        DefectClassification.MicroSpeck => "microSpeck",
        _ => throw new ArgumentOutOfRangeException(nameof(value)),
    };

    public static bool TryClassification(
        string? value,
        out DefectClassification result)
    {
        result = value switch
        {
            "dust" => DefectClassification.Dust,
            "pinhole" => DefectClassification.Pinhole,
            "scratchHorizontal" => DefectClassification.ScratchHorizontal,
            "scratchVertical" => DefectClassification.ScratchVertical,
            "scratchDiagonal" => DefectClassification.ScratchDiagonal,
            "emulsionDamage" => DefectClassification.EmulsionDamage,
            "microSpeck" => DefectClassification.MicroSpeck,
            _ => default,
        };
        return value is "dust" or "pinhole" or "scratchHorizontal" or
            "scratchVertical" or "scratchDiagonal" or "emulsionDamage" or
            "microSpeck";
    }

    public static string LabelKind(DefectEditLabelKind value) => value switch
    {
        DefectEditLabelKind.Automatic => "automatic",
        DefectEditLabelKind.Guided => "guided",
        DefectEditLabelKind.Brush => "brush",
        DefectEditLabelKind.Clone => "clone",
        DefectEditLabelKind.Infrared => "infrared",
        _ => throw new ArgumentOutOfRangeException(nameof(value)),
    };

    public static bool TryLabelKind(string? value, out DefectEditLabelKind result)
    {
        result = value switch
        {
            "automatic" => DefectEditLabelKind.Automatic,
            "guided" => DefectEditLabelKind.Guided,
            "brush" => DefectEditLabelKind.Brush,
            "clone" => DefectEditLabelKind.Clone,
            "infrared" => DefectEditLabelKind.Infrared,
            _ => default,
        };
        return value is "automatic" or "guided" or "brush" or "clone" or
            "infrared";
    }

    public static string SummaryKind(DefectEditSummaryKind value) => value switch
    {
        DefectEditSummaryKind.ClassBreakdown => "classBreakdown",
        DefectEditSummaryKind.Brush => "brush",
        DefectEditSummaryKind.Clone => "clone",
        _ => throw new ArgumentOutOfRangeException(nameof(value)),
    };

    public static bool TrySummaryKind(string? value, out DefectEditSummaryKind result)
    {
        result = value switch
        {
            "classBreakdown" => DefectEditSummaryKind.ClassBreakdown,
            "brush" => DefectEditSummaryKind.Brush,
            "clone" => DefectEditSummaryKind.Clone,
            _ => default,
        };
        return value is "classBreakdown" or "brush" or "clone";
    }
}

internal static class DefectSidecarCodec
{
    public const int CurrentVersion = 2;

    public static byte[] Serialize(DefectRecipeSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        return CatalogJson.SerializeCanonical(new JsonObject
        {
            ["version"] = CurrentVersion,
            ["frameID"] = snapshot.FrameId.ToString("D"),
            ["fingerprintVersion"] = snapshot.FingerprintVersion,
            ["recipeRevision"] = JsonValue.Create(snapshot.RecipeRevision),
            ["recipeSHA256"] = snapshot.RecipeSha256,
            ["sourceIdentity"] = EncodeSourceIdentity(snapshot.SourceIdentity),
            ["items"] = EncodeItems(snapshot.Items),
        });
    }

    public static DefectSidecarReadResult Decode(
        ReadOnlySpan<byte> data,
        Guid expectedFrameId,
        bool validateCompressedMasks = false)
    {
        try
        {
            if (JsonNode.Parse(data) is not JsonObject root ||
                !TryInt32(root["version"], out int version))
            {
                return DefectSidecarReadResult.Failure(
                    DefectSidecarError.InvalidContent);
            }
            if (version != CurrentVersion)
            {
                return DefectSidecarReadResult.Failure(
                    DefectSidecarError.UnsupportedVersion,
                    version);
            }
            if (!HasExactProperties(
                    root,
                    "version",
                    "frameID",
                    "fingerprintVersion",
                    "recipeRevision",
                    "recipeSHA256",
                    "sourceIdentity",
                    "items") ||
                !TryString(root["frameID"], out string? frameText) ||
                !Guid.TryParseExact(frameText, "D", out Guid frameId) ||
                !TryInt32(root["fingerprintVersion"], out int fingerprintVersion) ||
                !TryUInt64(root["recipeRevision"], out ulong recipeRevision) ||
                !TryString(root["recipeSHA256"], out string? recipeSha256) ||
                !TryReadSourceIdentity(
                    root["sourceIdentity"],
                    out DefectSourceIdentity? sourceIdentity) ||
                root["items"] is not JsonArray itemNodes ||
                itemNodes.Count > DefectRecipeValidator.MaximumItems ||
                !TryReadItems(itemNodes, out IReadOnlyList<DefectEditItem> items) ||
                !DefectRecipeValidator.TryCreateDecodedSnapshot(
                    expectedFrameId,
                    frameId,
                    fingerprintVersion,
                    recipeRevision,
                    recipeSha256,
                    sourceIdentity,
                    items,
                    validateCompressedMasks,
                    out DefectRecipeSnapshot snapshot))
            {
                return DefectSidecarReadResult.Failure(
                    DefectSidecarError.InvalidContent,
                    version);
            }
            return DefectSidecarReadResult.Success(snapshot);
        }
        catch (Exception error) when (error is
            JsonException or FormatException or OverflowException or ArgumentException)
        {
            return DefectSidecarReadResult.Failure(
                DefectSidecarError.InvalidContent);
        }
    }

    public static bool AreSameSnapshot(
        DefectRecipeSnapshot left,
        DefectRecipeSnapshot right) =>
        Serialize(left).AsSpan().SequenceEqual(Serialize(right));

    public static bool HaveSameItems(
        DefectRecipeSnapshot left,
        DefectRecipeSnapshot right) =>
        CatalogJson.SerializeCanonical(EncodeItems(left.Items)).AsSpan()
            .SequenceEqual(CatalogJson.SerializeCanonical(EncodeItems(right.Items)));

    private static JsonNode? EncodeSourceIdentity(DefectSourceIdentity? identity) =>
        identity is not { } value
            ? null
            : new JsonObject
            {
                ["byteCount"] = JsonValue.Create(value.ByteCount),
                ["sha256"] = value.Sha256,
            };

    private static JsonArray EncodeItems(IReadOnlyList<DefectEditItem> items)
    {
        JsonArray values = [];
        foreach (DefectEditItem item in items)
        {
            values.Add(new JsonObject
            {
                ["id"] = item.Id.ToString("D"),
                ["kind"] = DefectSidecarNames.EditKind(item.Kind),
                ["enabled"] = item.Enabled,
                ["strength"] = item.Strength,
                ["label"] = EncodeLabel(item.Label),
                ["summary"] = EncodeSummary(item.Summary),
                ["baseSize"] = item.BaseSize is { } baseSize
                    ? EncodeSize(baseSize)
                    : null,
                ["preview"] = EncodePreview(item.Preview),
                ["strokes"] = EncodeStrokes(item.Strokes),
                ["cloneStrokes"] = EncodeCloneStrokes(item.CloneStrokes),
                ["regionMask"] = item.RegionMask is { } regionMask
                    ? EncodeMask(regionMask)
                    : null,
                ["regionROI"] = item.RegionRoi is { } regionRoi
                    ? EncodeRect(regionRoi)
                    : null,
                ["regionWidth"] = item.RegionWidth,
                ["regionHeight"] = item.RegionHeight,
                ["clusters"] = EncodeClusters(item.Clusters),
            });
        }
        return values;
    }

    private static JsonObject EncodeLabel(DefectEditLabel label) => new()
    {
        ["kind"] = DefectSidecarNames.LabelKind(label.Kind),
        ["value"] = label.Value,
    };

    private static JsonObject EncodeSummary(DefectEditSummary summary)
    {
        JsonNode? breakdown = null;
        if (summary.ClassBreakdown is { } value)
        {
            JsonArray counts = [];
            foreach (DefectClassCount count in value.Counts)
            {
                counts.Add(new JsonObject
                {
                    ["classification"] =
                        DefectSidecarNames.Classification(count.Classification),
                    ["count"] = count.Count,
                });
            }
            breakdown = new JsonObject
            {
                ["counts"] = counts,
                ["meanConfidence"] = value.MeanConfidence,
            };
        }
        return new JsonObject
        {
            ["kind"] = DefectSidecarNames.SummaryKind(summary.Kind),
            ["classBreakdown"] = breakdown,
        };
    }

    private static JsonObject EncodeSize(DefectSize size) => new()
    {
        ["width"] = size.Width,
        ["height"] = size.Height,
    };

    private static JsonArray EncodePreview(
        IReadOnlyList<DefectPreviewComponent> preview)
    {
        JsonArray values = [];
        foreach (DefectPreviewComponent component in preview)
        {
            values.Add(new JsonObject
            {
                ["classification"] =
                    DefectSidecarNames.Classification(component.Classification),
                ["confidence"] = component.Confidence,
                ["points"] = EncodePoints(component.Points),
            });
        }
        return values;
    }

    private static JsonNode? EncodeStrokes(IReadOnlyList<DefectStroke>? strokes)
    {
        if (strokes is null)
        {
            return null;
        }
        JsonArray values = [];
        foreach (DefectStroke stroke in strokes)
        {
            values.Add(new JsonObject
            {
                ["points"] = EncodePoints(stroke.Points),
                ["thickness"] = stroke.Thickness,
            });
        }
        return values;
    }

    private static JsonNode? EncodeCloneStrokes(
        IReadOnlyList<DefectCloneStroke>? strokes)
    {
        if (strokes is null)
        {
            return null;
        }
        JsonArray values = [];
        foreach (DefectCloneStroke stroke in strokes)
        {
            values.Add(new JsonObject
            {
                ["points"] = EncodePoints(stroke.Points),
                ["offsetX"] = stroke.OffsetX,
                ["offsetY"] = stroke.OffsetY,
                ["diameter"] = stroke.Diameter,
                ["hardness"] = stroke.Hardness,
            });
        }
        return values;
    }

    private static JsonObject EncodeMask(DefectMask mask) => new()
    {
        ["zlib"] = mask.IsZlib,
        ["data"] = Convert.ToBase64String(mask.Data),
    };

    private static JsonNode? EncodeClusters(IReadOnlyList<DefectCluster>? clusters)
    {
        if (clusters is null)
        {
            return null;
        }
        JsonArray values = [];
        foreach (DefectCluster cluster in clusters)
        {
            values.Add(new JsonObject
            {
                ["roi"] = EncodeRect(cluster.Roi),
                ["mask"] = EncodeMask(cluster.Mask),
                ["attenuationR16"] = cluster.AttenuationR16 is { } attenuation
                    ? EncodeMask(attenuation)
                    : null,
                ["width"] = cluster.Width,
                ["height"] = cluster.Height,
            });
        }
        return values;
    }

    private static JsonArray EncodePoints(IReadOnlyList<DefectPoint> points)
    {
        JsonArray values = [];
        foreach (DefectPoint point in points)
        {
            values.Add(new JsonObject
            {
                ["x"] = point.X,
                ["y"] = point.Y,
            });
        }
        return values;
    }

    private static JsonObject EncodeRect(DefectRect rect) => new()
    {
        ["x"] = rect.X,
        ["y"] = rect.Y,
        ["width"] = rect.Width,
        ["height"] = rect.Height,
    };

    private static bool TryReadItems(
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

    private static bool TryReadSourceIdentity(
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

    private static bool TryReadLabel(JsonNode? node, out DefectEditLabel label)
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

    private static bool TryReadSummary(
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

    private static bool TryReadNullableSize(JsonNode? node, out DefectSize? size)
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

    private static bool TryReadPreview(
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

    private static bool TryReadNullableStrokes(
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

    private static bool TryReadNullableCloneStrokes(
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

    private static bool TryReadNullableMask(JsonNode? node, out DefectMask? mask)
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

    private static bool TryReadMask(JsonNode? node, out DefectMask mask)
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

    private static bool TryReadNullableRect(JsonNode? node, out DefectRect? rect)
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

    private static bool TryReadRect(JsonNode? node, out DefectRect rect)
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

    private static bool TryReadNullableClusters(
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

    private static bool TryReadPoints(
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

    private static bool HasExactProperties(JsonObject value, params string[] names)
    {
        if (value.Count != names.Length)
        {
            return false;
        }
        HashSet<string> expected = new(names, StringComparer.Ordinal);
        return value.All(property => expected.Contains(property.Key));
    }

    private static bool TryString(JsonNode? node, out string value)
    {
        value = string.Empty;
        return node is JsonValue jsonValue && jsonValue.TryGetValue(out value!);
    }

    private static bool TryBoolean(JsonNode? node, out bool value)
    {
        value = false;
        return node is JsonValue jsonValue && jsonValue.TryGetValue(out value);
    }

    private static bool TryDouble(JsonNode? node, out double value)
    {
        value = 0;
        return node is JsonValue jsonValue && jsonValue.TryGetValue(out value);
    }

    private static bool TryInt32(JsonNode? node, out int value)
    {
        value = 0;
        return node is JsonValue jsonValue && jsonValue.TryGetValue(out value);
    }

    private static bool TryUInt64(JsonNode? node, out ulong value)
    {
        value = 0;
        return node is JsonValue jsonValue && jsonValue.TryGetValue(out value);
    }

    private static bool TryNullableInt32(JsonNode? node, out int? value)
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
