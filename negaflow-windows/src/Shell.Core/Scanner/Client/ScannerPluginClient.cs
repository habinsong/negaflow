using System.Text.Json;
using System.Text.Json.Serialization;
using Negaflow.Catalog;
using Negaflow.Interop;

namespace Negaflow.Shell;

public static class ScannerPluginClient
{
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
            !TryParseDetectedDevices(
                string.Join('\n', process.StandardOutputLines),
                out IReadOnlyList<ScannerPluginDevice> devices))
        {
            return new(process, [], process.IsSuccess);
        }
        return new(process, devices, false);
    }

    public static bool TryParseDetectedDevices(
        string response,
        out IReadOnlyList<ScannerPluginDevice> devices) =>
        ScannerDiscoveryCodec.TryParseDetectedDevices(response, out devices);

    public static async Task<ScannerPluginCapabilitiesResult> GetCapabilitiesAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        ScannerPluginDevice device,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(device);
        ScannerPluginProcessResult process = await ScannerPluginProcessHost.RunAsync(
            plugin,
            approvedIdentity,
            "capabilities",
            [device.Id],
            ScannerDiscoveryCodec.BuildCapabilitiesRequest(device),
            cancellationToken: cancellationToken);
        if (!process.IsSuccess ||
            !TryParseCapabilities(
                string.Join('\n', process.StandardOutputLines),
                out ScannerPluginCapabilities? capabilities))
        {
            return new(process, null, process.IsSuccess);
        }
        return new(process, capabilities, false);
    }

    public static bool TryParseCapabilities(
        string response,
        out ScannerPluginCapabilities? capabilities) =>
        ScannerDiscoveryCodec.TryParseCapabilities(response, out capabilities);

    public static Task<ScannerPluginScanResult> ScanAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        ScannerPluginScanRequest request,
        CancellationToken cancellationToken = default) =>
        ScannerScanExecutor.ScanAsync(plugin, approvedIdentity, request, cancellationToken);

    public static Task<ScannerPluginLibraryScanResult> ScanAndPublishAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        ScannerPluginScanRequest request,
        LibraryHostService library,
        ImageTransformRecipe? initialTransform = null,
        InfraredDetectorParameters? infraredParameters = null,
        DevelopRun? run = null,
        bool isPreviewScan = false,
        CancellationToken cancellationToken = default,
        Action<ScanProgressReport>? onProgress = null) =>
        ScannerScanPublisher.ScanAndPublishAsync(
            plugin,
            approvedIdentity,
            request,
            library,
            initialTransform,
            infraredParameters,
            run,
            isPreviewScan,
            cancellationToken,
            onProgress);

    public static bool TryBuildScanWire(
        ScannerPluginScanRequest request,
        out ScanWire? wire,
        out string? stagingDirectory) =>
        ScannerScanCodec.TryBuild(request, out wire, out stagingDirectory);

    internal static bool TryValidateV2Result(
        JsonElement payload,
        ScanWire wire,
        out string? infraredPath,
        out ScannerArtifactRequirements? artifactRequirements,
        out ScannerPluginScanArea? appliedScanArea) =>
        ScannerScanCodec.TryValidateV2Result(
            payload,
            wire,
            out infraredPath,
            out artifactRequirements,
            out appliedScanArea);

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
}
