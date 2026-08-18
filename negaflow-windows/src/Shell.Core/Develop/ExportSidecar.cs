using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 내보낸 산출물 옆에 붙는 파일들의 이름입니다. macOS <c>ExportArtifactLayout</c> 과 같은 규칙이며
/// 접미사도 같습니다.
/// </summary>
public static class ExportArtifactPairing
{
    public const string MainFlatSuffix = "main-flat";

    public const string OriginalRawSuffix = "original";

    public static string SidecarPath(string outputPath) =>
        WithoutExtension(outputPath) + ".negaflow.json";

    public static string XmpPath(string outputPath) =>
        WithoutExtension(outputPath) + ".xmp";

    /// <summary>원본을 그대로 옆에 두는 자리입니다. 확장자는 원본의 것을 지킵니다.</summary>
    public static string OriginalPath(string outputPath, string sourcePath)
    {
        string extension = Path.GetExtension(sourcePath);
        return WithoutExtension(outputPath) + "-" + OriginalRawSuffix +
            (extension.Length == 0 ? ".tiff" : extension);
    }

    private static string WithoutExtension(string outputPath)
    {
        ArgumentException.ThrowIfNullOrEmpty(outputPath);
        string directory = Path.GetDirectoryName(outputPath) ?? string.Empty;
        return Path.Combine(directory, Path.GetFileNameWithoutExtension(outputPath));
    }
}

/// <summary>
/// 내보내기 사이드카입니다. macOS 처럼 **산출물 옆에만** 씁니다 — 원본 옆의 기존 XMP 를 병합 없이
/// 덮어쓰지 않습니다.
/// </summary>
/// <remarks>
/// 현상 레시피는 catalog 의 <c>params</c> 노드를 통째로 옮깁니다. 필드를 다시 나열하면 recipe 축이
/// 늘 때마다 사이드카가 조용히 뒤처집니다 — 버전 저장과 같은 이유, 같은 방식입니다.
/// </remarks>
public static class ExportSidecarWriter
{
    public const string XmpNamespace = "https://negaflow.app/ns/1.0/";

    private static readonly JsonSerializerOptions Json = new()
    {
        WriteIndented = true,
    };

    /// <summary>사이드카 두 개를 씁니다. 실패하면 무엇이 실패했는지 이름으로 돌려줍니다.</summary>
    public static string? Write(
        string outputPath,
        ExportSidecarContent content)
    {
        ArgumentException.ThrowIfNullOrEmpty(outputPath);
        ArgumentNullException.ThrowIfNull(content);
        try
        {
            File.WriteAllText(
                ExportArtifactPairing.SidecarPath(outputPath),
                BuildJson(content),
                new UTF8Encoding(false));
            File.WriteAllText(
                ExportArtifactPairing.XmpPath(outputPath),
                BuildXmp(content),
                new UTF8Encoding(false));
            return null;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            PathTooLongException or NotSupportedException)
        {
            return "sidecar_write_failed";
        }
    }

