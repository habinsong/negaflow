using System.Text.Json;
using System.Text.Json.Serialization;
using Negaflow.Catalog;

namespace Negaflow.Shell;

internal static class ScannerScanCodec
{
    private const int MaximumTextLength = 512;
    private static readonly string[] RequiredAppliedOptionNames =
    [
        "deviceID",
        "resolutionDPI",
        "bitDepth",
        "colorMode",
        "filmType",
        "scanArea",
        "infrared",
        "multiExposure",
        "hardwareExposureTime",
        "brightnessAdjustment",
        "contrastAdjustment",
        "outputRawTIFF",
    ];
    private static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = false,
    };

    internal static string Serialize(ScannerPluginClient.ScanWire wire) =>
        JsonSerializer.Serialize(wire, Json);

    internal static bool TryBuild(
        ScannerPluginScanRequest request,
        out ScannerPluginClient.ScanWire? wire,
        out string? stagingDirectory)
    {
        ArgumentNullException.ThrowIfNull(request);
        wire = null;
        stagingDirectory = null;
        if (!IsRequiredText(request.Device.Id) || !IsRequiredText(request.ColorMode) ||
            !Path.IsPathFullyQualified(request.DestinationVisiblePath) ||
            request.ResolutionDpi < 0 ||
            request.BitDepth is not (8 or 16) ||
            request.Preview != (request.ResolutionDpi == 0) ||
            request.HardwareExposureTime is <= 0 ||
            request.BrightnessAdjustment is { } brightness && !double.IsFinite(brightness) ||
            request.ContrastAdjustment is { } contrast && !double.IsFinite(contrast) ||
            request.ScanArea is { } area && !IsValidScanArea(area) ||
            !request.Capabilities.ResolutionsDpi.Contains(request.ResolutionDpi) ||
            !request.Capabilities.BitDepths.Contains(request.BitDepth) ||
            !request.Capabilities.Modes.Contains(request.ColorMode, StringComparer.Ordinal) ||
            !request.Capabilities.OutputFormats.Contains("tiff", StringComparer.OrdinalIgnoreCase) ||
            request.Preview && !request.Capabilities.SupportsPreview ||
            request.Infrared && !request.Capabilities.SupportsInfrared ||
            request.MultiExposure && !request.Capabilities.SupportsMultiExposure ||
            request.ScanArea is not null && !request.Capabilities.SupportsScanArea)
        {
            return false;
        }

        string destination;
        try
        {
            destination = Path.GetFullPath(request.DestinationVisiblePath);
        }
        catch (Exception error) when (error is ArgumentException or NotSupportedException or
            PathTooLongException)
        {
            return false;
        }
        string? destinationDirectory = Path.GetDirectoryName(destination);
        if (destinationDirectory is null || !Directory.Exists(destinationDirectory) ||
            File.Exists(destination))
        {
            return false;
        }

        stagingDirectory = Path.Combine(destinationDirectory, $".negaflow-scan-{Guid.NewGuid():N}");
        string outputPath = Path.Combine(stagingDirectory, Path.GetFileName(destination));
        wire = new ScannerPluginClient.ScanWire(
            ScannerPluginProtocol.StreamProtocolVersion,
            Guid.NewGuid(),
            request.Device.Id,
            request.ResolutionDpi,
            request.BitDepth,
            request.ColorMode,
            FormatFilmType(request.Process),
            request.Preview,
            request.MultiExposure,
            request.Infrared,
            request.BrightnessAdjustment,
            request.ContrastAdjustment,
            request.ScanArea,
            request.HardwareExposureTime,
            request.OutputRawTiff,
            request.Capabilities.CapabilityToken,
            outputPath);
        return true;
    }

    internal static bool TryValidateV2Result(
        JsonElement payload,
        ScannerPluginClient.ScanWire wire,
        out string? infraredPath,
        out ScannerArtifactRequirements? artifactRequirements)
    {
        infraredPath = null;
        artifactRequirements = null;
        try
        {
            if (!HasRequiredAppliedOptionNames(payload))
            {
                return false;
            }
            ScanResultResponse? result = payload.Deserialize<ScanResultResponse>(Json);
            if (result is null ||
                !string.Equals(result.Path, wire.OutputPath, StringComparison.OrdinalIgnoreCase) ||
                result.ResolutionDpi != wire.ResolutionDpi || result.BitDepth != wire.BitDepth ||
                result.HasInfrared != wire.Infrared || !AppliedOptionsMatch(result.AppliedOptions, wire))
            {
                return false;
            }
            if (result.Width is not int width || width <= 0 ||
                result.Height is not int height || height <= 0)
            {
                return false;
            }

            artifactRequirements = new ScannerArtifactRequirements(
                width,
                height,
                wire.BitDepth,
                wire.ColorMode);
            if (!wire.Infrared)
            {
                return result.IrPath is null;
            }
            if (string.IsNullOrWhiteSpace(result.IrPath) ||
                !IsContainedPath(Path.GetDirectoryName(wire.OutputPath)!, result.IrPath))
            {
                return false;
            }
            infraredPath = Path.GetFullPath(result.IrPath);
            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private static bool AppliedOptionsMatch(
        AppliedScanOptionsResponse? applied,
        ScannerPluginClient.ScanWire requested) => applied is not null &&
        applied.DeviceId == requested.DeviceId &&
        applied.ResolutionDpi == requested.ResolutionDpi &&
        applied.BitDepth == requested.BitDepth &&
        applied.ColorMode == requested.ColorMode &&
        applied.FilmType == requested.FilmType &&
        applied.Infrared == requested.Infrared &&
        applied.MultiExposure == requested.MultiExposure &&
        applied.HardwareExposureTime == requested.HardwareExposureTime &&
        applied.BrightnessAdjustment == requested.BrightnessAdjustment &&
        applied.ContrastAdjustment == requested.ContrastAdjustment &&
        applied.OutputRawTiff == requested.OutputRawTiff &&
        ScanAreasMatch(applied.ScanArea, requested.ScanArea);

    private static bool HasRequiredAppliedOptionNames(JsonElement payload)
    {
        if (payload.ValueKind != JsonValueKind.Object ||
            !payload.TryGetProperty("appliedOptions", out JsonElement applied) ||
            applied.ValueKind != JsonValueKind.Object)
        {
            return false;
        }
        return RequiredAppliedOptionNames.All(name => applied.TryGetProperty(name, out _));
    }

    private static bool ScanAreasMatch(
        ScannerPluginScanArea? applied,
        ScannerPluginScanArea? requested) =>
        applied is null && requested is null ||
        applied is not null && requested is not null &&
        applied.OriginXmm == requested.OriginXmm &&
        applied.OriginYmm == requested.OriginYmm &&
        applied.WidthMm == requested.WidthMm &&
        Math.Abs(applied.HeightMm - requested.HeightMm) < 1.0;

    private static bool IsValidScanArea(ScannerPluginScanArea area) =>
        double.IsFinite(area.OriginXmm) && double.IsFinite(area.OriginYmm) &&
        double.IsFinite(area.WidthMm) && double.IsFinite(area.HeightMm) &&
        area.OriginXmm >= 0 && area.OriginYmm >= 0 && area.WidthMm > 0 && area.HeightMm > 0;

    private static bool IsContainedPath(string directory, string path)
    {
        try
        {
            string candidate = Path.GetFullPath(path);
            string relative = Path.GetRelativePath(directory, candidate);
            return relative.Length != 0 && !Path.IsPathFullyQualified(relative) &&
                !relative.Equals("..", StringComparison.Ordinal) &&
                !relative.StartsWith($"..{Path.DirectorySeparatorChar}", StringComparison.Ordinal);
        }
        catch (Exception error) when (error is ArgumentException or NotSupportedException or
            PathTooLongException)
        {
            return false;
        }
    }

    private static string FormatFilmType(DevelopmentProcess process) => process switch
    {
        DevelopmentProcess.C41 => "colorNegative",
        DevelopmentProcess.E6 or DevelopmentProcess.DigitalColor => "colorPositive",
        DevelopmentProcess.D76 => "bwNegative",
        DevelopmentProcess.BlackAndWhiteReversal or DevelopmentProcess.DigitalBlackAndWhite =>
            "bwPositive",
        _ => throw new ArgumentOutOfRangeException(nameof(process)),
    };

    private static bool IsRequiredText(string? value) =>
        !string.IsNullOrWhiteSpace(value) && value.Length <= MaximumTextLength &&
        value.All(character => !char.IsControl(character));

    private sealed record ScanResultResponse(
        string? Path,
        int? Width,
        int? Height,
        [property: JsonPropertyName("resolutionDPI")] int? ResolutionDpi,
        int? BitDepth,
        string? IrPath,
        bool? HasInfrared,
        AppliedScanOptionsResponse? AppliedOptions);

    private sealed record AppliedScanOptionsResponse(
        [property: JsonPropertyName("deviceID")] string? DeviceId,
        [property: JsonPropertyName("resolutionDPI")] int? ResolutionDpi,
        int? BitDepth,
        string? ColorMode,
        string? FilmType,
        ScannerPluginScanArea? ScanArea,
        bool? Infrared,
        bool? MultiExposure,
        int? HardwareExposureTime,
        double? BrightnessAdjustment,
        double? ContrastAdjustment,
        [property: JsonPropertyName("outputRawTIFF")] bool? OutputRawTiff);
}
