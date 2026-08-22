using System.Text.Encodings.Web;
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
        // 플러그인 protocol v2 의 상호 배타 계약입니다.
        // preview=true dpi 0 · outputRawTIFF=false · IR/다중노출/노출시간 없음
        // preview=false dpi > 0 · outputRawTIFF=true
        // dpi 0 은 해상도가 아니라 **프리뷰 표식**이라 장치 해상도 목록에는 절대 없습니다.
        // 목록 대조를 프리뷰에도 걸면 모든 프리뷰가 CapabilityMismatch 로 떨어집니다.
        bool previewContract = request.Preview
            ? request.ResolutionDpi == 0 && !request.OutputRawTiff && !request.Infrared &&
              !request.MultiExposure && request.HardwareExposureTime is null
            : request.ResolutionDpi > 0 && request.OutputRawTiff;
        // scanArea 는 protocol v2 의 **필수** 필드입니다. macOS 의 `ScanOptions.scanArea` 도
        // 옵셔널이 아닙니다. 비우면 요청 JSON 이 파싱에서 떨어져 ProcessFailed 로 보입니다.
        if (!previewContract ||
            request.ScanArea is not { } area || !IsValidScanArea(area) ||
            !IsRequiredText(request.Device.Id) || !IsRequiredText(request.ColorMode) ||
            !Path.IsPathFullyQualified(request.DestinationVisiblePath) ||
            request.BitDepth is not (8 or 16) ||
            request.HardwareExposureTime is <= 0 ||
            request.BrightnessAdjustment is { } brightness && !double.IsFinite(brightness) ||
            request.ContrastAdjustment is { } contrast && !double.IsFinite(contrast) ||
            (request.ResolutionDpi != 0 &&
                !request.Capabilities.ResolutionsDpi.Contains(request.ResolutionDpi)) ||
            !request.Capabilities.BitDepths.Contains(request.BitDepth) ||
            !request.Capabilities.Modes.Contains(request.ColorMode, StringComparer.Ordinal) ||
            !request.Capabilities.OutputFormats.Contains("tiff", StringComparer.OrdinalIgnoreCase) ||
            request.Preview && !request.Capabilities.SupportsPreview ||
            request.Infrared && !request.Capabilities.SupportsInfrared ||
            request.MultiExposure && !request.Capabilities.SupportsMultiExposure)
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
