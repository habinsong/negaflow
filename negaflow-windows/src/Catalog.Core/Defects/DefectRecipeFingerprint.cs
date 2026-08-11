using System.Security.Cryptography;
using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

internal static class DefectRecipeFingerprint
{
    public const int LegacyVersion = 2;
    public const int CurrentVersion = 3;

    public static string Compute(IReadOnlyList<DefectEditItem> items) =>
        Compute(items, CurrentVersion);

    public static string Compute(
        IReadOnlyList<DefectEditItem> items,
        int version)
    {
        if (version is not LegacyVersion and not CurrentVersion)
        {
            throw new ArgumentOutOfRangeException(nameof(version));
        }
        JsonArray encodedItems = [];
        foreach (DefectEditItem item in items)
        {
            encodedItems.Add(EncodeItem(
                item,
                includeAttenuation: version >= CurrentVersion));
        }
        byte[] canonical = CatalogJson.SerializeCanonical(new JsonObject
        {
            ["version"] = version,
            ["items"] = encodedItems,
        });
        return Convert.ToHexStringLower(SHA256.HashData(canonical));
    }

    private static JsonObject EncodeItem(
        DefectEditItem item,
        bool includeAttenuation)
    {
        JsonArray? strokes = null;
        JsonObject? region = null;
        JsonArray? clusters = null;
        JsonArray? clones = null;

        switch (item.Kind)
        {
            case DefectEditKind.Brush:
                strokes = [];
                foreach (DefectStroke stroke in item.Strokes ?? [])
                {
                    strokes.Add(new JsonObject
                    {
                        ["points"] = EncodePoints(stroke.Points),
                        ["thickness"] = Bits(stroke.Thickness),
                    });
                }
                break;
            case DefectEditKind.Region:
                DefectRect roi = item.RegionRoi!.Value;
                DefectMask mask = item.RegionMask!;
                region = new JsonObject
                {
                    ["maskByteCount"] = mask.Data.LongLength,
                    ["maskZlib"] = mask.IsZlib,
                    ["roi"] = EncodeRect(roi),
                    ["width"] = item.RegionWidth!.Value,
                    ["height"] = item.RegionHeight!.Value,
                };
                break;
            case DefectEditKind.Infrared:
                clusters = [];
                foreach (DefectCluster cluster in item.Clusters ?? [])
                {
                    JsonObject encoded = new()
                    {
                        ["roi"] = EncodeRect(cluster.Roi),
                        ["maskByteCount"] = cluster.Mask.Data.LongLength,
                        ["maskZlib"] = cluster.Mask.IsZlib,
                        ["width"] = cluster.Width,
                        ["height"] = cluster.Height,
                    };
                    if (includeAttenuation &&
                        cluster.AttenuationR16 is { } attenuation)
                    {
                        encoded["attenuationByteCount"] = attenuation.Data.LongLength;
                        encoded["attenuationZlib"] = attenuation.IsZlib;
                        encoded["attenuationSHA256"] = Convert.ToHexStringLower(
                            SHA256.HashData(attenuation.Data));
                    }
                    clusters.Add(encoded);
                }
                break;
            case DefectEditKind.Clone:
                clones = [];
                foreach (DefectCloneStroke stroke in item.CloneStrokes ?? [])
                {
                    clones.Add(new JsonObject
                    {
                        ["points"] = EncodePoints(stroke.Points),
                        ["offsetX"] = Bits(stroke.OffsetX),
                        ["offsetY"] = Bits(stroke.OffsetY),
                        ["diameter"] = Bits(stroke.Diameter),
                        ["hardness"] = Bits(stroke.Hardness),
                    });
                }
                break;
            default:
                throw new ArgumentException("Unsupported defect edit kind.", nameof(item));
        }

        return new JsonObject
        {
            ["id"] = item.Id.ToString("D"),
            ["kind"] = DefectSidecarNames.EditKind(item.Kind),
            ["enabled"] = item.Enabled,
            ["strength"] = Bits(item.Strength),
            ["strokes"] = strokes,
            ["region"] = region,
            ["clusters"] = clusters,
            ["clones"] = clones,
        };
    }

    private static JsonArray EncodePoints(IReadOnlyList<DefectPoint> points)
    {
        JsonArray result = [];
        foreach (DefectPoint point in points)
        {
            result.Add(new JsonObject
            {
                ["x"] = Bits(point.X),
                ["y"] = Bits(point.Y),
            });
        }
        return result;
    }

    private static JsonObject EncodeRect(DefectRect rect) => new()
    {
        ["x"] = Bits(rect.X),
        ["y"] = Bits(rect.Y),
        ["width"] = Bits(rect.Width),
        ["height"] = Bits(rect.Height),
    };

    private static ulong Bits(double value) =>
        BitConverter.DoubleToUInt64Bits(value == 0.0 ? 0.0 : value);
}
