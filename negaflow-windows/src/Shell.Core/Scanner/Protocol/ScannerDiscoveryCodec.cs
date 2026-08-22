using System.Text.Encodings.Web;
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
    /// <summary>
    /// 플러그인과 주고받는 JSON 입니다.
    /// </summary>
    /// <remarks>
    /// <b>인코더를 기본값으로 두면 안 됩니다.</b> <c>JavaScriptEncoder.Default</c> 는 ASCII
    /// 밖의 모든 글자를 <c>\uXXXX</c> 로 이스케이프합니다. macOS 의 <c>JSONEncoder</c> 는
    /// 그러지 않고 원시 UTF-8 로 냅니다 — 즉 같은 요청이 두 플랫폼에서 <b>다른 바이트</b>로
    /// 나갔습니다.
    ///
    /// 실측(2026-08-22): 스캔 목적지의 기본 롤 폴더가 한국어 "무제 필름" 이라
    /// <c>outputPath</c> 에 한글이 들어갑니다. 같은 경로를 원시 UTF-8 로 보내면 스캔이 정상
    /// 완료(exit 0, 3,030,480 bytes)되고, <c>\uXXXX</c> 로 보내면 플러그인이
    /// <c>0xC0000409</c>(STATUS_STACK_BUFFER_OVERRUN)로 죽었습니다. 화면에는
    /// "ProcessFailed" 한 줄만 나오고, 폴더 이름이 ASCII 인 언어에서는 재현되지 않습니다.
    ///
    /// 이스케이프를 받아 죽는 것은 플러그인 쪽 결함이기도 하지만, 호스트가 macOS 와 다른
    /// 바이트를 내는 것 자체가 파리티 위반입니다. 여기서 macOS 와 같은 모양으로 맞춥니다.
    /// </remarks>
    private static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = false,
        // macOS `JSONEncoder` 와 같은 규칙: 따옴표·역슬래시·제어 문자만 이스케이프합니다.
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
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

            // macOS `ExternalScannerBackend.capabilities(for:)` 와 같은 판정입니다.
            // 단위를 보고했는데 우리가 모르는 단위면 영역 지정을 쓰지 않습니다 — mm 로 읽고
            // 엉뚱한 자리를 스캔하는 것보다 낫습니다.
            string? scanAreaUnit = string.IsNullOrWhiteSpace(decoded.ScanAreaUnit)
                ? null
                : decoded.ScanAreaUnit;
            bool knownUnit = scanAreaUnit is null or "millimeter" or "inch" or "pixel";
            bool supportsScanArea = (decoded.SupportsScanArea ?? false) && knownUnit;
            ScannerOptionRange? originX = Range(decoded.ScanOriginXRange);
            ScannerOptionRange? originY = Range(decoded.ScanOriginYRange);
            ScannerOptionRange? widthRange = Range(decoded.ScanWidthRange);
            ScannerOptionRange? heightRange = Range(decoded.ScanHeightRange);
            bool supportsPositionedScanArea = supportsScanArea &&
                decoded.SupportsPositionedScanArea == true &&
                originX is not null && originY is not null &&
                widthRange is not null && heightRange is not null;
            ScannerPluginScanArea maximumArea = new(
                decoded.MaxScanAreaOriginXMm ?? 0.0,
                decoded.MaxScanAreaOriginYMm ?? 0.0,
                decoded.MaxScanAreaWidthMm ?? 0.0,
                decoded.MaxScanAreaHeightMm ?? 0.0);
            ScannerPluginScanArea minimumArea = new(
                decoded.MinScanAreaOriginXMm ?? decoded.MaxScanAreaOriginXMm ?? 0.0,
                decoded.MinScanAreaOriginYMm ?? decoded.MaxScanAreaOriginYMm ?? 0.0,
                decoded.MinScanAreaWidthMm ?? 0.0,
                decoded.MinScanAreaHeightMm ?? 0.0);
            capabilities = new ScannerPluginCapabilities(
                decoded.ResolutionsDpi!,
                decoded.Modes!,
                decoded.BitDepths!,
                decoded.SupportsPreview ?? false,
                decoded.SupportsTransparency ?? false,
                decoded.SupportsInfrared ?? false,
                decoded.SupportsMultiExposure ?? false,
                supportsScanArea,
                supportsPositionedScanArea,
                decoded.OutputFormats!,
                string.IsNullOrWhiteSpace(decoded.CapabilityToken) ? null : decoded.CapabilityToken,
                Positive(decoded.MaxScanAreaWidthMm),
                Positive(decoded.MaxScanAreaHeightMm),
                minimumArea,
                maximumArea,
                scanAreaUnit,
                Range(decoded.BrightnessRange),
                Range(decoded.ContrastRange),
                Range(decoded.HardwareExposureRange),
                originX,
                originY,
                widthRange,
                heightRange);
            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private static double? Positive(double? value) =>
        value is { } number && double.IsFinite(number) && number > 0.0 ? number : null;

    /// <summary>
    /// macOS 는 <c>ScannerOptionRange</c> 를 그대로 디코딩합니다. 유한하지 않거나 뒤집힌
    /// 범위는 없는 것으로 둡니다 — 그런 범위로 격자를 맞추면 값이 튑니다.
    /// </summary>
    private static ScannerOptionRange? Range(OptionRangeResponse? value) =>
        value is { Minimum: { } minimum, Maximum: { } maximum } &&
        double.IsFinite(minimum) && double.IsFinite(maximum) && maximum >= minimum
            ? new ScannerOptionRange(
                minimum,
                maximum,
                value.Step is { } step && double.IsFinite(step) && step > 0.0 ? step : null)
            : null;

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

    private sealed record OptionRangeResponse(double? Minimum, double? Maximum, double? Step);

    // 키 이름은 플러그인 wire 계약(protocol v2)이 정합니다. macOS `PluginCapabilities` 가 읽는
    // 것과 같은 이름이어야 하며, `maxScanWidthMM` 처럼 비슷하지만 다른 이름을 읽으면 값이
    // 조용히 null 이 되어 평판 영역 워크플로가 통째로 사라집니다.
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
        [property: JsonPropertyName("minScanAreaWidthMM")] double? MinScanAreaWidthMm,
        [property: JsonPropertyName("minScanAreaHeightMM")] double? MinScanAreaHeightMm,
        [property: JsonPropertyName("minScanAreaOriginXMM")] double? MinScanAreaOriginXMm,
        [property: JsonPropertyName("minScanAreaOriginYMM")] double? MinScanAreaOriginYMm,
        [property: JsonPropertyName("maxScanAreaWidthMM")] double? MaxScanAreaWidthMm,
        [property: JsonPropertyName("maxScanAreaHeightMM")] double? MaxScanAreaHeightMm,
        [property: JsonPropertyName("maxScanAreaOriginXMM")] double? MaxScanAreaOriginXMm,
        [property: JsonPropertyName("maxScanAreaOriginYMM")] double? MaxScanAreaOriginYMm,
        string? ScanAreaUnit,
        OptionRangeResponse? BrightnessRange,
        OptionRangeResponse? ContrastRange,
        OptionRangeResponse? HardwareExposureRange,
        OptionRangeResponse? ScanOriginXRange,
        OptionRangeResponse? ScanOriginYRange,
        OptionRangeResponse? ScanWidthRange,
        OptionRangeResponse? ScanHeightRange);
}
