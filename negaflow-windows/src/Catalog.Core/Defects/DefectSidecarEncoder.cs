using System.Text.Json;
using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

/// <summary>
/// defect recipe snapshot 을 sidecar JSON 으로 씁니다. 읽기는
/// <see cref="DefectSidecarDecoder"/> 가 소유하며, 둘은 서로를 부르지 않습니다.
/// </summary>
internal static class DefectSidecarEncoder
{
    internal static JsonNode? EncodeSourceIdentity(DefectSourceIdentity? identity) =>
        identity is not { } value
            ? null
            : new JsonObject
            {
                ["byteCount"] = JsonValue.Create(value.ByteCount),
                ["sha256"] = value.Sha256,
            };

    internal static JsonArray EncodeItems(IReadOnlyList<DefectEditItem> items)
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

    internal static JsonObject EncodeLabel(DefectEditLabel label) => new()
    {
        ["kind"] = DefectSidecarNames.LabelKind(label.Kind),
        ["value"] = label.Value,
    };

    internal static JsonObject EncodeSummary(DefectEditSummary summary)
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

    internal static JsonObject EncodeSize(DefectSize size) => new()
    {
        ["width"] = size.Width,
        ["height"] = size.Height,
    };

    internal static JsonArray EncodePreview(
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

    internal static JsonNode? EncodeStrokes(IReadOnlyList<DefectStroke>? strokes)
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

    internal static JsonNode? EncodeCloneStrokes(
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

    internal static JsonObject EncodeMask(DefectMask mask) => new()
    {
        ["zlib"] = mask.IsZlib,
        ["data"] = Convert.ToBase64String(mask.Data),
    };

    internal static JsonNode? EncodeClusters(IReadOnlyList<DefectCluster>? clusters)
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

    internal static JsonArray EncodePoints(IReadOnlyList<DefectPoint> points)
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

    internal static JsonObject EncodeRect(DefectRect rect) => new()
    {
        ["x"] = rect.X,
        ["y"] = rect.Y,
        ["width"] = rect.Width,
        ["height"] = rect.Height,
    };
}