    public static string BuildJson(ExportSidecarContent content)
    {
        ArgumentNullException.ThrowIfNull(content);
        var root = new JsonObject
        {
            ["appVersion"] = content.AppVersion,
            ["engineVersion"] = content.EngineVersion,
            ["filmType"] = content.FilmType,
            ["rating"] = content.Rating,
            ["pickState"] = content.PickState,
        };
        if (content.BaseSample is { } sample)
        {
            root["baseSample"] = new JsonObject
            {
                ["r"] = sample.R,
                ["g"] = sample.G,
                ["b"] = sample.B,
                ["source"] = sample.Source,
            };
        }
        if (content.FilmBaseDiagnostics is { } diagnostics)
        {
            root["filmBaseDiagnostics"] = WriteFilmBaseDiagnostics(diagnostics);
        }
        if (content.PresetName is { } presetName)
        {
            root["presetName"] = presetName;
        }
        if (content.Parameters is { } parameters)
        {
            root["parameters"] = parameters.DeepClone();
        }
        if (content.AppMetadata is { } overlay && !overlay.IsEmpty)
        {
            var metadata = new JsonObject();
            AddIfPresent(metadata, "title", overlay.Title);
            AddIfPresent(metadata, "caption", overlay.Caption);
            AddIfPresent(metadata, "copyright", overlay.Copyright);
            if (overlay.Keywords.Count > 0)
            {
                var keywords = new JsonArray();
                foreach (string keyword in overlay.Keywords)
                {
                    keywords.Add(keyword);
                }
                metadata["keywords"] = keywords;
            }
            if (overlay.FilmShot is { } shot && !shot.IsEmpty)
            {
                var shotNode = new JsonObject();
                AddIfPresent(shotNode, "cameraMake", shot.CameraMake);
                AddIfPresent(shotNode, "cameraModel", shot.CameraModel);
                AddIfPresent(shotNode, "lensModel", shot.LensModel);
                AddIfPresent(shotNode, "filmStock", shot.FilmStock);
                if (shot.IsoSpeed is { } iso)
                {
                    shotNode["isoSpeed"] = iso;
                }
                if (shot.ExposureTimeSeconds is { } exposure)
                {
                    shotNode["exposureTimeSeconds"] = exposure;
                }
                if (shot.FNumber is { } fNumber)
                {
                    shotNode["fNumber"] = fNumber;
                }
                if (shot.FocalLengthMm is { } focal)
                {
                    shotNode["focalLengthMM"] = focal;
                }
                metadata["filmShot"] = shotNode;
            }
            root["appMetadata"] = metadata;
        }
        root["exportEncoding"] = new JsonObject
        {
            ["format"] = content.Format.ToString(),
            ["dpi"] = content.Encoding.Dpi,
            ["longEdge"] = content.Encoding.LongEdge,
            ["jpegQuality"] = content.Encoding.JpegQuality,
            ["tiffCompression"] = content.Encoding.TiffCompression.ToString(),
            ["preserveAlpha"] = content.Encoding.PreserveAlpha,
            ["outputSharpening"] = content.Encoding.OutputSharpening,
            ["outputSharpeningMedium"] = content.Encoding.OutputSharpeningMedium.ToString(),
        };
        root["exportHistory"] = new JsonArray(new JsonObject
        {
            ["path"] = content.OutputPath,
            ["format"] = content.Format.ToString(),
            ["at"] = content.ExportedAt.ToUniversalTime().ToString(
                "yyyy-MM-ddTHH:mm:ssZ",
                CultureInfo.InvariantCulture),
        });
        return root.ToJsonString(Json);
    }

