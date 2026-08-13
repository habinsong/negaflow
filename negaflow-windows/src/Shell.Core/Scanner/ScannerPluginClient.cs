using System.Text.Json;
using System.Text.Json.Serialization;
using Negaflow.Catalog;
using Negaflow.Interop;

namespace Negaflow.Shell;

public sealed record ScannerPluginDevice(
    string Id,
    string DisplayName,
    string Vendor,
    string Model,
    string? ConnectionType,
    string? UsbVendorId,
    string? UsbProductId,
    string? SerialNumber,
    string? VerifiedStatus,
    string? DriverVersion);

public sealed record ScannerPluginDetectResult(
    ScannerPluginProcessResult Process,
    IReadOnlyList<ScannerPluginDevice> Devices,
    bool IsMalformedResponse)
{
    public bool IsSuccess => Process.IsSuccess && !IsMalformedResponse;
}

public sealed record ScannerPluginCapabilities(
    IReadOnlyList<int> ResolutionsDpi,
    IReadOnlyList<string> Modes,
    IReadOnlyList<int> BitDepths,
    bool SupportsPreview,
    bool SupportsTransparency,
    bool SupportsInfrared,
    bool SupportsMultiExposure,
    bool SupportsScanArea,
    bool SupportsPositionedScanArea,
    IReadOnlyList<string> OutputFormats,
    string? CapabilityToken);

public sealed record ScannerPluginCapabilitiesResult(
    ScannerPluginProcessResult Process,
    ScannerPluginCapabilities? Capabilities,
    bool IsMalformedResponse)
{
    public bool IsSuccess => Process.IsSuccess && !IsMalformedResponse && Capabilities is not null;
}

public sealed record ScannerPluginScanArea(
    [property: JsonPropertyName("originXMM")] double OriginXmm,
    [property: JsonPropertyName("originYMM")] double OriginYmm,
    [property: JsonPropertyName("widthMM")] double WidthMm,
    [property: JsonPropertyName("heightMM")] double HeightMm);

public sealed record ScannerPluginScanRequest(
    ScannerPluginDevice Device,
    ScannerPluginCapabilities Capabilities,
    DevelopmentProcess Process,
    int ResolutionDpi,
    int BitDepth,
    string ColorMode,
    bool Preview,
    bool Infrared,
    bool MultiExposure,
    ScannerPluginScanArea? ScanArea,
    bool OutputRawTiff,
    string DestinationVisiblePath,
    double? BrightnessAdjustment = null,
    double? ContrastAdjustment = null,
    int? HardwareExposureTime = null);

public enum ScannerPluginScanStatus
{
    Completed,
    InvalidRequest,
    CapabilityMismatch,
    StagingCreateFailed,
    ProcessFailed,
    ProtocolViolation,
    PluginError,
    ResultMismatch,
    ArtifactCommitFailed,
}

public sealed record ScannerPluginScanResult(
    ScannerPluginScanStatus Status,
    ScannerPluginProcessResult? Process,
    ScannerPluginStreamStatus? ProtocolStatus,
    ScannerArtifactCommitResult? ArtifactCommit)
{
    public bool IsSuccess => Status == ScannerPluginScanStatus.Completed &&
        ArtifactCommit is { IsSuccess: true };
}

public enum ScannerPluginLibraryScanStatus
{
    Published,
    ScanFailed,
    CatalogPublicationFailed,
}

public sealed record ScannerPluginLibraryScanResult(
    ScannerPluginLibraryScanStatus Status,
    ScannerPluginScanResult Scan,
    ScannerFramePublishResult? Publication)
{
    public bool IsSuccess => Status == ScannerPluginLibraryScanStatus.Published;
}

// The first product-facing scanner operation. It intentionally has no WIA/TWAIN knowledge:
// approved adapters provide discoverable devices through the same bounded JSON process boundary.
public static class ScannerPluginClient
{
    private const int MaximumDevices = 128;
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

