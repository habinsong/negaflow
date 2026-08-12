using System.Text.Json;
using System.Text.Json.Serialization;

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

// The first product-facing scanner operation. It intentionally has no WIA/TWAIN knowledge:
// approved adapters provide discoverable devices through the same bounded JSON process boundary.
public static class ScannerPluginClient
{
    private const int MaximumDevices = 128;
    private const int MaximumTextLength = 512;
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
}
