using System.Globalization;
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
        out string? stagingDirectory) =>
        TryBuild(request, out wire, out stagingDirectory, out _);

    /// <param name="refusal">
    /// 요청을 만들지 못한 <b>이유</b>입니다. 만들었으면 <c>null</c> 입니다. 앞 판은 이유 없이
    /// <c>false</c> 만 돌려줘서, 실패가 `CapabilityMismatch` 한 단어로만 남았습니다 — 열몇
    /// 가지 조건 중 무엇이 걸렸는지 기록으로 좁힐 수 없었습니다(2026-08-31).
    /// </param>
    internal static bool TryBuild(
        ScannerPluginScanRequest request,
        out ScannerPluginClient.ScanWire? wire,
        out string? stagingDirectory,
        out string? refusal)
    {
        ArgumentNullException.ThrowIfNull(request);
        wire = null;
        stagingDirectory = null;
        refusal = null;
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
        // **한 줄로 묶지 않습니다.** 묶으면 어느 조건이 걸렸는지 남길 자리가 없습니다.
        refusal =
            !previewContract
                ? $"preview contract: preview={request.Preview} dpi={request.ResolutionDpi} " +
                  $"rawTiff={request.OutputRawTiff} ir={request.Infrared} " +
                  $"multiExposure={request.MultiExposure} " +
                  $"exposure={request.HardwareExposureTime?.ToString(CultureInfo.InvariantCulture) ?? "none"}"
            : request.ScanArea is not { } checkedArea ? "scanArea is required by protocol v2 but absent"
            : !IsValidScanArea(checkedArea) ? $"scanArea is not usable: {DescribeArea(checkedArea)}"
            : !IsRequiredText(request.Device.Id) ? "deviceID is empty or unusable"
            : !IsRequiredText(request.ColorMode) ? "colorMode is empty or unusable"
            : !Path.IsPathFullyQualified(request.DestinationVisiblePath)
                ? $"destination is not a full path: {request.DestinationVisiblePath}"
            : request.BitDepth is not (8 or 16) ? $"bitDepth {request.BitDepth} is neither 8 nor 16"
            : request.HardwareExposureTime is <= 0
                ? $"hardwareExposureTime {request.HardwareExposureTime} is not positive"
            : request.BrightnessAdjustment is { } brightness && !double.IsFinite(brightness)
                ? $"brightnessAdjustment {brightness} is not finite"
            : request.ContrastAdjustment is { } contrast && !double.IsFinite(contrast)
                ? $"contrastAdjustment {contrast} is not finite"
            : request.ResolutionDpi != 0 &&
              !request.Capabilities.ResolutionsDpi.Contains(request.ResolutionDpi)
                ? $"the device does not offer {request.ResolutionDpi} dpi " +
                  $"(offers {string.Join(",", request.Capabilities.ResolutionsDpi)})"
            : !request.Capabilities.BitDepths.Contains(request.BitDepth)
                ? $"the device does not offer {request.BitDepth} bit " +
                  $"(offers {string.Join(",", request.Capabilities.BitDepths)})"
            : !request.Capabilities.Modes.Contains(request.ColorMode, StringComparer.Ordinal)
                ? $"the device does not offer colorMode '{request.ColorMode}' " +
                  $"(offers {string.Join(",", request.Capabilities.Modes)})"
            : !request.Capabilities.OutputFormats.Contains("tiff", StringComparer.OrdinalIgnoreCase)
                ? $"the device does not output tiff " +
                  $"(offers {string.Join(",", request.Capabilities.OutputFormats)})"
            : request.Preview && !request.Capabilities.SupportsPreview
                ? "a preview was asked for but the device does not support preview"
            : request.Infrared && !request.Capabilities.SupportsInfrared
                ? "infrared was asked for but the device does not support it"
            : request.MultiExposure && !request.Capabilities.SupportsMultiExposure
                ? "multi exposure was asked for but the device does not support it"
            : null;
        if (refusal is not null)
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
            refusal =
                $"destination path is unusable: {request.DestinationVisiblePath} " +
                $"({error.GetType().Name} {error.Message})";
            return false;
        }
        string? destinationDirectory = Path.GetDirectoryName(destination);
        if (destinationDirectory is null)
        {
            refusal = $"destination has no parent folder: {destination}";
            return false;
        }
        if (!Directory.Exists(destinationDirectory))
        {
            refusal = $"destination folder does not exist: {destinationDirectory}";
            return false;
        }
        if (File.Exists(destination))
        {
            refusal = $"destination file already exists: {destination}";
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

    /// <param name="mismatch">
    /// 어긋난 자리를 **이름과 두 값으로** 적어 돌려줍니다. 맞으면 <c>null</c> 입니다.
    /// 앞 판은 이 정보가 없어 실패가 `ResultMismatch` 한 단어로만 남았고, 열몇 가지 검사 중
    /// 무엇이 틀렸는지 알 수 없었습니다 — 필름 종류만 바꾸면 스캔이 안 된다는 보고를 그
    /// 기록으로는 한 발짝도 좁히지 못했습니다(2026-08-31).
    /// </param>
    internal static bool TryValidateV2Result(
        JsonElement payload,
        ScannerPluginClient.ScanWire wire,
        out string? infraredPath,
        out ScannerArtifactRequirements? artifactRequirements,
        out ScannerPluginScanArea? appliedScanArea,
        out string? mismatch)
    {
        infraredPath = null;
        artifactRequirements = null;
        appliedScanArea = null;
        mismatch = null;
        try
        {
            if (!HasRequiredAppliedOptionNames(payload))
            {
                mismatch = "appliedOptions is missing one of the required names";
                return false;
            }
            ScanResultResponse? result = payload.Deserialize<ScanResultResponse>(Json);
            if (result is null)
            {
                mismatch = "the result payload did not parse";
                return false;
            }
            if (!string.Equals(result.Path, wire.OutputPath, StringComparison.OrdinalIgnoreCase))
            {
                mismatch = $"path: applied={result.Path ?? "null"} requested={wire.OutputPath}";
                return false;
            }
            if (Differs("resolutionDPI", result.ResolutionDpi, wire.ResolutionDpi) is { } dpi)
            {
                mismatch = dpi;
                return false;
            }
            if (Differs("bitDepth", result.BitDepth, wire.BitDepth) is { } depth)
            {
                mismatch = depth;
                return false;
            }
            if (Differs("hasInfrared", result.HasInfrared, wire.Infrared) is { } ir)
            {
                mismatch = ir;
                return false;
            }
            if (AppliedOptionsMismatch(result.AppliedOptions, wire) is { } applied)
            {
                mismatch = applied;
                return false;
            }
            if (result.Width is not int width || width <= 0 ||
                result.Height is not int height || height <= 0)
            {
                mismatch =
                    $"size: width={result.Width?.ToString() ?? "null"} height={result.Height?.ToString() ?? "null"}";
                return false;
            }

            artifactRequirements = new ScannerArtifactRequirements(
                width,
                height,
                wire.BitDepth,
                wire.ColorMode);
            appliedScanArea = result.AppliedOptions!.ScanArea;
            if (!wire.Infrared)
            {
                if (result.IrPath is not null)
                {
                    mismatch = $"irPath: infrared was not requested but got {result.IrPath}";
                    return false;
                }
                return true;
            }
            if (string.IsNullOrWhiteSpace(result.IrPath) ||
                !IsContainedPath(Path.GetDirectoryName(wire.OutputPath)!, result.IrPath))
            {
                mismatch = $"irPath: {result.IrPath ?? "null"} is missing or outside the staging folder";
                return false;
            }
            infraredPath = Path.GetFullPath(result.IrPath);
            return true;
        }
        catch (JsonException error)
        {
            mismatch = $"the result payload is not valid JSON: {error.Message}";
            return false;
        }
    }

    /// <summary>
    /// 두 값이 다르면 <b>이름과 두 값</b>을 적어 돌려줍니다. 같으면 <c>null</c> 입니다.
    /// </summary>
    /// <remarks>
    /// `object` 로 받아 `Equals` 로 봅니다 - `int` 와 `int?` 처럼 짝이 맞지 않는 자리가 많아
    /// 제네릭으로 묶으면 호출부마다 타입을 적어야 합니다. 박싱은 스캔 한 장에 열몇 번이라
    /// 잴 수 있는 비용이 아닙니다.
    /// </remarks>
    private static string? Differs(string name, object? applied, object? requested) =>
        Equals(applied, requested)
            ? null
            : $"{name}: applied={applied ?? "null"} requested={requested ?? "null"}";

    /// <summary>
    /// 플러그인이 적용했다고 보고한 옵션이 우리가 청한 것과 어긋나면 <b>그 필드</b>를 적어
    /// 돌려줍니다. 다 맞으면 <c>null</c> 입니다.
    /// </summary>
    private static string? AppliedOptionsMismatch(
        AppliedScanOptionsResponse? applied,
        ScannerPluginClient.ScanWire requested)
    {
        if (applied is null)
        {
            return "appliedOptions is absent";
        }
        return Differs("deviceID", applied.DeviceId, requested.DeviceId)
            ?? Differs("resolutionDPI", applied.ResolutionDpi, requested.ResolutionDpi)
            ?? Differs("bitDepth", applied.BitDepth, requested.BitDepth)
            ?? Differs("colorMode", applied.ColorMode, requested.ColorMode)
            ?? Differs("filmType", applied.FilmType, requested.FilmType)
            ?? Differs("infrared", applied.Infrared, requested.Infrared)
            ?? Differs("multiExposure", applied.MultiExposure, requested.MultiExposure)
            ?? Differs(
                "hardwareExposureTime",
                applied.HardwareExposureTime,
                requested.HardwareExposureTime)
            ?? Differs(
                "brightnessAdjustment",
                applied.BrightnessAdjustment,
                requested.BrightnessAdjustment)
            ?? Differs("contrastAdjustment", applied.ContrastAdjustment, requested.ContrastAdjustment)
            ?? Differs("outputRawTIFF", applied.OutputRawTiff, requested.OutputRawTiff)
            ?? (ScanAreasMatch(applied.ScanArea, requested.ScanArea)
                ? null
                : $"scanArea: applied={DescribeArea(applied.ScanArea)} " +
                  $"requested={DescribeArea(requested.ScanArea)}");
    }

    private static string DescribeArea(ScannerPluginScanArea? area) => area is null
        ? "null"
        : string.Create(
            CultureInfo.InvariantCulture,
            $"{area.OriginXmm},{area.OriginYmm} {area.WidthMm}x{area.HeightMm}mm");

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