    public static async Task<ScannerPluginDetectResult> DetectAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        CancellationToken cancellationToken = default)
    {
        ScannerPluginProcessResult process = await ScannerPluginProcessHost.RunAsync(
            plugin,
            approvedIdentity,
            "detect",
            [],
            null,
            cancellationToken: cancellationToken);
        if (!process.IsSuccess ||
            !TryParseDetectedDevices(string.Join('\n', process.StandardOutputLines), out IReadOnlyList<ScannerPluginDevice> devices))
        {
            return new(process, [], process.IsSuccess);
        }
        return new(process, devices, false);
    }

    public static bool TryParseDetectedDevices(
        string response,
        out IReadOnlyList<ScannerPluginDevice> devices)
    {
        devices = [];
        try
        {
            DetectResponse? decoded = JsonSerializer.Deserialize<DetectResponse>(response, Json);
            if (decoded?.Devices is not { Count: <= MaximumDevices })
            {
                return false;
            }

            var result = new List<ScannerPluginDevice>(decoded.Devices.Count);
            var ids = new HashSet<string>(StringComparer.Ordinal);
            foreach (DeviceResponse device in decoded.Devices)
            {
                if (!IsRequiredText(device.Id) || !IsRequiredText(device.DisplayName) ||
                    !IsRequiredText(device.Vendor) || !IsRequiredText(device.Model) ||
                    !ids.Add(device.Id!) || !IsOptionalText(device.ConnectionType) ||
                    !IsOptionalText(device.UsbVendorId) || !IsOptionalText(device.UsbProductId) ||
                    !IsOptionalText(device.SerialNumber) || !IsOptionalText(device.VerifiedStatus) ||
                    !IsOptionalText(device.DriverVersion))
                {
                    return false;
                }

                result.Add(new ScannerPluginDevice(
                    device.Id!,
                    device.DisplayName!,
                    device.Vendor!,
                    device.Model!,
                    device.ConnectionType,
                    device.UsbVendorId,
                    device.UsbProductId,
                    device.SerialNumber,
                    device.VerifiedStatus,
                    device.DriverVersion));
            }
            devices = result;
            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    public static async Task<ScannerPluginCapabilitiesResult> GetCapabilitiesAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        ScannerPluginDevice device,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(device);
        string request = JsonSerializer.Serialize(
            new CapabilityRequest(device.Id, device.Vendor, device.Model),
            Json);
        ScannerPluginProcessResult process = await ScannerPluginProcessHost.RunAsync(
            plugin,
            approvedIdentity,
            "capabilities",
            [device.Id],
            request,
            cancellationToken: cancellationToken);
        if (!process.IsSuccess ||
            !TryParseCapabilities(string.Join('\n', process.StandardOutputLines), out ScannerPluginCapabilities? capabilities))
        {
            return new(process, null, process.IsSuccess);
        }
        return new(process, capabilities, false);
    }

    public static bool TryParseCapabilities(string response, out ScannerPluginCapabilities? capabilities)
    {
        capabilities = null;
        try
        {
            CapabilitiesResponse? decoded = JsonSerializer.Deserialize<CapabilitiesResponse>(response, Json);
            if (decoded is null || !AreSupportedResolutions(decoded.ResolutionsDpi) ||
                !AreDistinctValues(decoded.Modes, IsSupportedMode) ||
                !AreDistinctValues(decoded.BitDepths, value => value is 8 or 16) ||
                !AreDistinctValues(decoded.OutputFormats, IsSafeText) ||
                !IsOptionalText(decoded.CapabilityToken))
            {
                return false;
            }

            capabilities = new ScannerPluginCapabilities(
                decoded.ResolutionsDpi!,
                decoded.Modes!,
                decoded.BitDepths!,
                decoded.SupportsPreview ?? false,
                decoded.SupportsTransparency ?? false,
                decoded.SupportsInfrared ?? false,
                decoded.SupportsMultiExposure ?? false,
                decoded.SupportsScanArea ?? false,
                decoded.SupportsPositionedScanArea ?? false,
                decoded.OutputFormats!,
                string.IsNullOrWhiteSpace(decoded.CapabilityToken) ? null : decoded.CapabilityToken);
            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    public static async Task<ScannerPluginScanResult> ScanAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        ScannerPluginScanRequest request,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);
        if (!TryBuildScanWire(request, out ScanWire? wire, out string? stagingDirectory))
        {
            return new(ScannerPluginScanStatus.CapabilityMismatch, null, null, null);
        }
        ScanWire scanWire = wire!;

        try
        {
            Directory.CreateDirectory(stagingDirectory!);
        }
        catch (IOException)
        {
            return new(ScannerPluginScanStatus.StagingCreateFailed, null, null, null);
        }
        catch (UnauthorizedAccessException)
        {
            return new(ScannerPluginScanStatus.StagingCreateFailed, null, null, null);
        }

        try
        {
            string input = JsonSerializer.Serialize(scanWire, Json);
            ScannerPluginProcessResult process = await ScannerPluginProcessHost.RunAsync(
                plugin,
                approvedIdentity,
                "scan",
                [request.Device.Id],
                input,
                cancellationToken: cancellationToken);
            if (!process.IsSuccess)
            {
                return new(ScannerPluginScanStatus.ProcessFailed, process, null, null);
            }

            ScannerPluginStreamValidation stream = ScannerPluginProtocol.ValidateV2(
                process.StandardOutputLines,
                scanWire.RequestId);
            if (!stream.IsSuccess)
            {
                return new(ScannerPluginScanStatus.ProtocolViolation, process, stream.Status, null);
            }
            ScannerPluginStreamEvent terminal = stream.TerminalEvent!;
            if (terminal.Type == "error")
            {
                return new(ScannerPluginScanStatus.PluginError, process, stream.Status, null);
            }
            if (!TryValidateV2Result(
                    terminal.Payload,
                    scanWire,
                    out string? infraredPath,
                    out ScannerArtifactRequirements? artifactRequirements))
            {
                return new(ScannerPluginScanStatus.ResultMismatch, process, stream.Status, null);
            }

            ScannerArtifactCommitResult committed = ScannerArtifactTransaction.Commit(
                new ScannerStagedArtifacts(stagingDirectory!, scanWire.OutputPath, infraredPath),
                request.DestinationVisiblePath,
                requirements: artifactRequirements);
            return new(
                committed.IsSuccess ? ScannerPluginScanStatus.Completed : ScannerPluginScanStatus.ArtifactCommitFailed,
                process,
                stream.Status,
                committed);
        }
        finally
        {
            try
            {
                if (Directory.Exists(stagingDirectory))
                {
                    Directory.Delete(stagingDirectory, recursive: true);
                }
            }
            catch (IOException)
            {
            }
            catch (UnauthorizedAccessException)
            {
            }
        }
    }

    // The scanner adapter never writes the catalog. Its only authority is a staged TIFF pair;
    // once that pair is verified and committed, the existing single-writer Library boundary owns
    // the durable frame record and optional IR recipe bootstrap.
    public static async Task<ScannerPluginLibraryScanResult> ScanAndPublishAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        ScannerPluginScanRequest request,
        LibraryHostService library,
        InfraredDetectorParameters? infraredParameters = null,
        DevelopRun? run = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(library);
        ScannerPluginScanResult scan = await ScanAsync(
            plugin,
            approvedIdentity,
            request,
            cancellationToken);
        if (scan.ArtifactCommit?.Artifacts is not { } artifacts)
        {
            return new(ScannerPluginLibraryScanStatus.ScanFailed, scan, null);
        }

        ScannerFramePublishResult published = library.PublishScannerFrame(
            new ScannerFrameImport(
                artifacts.VisiblePath,
                artifacts.InfraredPath,
                request.Process),
            infraredParameters,
            run);
        return new(
            published.Status == ScannerFramePublishStatus.CatalogWriteFailed
                ? ScannerPluginLibraryScanStatus.CatalogPublicationFailed
                : ScannerPluginLibraryScanStatus.Published,
            scan,
            published);
    }

    public static bool TryBuildScanWire(
        ScannerPluginScanRequest request,
        out ScanWire? wire,
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
        catch (ArgumentException)
        {
            return false;
        }
        catch (NotSupportedException)
        {
            return false;
        }
        catch (PathTooLongException)
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
        wire = new(
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

    // Nullable values are not optional JSON keys in protocol v2. Inspect the object before
    // deserializing because System.Text.Json otherwise treats an omitted nullable key as null.
    internal static bool TryValidateV2Result(
        JsonElement payload,
        ScanWire wire,
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
            if (result is null || !string.Equals(result.Path, wire.OutputPath, StringComparison.OrdinalIgnoreCase) ||
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

    private static bool AppliedOptionsMatch(AppliedScanOptionsResponse? applied, ScanWire requested) =>
        applied is not null &&
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

    private static bool ScanAreasMatch(ScannerPluginScanArea? applied, ScannerPluginScanArea? requested) =>
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
        catch (ArgumentException)
        {
            return false;
        }
        catch (NotSupportedException)
        {
            return false;
        }
        catch (PathTooLongException)
        {
            return false;
        }
    }

    private static string FormatFilmType(DevelopmentProcess process) => process switch
    {
        DevelopmentProcess.C41 => "colorNegative",
        DevelopmentProcess.E6 or DevelopmentProcess.DigitalColor => "colorPositive",
        DevelopmentProcess.D76 => "bwNegative",
        DevelopmentProcess.BlackAndWhiteReversal or DevelopmentProcess.DigitalBlackAndWhite => "bwPositive",
        _ => throw new ArgumentOutOfRangeException(nameof(process)),
    };

    private static bool IsRequiredText(string? value) =>
        !string.IsNullOrWhiteSpace(value) && IsOptionalText(value);

    private static bool IsOptionalText(string? value) =>
        value is null || IsSafeText(value);

    private static bool IsSafeText(string value) =>
        value.Length <= MaximumTextLength && value.All(character => !char.IsControl(character));

    private static bool AreSupportedResolutions(List<int>? values) =>
        values is { Count: > 0 and <= 64 } && values.All(value => value is >= 0 and <= 19_200) &&
        values.Distinct().Count() == values.Count;

    private static bool AreDistinctValues<T>(List<T>? values, Func<T, bool> isValid) where T : notnull =>
        values is { Count: > 0 and <= 64 } && values.All(isValid) &&
        values.Distinct().Count() == values.Count;

    private static bool IsSupportedMode(string value) =>
        value is "color" or "gray" or "lineart" or "infrared";

    private sealed record DetectResponse(List<DeviceResponse>? Devices);

    private sealed record DeviceResponse(
        string? Id,
        string? DisplayName,
        string? Vendor,
        string? Model,
        string? ConnectionType,
        string? UsbVendorId,
        string? UsbProductId,
        string? SerialNumber,
        string? VerifiedStatus,
        string? DriverVersion);

    private sealed record CapabilityRequest(
        [property: JsonPropertyName("deviceID")] string DeviceId,
        string Vendor,
        string Model);

    private sealed record CapabilitiesResponse(
        [property: JsonPropertyName("resolutionsDPI")] List<int>? ResolutionsDpi,
        List<string>? Modes,
        List<int>? BitDepths,
        bool? SupportsPreview,
        bool? SupportsTransparency,
        bool? SupportsInfrared,
        bool? SupportsMultiExposure,
        bool? SupportsScanArea,
        bool? SupportsPositionedScanArea,
        List<string>? OutputFormats,
        string? CapabilityToken);

    public sealed record ScanWire(
        [property: JsonPropertyName("protocolVersion")] int ProtocolVersion,
        [property: JsonPropertyName("requestID")] Guid RequestId,
        [property: JsonPropertyName("deviceID")] string DeviceId,
        [property: JsonPropertyName("resolutionDPI")] int ResolutionDpi,
        int BitDepth,
        string ColorMode,
        string FilmType,
        bool Preview,
        bool MultiExposure,
        bool Infrared,
        double? BrightnessAdjustment,
        double? ContrastAdjustment,
        ScannerPluginScanArea? ScanArea,
        int? HardwareExposureTime,
        [property: JsonPropertyName("outputRawTIFF")] bool OutputRawTiff,
        string? CapabilityToken,
        string OutputPath);

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