    /// <summary>
    /// macOS 와 같은 XMP 패킷입니다. 같은 네임스페이스, 같은 속성 이름, 같은 숫자 표기입니다 —
    /// 다른 앱이 두 플랫폼의 파일을 같은 것으로 읽어야 합니다.
    /// </summary>
    public static string BuildXmp(ExportSidecarContent content)
    {
        ArgumentNullException.ThrowIfNull(content);
        var attributes = new List<(string Name, string Value)>
        {
            ("xmp:CreatorTool", "negaflow " + content.AppVersion),
            ("negaflow:AppVersion", content.AppVersion),
            ("negaflow:EngineVersion", content.EngineVersion),
            ("negaflow:FilmType", content.FilmType),
            // macOS 와 같이 거부된 사진은 XMP 별점 -1 입니다.
            ("xmp:Rating", string.Equals(content.PickState, "rejected", StringComparison.Ordinal)
                ? "-1"
                : content.Rating.ToString(CultureInfo.InvariantCulture)),
            ("negaflow:Rating", content.Rating.ToString(CultureInfo.InvariantCulture)),
            ("negaflow:PickState", content.PickState),
        };
        if (content.PresetName is { } presetName)
        {
            attributes.Add(("negaflow:PresetName", presetName));
        }
        if (content.BaseSample is { } sample)
        {
            attributes.Add(("negaflow:BaseSampleR", Number(sample.R)));
            attributes.Add(("negaflow:BaseSampleG", Number(sample.G)));
            attributes.Add(("negaflow:BaseSampleB", Number(sample.B)));
            attributes.Add(("negaflow:BaseSampleSource", sample.Source));
        }
        foreach ((string name, JsonNode? value) in content.Parameters ?? [])
        {
            // 숫자 축만 냅니다. 중첩 노드는 JSON 사이드카가 그대로 담습니다.
            if (value is JsonValue scalar && scalar.TryGetValue(out double number))
            {
                attributes.Add((
                    "negaflow:" + char.ToUpperInvariant(name[0]) + name[1..],
                    Number(number)));
            }
        }
        if (content.AppMetadata is { } overlay)
        {
            AddAttribute(attributes, "dc:title", overlay.Title);
            AddAttribute(attributes, "dc:description", overlay.Caption);
            AddAttribute(attributes, "dc:rights", overlay.Copyright);
            if (overlay.Keywords.Count > 0)
            {
                attributes.Add(("dc:subject", string.Join(", ", overlay.Keywords)));
            }
            if (overlay.FilmShot is { } shot)
            {
                AddAttribute(attributes, "tiff:Make", shot.CameraMake);
                AddAttribute(attributes, "tiff:Model", shot.CameraModel);
                AddAttribute(attributes, "aux:Lens", shot.LensModel);
                AddAttribute(attributes, "negaflow:FilmStock", shot.FilmStock);
                if (shot.IsoSpeed is { } iso)
                {
                    attributes.Add((
                        "exif:ISOSpeedRatings",
                        iso.ToString(CultureInfo.InvariantCulture)));
                }
                if (shot.ExposureTimeSeconds is { } exposure)
                {
                    attributes.Add(("exif:ExposureTime", Number(exposure)));
                }
                if (shot.FNumber is { } fNumber)
                {
                    attributes.Add(("exif:FNumber", Number(fNumber)));
                }
                if (shot.FocalLengthMm is { } focal)
                {
                    attributes.Add(("exif:FocalLength", Number(focal)));
                }
            }
        }
        string timestamp = content.ExportedAt.ToUniversalTime().ToString(
            "yyyy-MM-ddTHH:mm:ssZ",
            CultureInfo.InvariantCulture);
        attributes.Add(("xmp:ModifyDate", timestamp));
        attributes.Add(("xmp:MetadataDate", timestamp));

        var builder = new StringBuilder();
        builder.Append("<?xpacket begin=\"﻿\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?>\n");
        builder.Append("<x:xmpmeta xmlns:x=\"adobe:ns:meta/\" x:xmptk=\"negaflow\">\n");
        builder.Append("  <rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">\n");
        builder.Append("    <rdf:Description rdf:about=\"\"\n");
        builder.Append("        xmlns:xmp=\"http://ns.adobe.com/xap/1.0/\"\n");
        builder.Append("        xmlns:dc=\"http://purl.org/dc/elements/1.1/\"\n");
        builder.Append("        xmlns:tiff=\"http://ns.adobe.com/tiff/1.0/\"\n");
        builder.Append("        xmlns:exif=\"http://ns.adobe.com/exif/1.0/\"\n");
        builder.Append("        xmlns:aux=\"http://ns.adobe.com/exif/1.0/aux/\"\n");
        builder.Append("        xmlns:photoshop=\"http://ns.adobe.com/photoshop/1.0/\"\n");
        builder.Append("        xmlns:xmpRights=\"http://ns.adobe.com/xap/1.0/rights/\"\n");
        builder.Append(
            "        xmlns:Iptc4xmpCore=\"http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/\"\n");
        builder.Append("        xmlns:negaflow=\"" + XmpNamespace + "\"\n");
        foreach ((string name, string value) in attributes)
        {
            builder.Append("        " + name + "=\"" + Escape(value) + "\"\n");
        }
        builder.Length -= 1;
        builder.Append(">\n");
        builder.Append("    </rdf:Description>\n");
        builder.Append("  </rdf:RDF>\n");
        builder.Append("</x:xmpmeta>\n");
        builder.Append("<?xpacket end=\"w\"?>\n");
        return builder.ToString();
    }

    private static void AddAttribute(
        List<(string Name, string Value)> attributes,
        string name,
        string? value)
    {
        if (value is not null)
        {
            attributes.Add((name, value));
        }
    }

    /// <summary>macOS <c>Sidecar.FilmBaseDiagnostics</c> Codable 키입니다.</summary>
    private static JsonObject WriteFilmBaseDiagnostics(FilmBaseDiagnosticsSidecar diagnostics)
    {
        var node = new JsonObject
        {
            ["rgb"] = JsonArrayOf(diagnostics.Rgb),
            ["source"] = diagnostics.Source,
            ["dmin"] = JsonArrayOf(diagnostics.Dmin),
            ["dmax"] = diagnostics.Dmax is { } dmax ? JsonArrayOf(dmax) : null,
            ["densityRange"] = diagnostics.DensityRange is { } range
                ? JsonArrayOf(range)
                : null,
            ["confidence"] = diagnostics.Confidence,
            ["confidenceBasis"] = diagnostics.ConfidenceBasis,
            ["confidenceIsCalibratedProbability"] =
                diagnostics.ConfidenceIsCalibratedProbability,
        };
        if (diagnostics.Measurement is { } measurement)
        {
            node["measurement"] = WriteMeasurement(measurement);
        }
        else
        {
            node["measurement"] = null;
        }
        return node;
    }

    private static JsonObject WriteMeasurement(FilmBaseMeasurementSnapshot measurement)
    {
        var anomalies = new JsonArray();
        foreach (string anomaly in measurement.Anomalies)
        {
            anomalies.Add(anomaly);
        }
        return new JsonObject
        {
            ["schemaVersion"] = measurement.SchemaVersion,
            ["method"] = measurement.Method,
            ["sampledPixelCount"] = measurement.SampledPixelCount,
            ["candidateCount"] = measurement.CandidateCount,
            ["selectedSampleCount"] = measurement.SelectedSampleCount,
            ["retainedSampleCount"] = measurement.RetainedSampleCount,
            ["sampleCoverage"] = measurement.SampleCoverage,
            ["spatialCoverage"] = measurement.SpatialCoverage,
            ["medianLuma"] = measurement.MedianLuma,
            ["lumaMAD"] = measurement.LumaMad,
            ["channelMAD"] = JsonArrayOf(measurement.ChannelMad),
            ["chromaticityMAD"] = measurement.ChromaticityMad,
            ["clippedFraction"] = measurement.ClippedFraction,
            ["outlierFraction"] = measurement.OutlierFraction,
            ["evidenceComponents"] = new JsonObject
            {
                ["sampleSupport"] = measurement.SampleSupport,
                ["sampleCoverage"] = measurement.EvidenceSampleCoverage,
                ["spatialCoverage"] = measurement.EvidenceSpatialCoverage,
                ["lumaUniformity"] = measurement.LumaUniformity,
                ["channelConsistency"] = measurement.ChannelConsistency,
                ["unclippedSamples"] = measurement.UnclippedSamples,
                ["inlierRetention"] = measurement.InlierRetention,
            },
            ["evidenceScore"] = measurement.EvidenceScore,
            ["isCalibratedProbability"] = measurement.IsCalibratedProbability,
            ["anomalies"] = anomalies,
        };
    }

    private static JsonArray JsonArrayOf(IReadOnlyList<double> values)
    {
        var array = new JsonArray();
        foreach (double value in values)
        {
            array.Add(value);
        }
        return array;
    }

    private static void AddIfPresent(JsonObject owner, string name, string? value)
    {
        if (value is not null)
        {
            owner[name] = value;
        }
    }

    /// <summary>macOS 와 같은 <c>%.6g</c> 표기입니다.</summary>
    private static string Number(double value) =>
        value.ToString("G6", CultureInfo.InvariantCulture);

    private static string Escape(string value) => value
        .Replace("&", "&amp;", StringComparison.Ordinal)
        .Replace("\"", "&quot;", StringComparison.Ordinal)
        .Replace("'", "&apos;", StringComparison.Ordinal)
        .Replace("<", "&lt;", StringComparison.Ordinal)
        .Replace(">", "&gt;", StringComparison.Ordinal);
}

/// <summary>사이드카에 실릴 값입니다. 파일 접근 없이 본문을 시험할 수 있도록 따로 둡니다.</summary>
public sealed record ExportSidecarContent
{
    public required string OutputPath { get; init; }

    public required DevelopExportFormat Format { get; init; }

    public required ExportEncodingOptions Encoding { get; init; }

    public string AppVersion { get; init; } = "0.0.0";

    public string EngineVersion { get; init; } = "0.0.0";

    public string FilmType { get; init; } = "colorNegative";

    public string PickState { get; init; } = "unflagged";

    public int Rating { get; init; }

    public string? PresetName { get; init; }

    /// <summary>catalog 의 <c>params</c> 노드 그대로입니다.</summary>
    public JsonObject? Parameters { get; init; }

    public FilmBaseSampleSidecar? BaseSample { get; init; }

    public FilmBaseDiagnosticsSidecar? FilmBaseDiagnostics { get; init; }

    public AppMetadataOverlay? AppMetadata { get; init; }

    public DateTimeOffset ExportedAt { get; init; } = DateTimeOffset.UtcNow;
}
