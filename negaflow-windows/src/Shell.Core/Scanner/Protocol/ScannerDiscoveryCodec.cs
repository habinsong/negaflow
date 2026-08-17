using System.Text.Json;
using System.Text.Json.Serialization;

namespace Negaflow.Shell;

internal static class ScannerDiscoveryCodec
{
    private const int MaximumDevices = 128;
    private const int MaximumTextLength = 512;

    // capabilityToken 은 화면에 나가는 글이 아니라 플러그인이 발급하고 스캔 요청에 그대로
    // 돌려보내는 불투명 값이다. 그 안에 장치의 SANE 옵션 덤프가 들어 있어 표시용 512자
    // 규칙에 걸리면 응답 전체가 버려지고, 화면에는 "심도 옵션을 보고하지 않는다"만 남는다.
    // 실측: OpticFilm 8100 은 4,148자, Epson GT-X900 은 5,012자다. 상한은 전송 계층이
    // 이미 보장하는 stdout 줄 한 개 크기(256 KiB)에 맞춘다.
    private const int MaximumTokenLength = 256 * 1024;
    private static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = false,
    };

    internal static string BuildCapabilitiesRequest(ScannerPluginDevice device) =>
        JsonSerializer.Serialize(
            new CapabilityRequest(device.Id, device.Vendor, device.Model),
            Json);

    internal static bool TryParseDetectedDevices(
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

    internal static bool TryParseCapabilities(
        string response,
        out ScannerPluginCapabilities? capabilities)
    {
        capabilities = null;
        try
        {
            CapabilitiesResponse? decoded = JsonSerializer.Deserialize<CapabilitiesResponse>(response, Json);
            if (decoded is null || !AreSupportedResolutions(decoded.ResolutionsDpi) ||
                !AreDistinctValues(decoded.Modes, IsSupportedMode) ||
                !AreDistinctValues(decoded.BitDepths, value => value is 8 or 16) ||
                !AreDistinctValues(decoded.OutputFormats, IsSafeText) ||
                !IsOptionalToken(decoded.CapabilityToken))
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
                string.IsNullOrWhiteSpace(decoded.CapabilityToken) ? null : decoded.CapabilityToken,
                Positive(decoded.MaxScanWidthMm),
                Positive(decoded.MaxScanHeightMm));
            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private static double? Positive(double? value) =>
        value is { } number && double.IsFinite(number) && number > 0.0 ? number : null;

    private static bool IsRequiredText(string? value) =>
        !string.IsNullOrWhiteSpace(value) && IsOptionalText(value);

    private static bool IsOptionalText(string? value) => value is null || IsSafeText(value);

    private static bool IsOptionalToken(string? value) =>
        value is null ||
        (value.Length <= MaximumTokenLength && value.All(character => !char.IsControl(character)));

    private static bool IsSafeText(string value) =>
        value.Length <= MaximumTextLength && value.All(character => !char.IsControl(character));

    private static bool AreSupportedResolutions(List<int>? values) =>
        values is { Count: > 0 and <= 64 } &&
        values.All(value => value is >= 0 and <= 19_200) &&
        values.Distinct().Count() == values.Count;

    private static bool AreDistinctValues<T>(List<T>? values, Func<T, bool> isValid)
        where T : notnull => values is { Count: > 0 and <= 64 } &&
        values.All(isValid) && values.Distinct().Count() == values.Count;

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
        string? CapabilityToken,
        [property: JsonPropertyName("maxScanWidthMM")] double? MaxScanWidthMm,
        [property: JsonPropertyName("maxScanHeightMM")] double? MaxScanHeightMm);
}
