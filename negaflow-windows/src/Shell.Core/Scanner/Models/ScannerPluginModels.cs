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

public sealed record ScannerPluginScanArea(
    [property: JsonPropertyName("originXMM")] double OriginXmm,
    [property: JsonPropertyName("originYMM")] double OriginYmm,
    [property: JsonPropertyName("widthMM")] double WidthMm,
    [property: JsonPropertyName("heightMM")] double HeightMm);

/// <summary>
/// macOS <c>ScannerOptionRange</c> — 장치가 낼 수 있는 수치의 범위입니다. <c>Step</c> 이 있으면
/// 그 격자 위의 값만 실제로 적용되므로, 보내기 전에 격자에 맞춥니다.
/// </summary>
public sealed record ScannerOptionRange(double Minimum, double Maximum, double? Step = null)
{
    /// <summary>macOS <c>clamped(_:)</c>.</summary>
    public double Clamped(double value) => Math.Min(Math.Max(value, Minimum), Maximum);

    /// <summary>
    /// macOS <c>quantized(_:upperBound:rule:)</c>. <paramref name="roundUp"/> 는 Swift 의
    /// <c>.up</c>(<see langword="true"/>) 과 <c>.down</c>(<see langword="false"/>) 입니다.
    /// </summary>
    public double Quantized(double value, double? upperBound = null, bool? roundUp = null)
    {
        double upper = Math.Max(Minimum, Math.Min(Maximum, upperBound ?? Maximum));
        double clamped = Math.Min(Math.Max(value, Minimum), upper);
        if (Step is not { } step || step <= 0.0)
        {
            return clamped;
        }
        double steps = (clamped - Minimum) / step;
        double rule = roundUp switch
        {
            true => Math.Ceiling(steps),
            false => Math.Floor(steps),
            // Swift 의 기본값 `.toNearestOrAwayFromZero`.
            null => Math.Round(steps, MidpointRounding.AwayFromZero),
        };
        double rounded = Minimum + (rule * step);
        return rounded <= upper
            ? Math.Max(rounded, Minimum)
            : Math.Max(Minimum, Minimum + (Math.Floor((upper - Minimum) / step) * step));
    }
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
    string? CapabilityToken,
    double? MaxScanWidthMm = null,
    double? MaxScanHeightMm = null,
    ScannerPluginScanArea? MinScanArea = null,
    ScannerPluginScanArea? MaxScanArea = null,
    string? ScanAreaUnit = null,
    ScannerOptionRange? BrightnessRange = null,
    ScannerOptionRange? ContrastRange = null,
    ScannerOptionRange? HardwareExposureRange = null,
    ScannerOptionRange? ScanOriginXRange = null,
    ScannerOptionRange? ScanOriginYRange = null,
    ScannerOptionRange? ScanWidthRange = null,
    ScannerOptionRange? ScanHeightRange = null)
{
    /// <summary>
    /// macOS <c>ScannerCapabilities.physicalScanAreaBounds</c> 그대로입니다. 하나라도 조건을
    /// 어기면 <see langword="null"/> 이고, 그때 macOS 는 프레임 규격·영역 워크플로를 감춥니다.
    /// </summary>
    public (ScannerPluginScanArea Minimum, ScannerPluginScanArea Maximum)? PhysicalScanAreaBounds
    {
        get
        {
            if (!SupportsScanArea ||
                string.Equals(ScanAreaUnit, "pixel", StringComparison.Ordinal) ||
                MinScanArea is not { } minimum || MaxScanArea is not { } maximum ||
                !IsFinite(minimum) || !IsFinite(maximum) ||
                minimum.OriginXmm < 0.0 || minimum.OriginYmm < 0.0 ||
                maximum.OriginXmm < 0.0 || maximum.OriginYmm < 0.0 ||
                minimum.WidthMm <= 0.0 || minimum.HeightMm <= 0.0 ||
                maximum.WidthMm < minimum.WidthMm || maximum.HeightMm < minimum.HeightMm)
            {
                return null;
            }
            return (minimum, maximum);
        }
    }

    /// <summary>macOS <c>clampedPhysicalScanArea(_:)</c> 그대로입니다.</summary>
    public ScannerPluginScanArea? ClampedPhysicalScanArea(ScannerPluginScanArea requested)
    {
        ArgumentNullException.ThrowIfNull(requested);
        if (PhysicalScanAreaBounds is not { } bounds || !IsFinite(requested))
        {
            return null;
        }
        (ScannerPluginScanArea minimum, ScannerPluginScanArea maximum) = bounds;
        double rawWidth = Math.Min(Math.Max(requested.WidthMm, minimum.WidthMm), maximum.WidthMm);
        double rawHeight = Math.Min(Math.Max(requested.HeightMm, minimum.HeightMm), maximum.HeightMm);
        double rawOriginX = Math.Min(
            Math.Max(requested.OriginXmm, maximum.OriginXmm),
            maximum.OriginXmm + maximum.WidthMm - rawWidth);
        double rawOriginY = Math.Min(
            Math.Max(requested.OriginYmm, maximum.OriginYmm),
            maximum.OriginYmm + maximum.HeightMm - rawHeight);
        double originX = ScanOriginXRange?.Quantized(rawOriginX, roundUp: false) ?? rawOriginX;
        double originY = ScanOriginYRange?.Quantized(rawOriginY, roundUp: false) ?? rawOriginY;
        double requiredWidth = rawOriginX + rawWidth - originX;
        double requiredHeight = rawOriginY + rawHeight - originY;
        double width = ScanWidthRange?.Quantized(
                requiredWidth,
                maximum.OriginXmm + maximum.WidthMm - originX,
                roundUp: true)
            ?? Math.Min(Math.Max(requested.WidthMm, minimum.WidthMm), maximum.WidthMm);
        double height = ScanHeightRange?.Quantized(
                requiredHeight,
                maximum.OriginYmm + maximum.HeightMm - originY,
                roundUp: true)
            ?? Math.Min(Math.Max(requested.HeightMm, minimum.HeightMm), maximum.HeightMm);
        return new ScannerPluginScanArea(originX, originY, width, height);
    }

    private static bool IsFinite(ScannerPluginScanArea area) =>
        double.IsFinite(area.OriginXmm) && double.IsFinite(area.OriginYmm) &&
        double.IsFinite(area.WidthMm) && double.IsFinite(area.HeightMm);
}

public sealed record ScannerPluginCapabilitiesResult(
    ScannerPluginProcessResult Process,
    ScannerPluginCapabilities? Capabilities,
    bool IsMalformedResponse)
{
    public bool IsSuccess => Process.IsSuccess && !IsMalformedResponse && Capabilities is not null;
}

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
    int? HardwareExposureTime = null,
    ImageRotation Rotation = ImageRotation.Degrees0);

public enum ScannerPluginScanStatus
{
    Completed,
    InvalidRequest,
    CapabilityMismatch,
    StagingCreateFailed,
    /// <summary>
    /// 플러그인 프로세스가 실패했는데 <b>어느 갈래인지 모를 때만</b> 씁니다.
    /// </summary>
    /// <remarks>
    /// 앞 판은 실행 실패·신뢰 거부·시간 초과·<b>사용자 취소</b>·출력 상한 초과·비정상 종료를
    /// 전부 이 한 이름으로 접었습니다. 그래서 스캔을 사용자가 멈춰도 화면에 "ProcessFailed"
    /// 가 떴고, 사용자가 그 글자로 할 수 있는 일이 없었습니다. 아래 갈래들이 그 자리를
    /// 대신하며, 이 값은 새로 생긴 프로세스 상태를 못 옮겼을 때의 마지막 자리입니다.
    /// </remarks>
    ProcessFailed,
    /// <summary>플러그인을 띄우지 못했습니다(경로·권한·실행 파일).</summary>
    ProcessLaunchFailed,
    /// <summary>플러그인 서명·해시가 승인된 것과 다릅니다. 실행하지 않았습니다.</summary>
    PluginUntrusted,
    /// <summary>플러그인이 제한 시간 안에 끝내지 못했습니다.</summary>
    ProcessTimedOut,
    /// <summary><b>사용자가 멈췄습니다.</b> 실패가 아닙니다.</summary>
    Cancelled,
    /// <summary>플러그인 출력이 상한을 넘었습니다.</summary>
    ProcessOutputLimitExceeded,
    /// <summary>플러그인이 0 이 아닌 코드로 끝났습니다. 코드는 기록에 남습니다.</summary>
    ProcessExitedWithError,
    ProtocolViolation,
    PluginError,
    ResultMismatch,
    ArtifactCommitFailed,
}

public sealed record ScannerPluginScanResult(
    ScannerPluginScanStatus Status,
    ScannerPluginProcessResult? Process,
    ScannerPluginStreamStatus? ProtocolStatus,
    ScannerArtifactCommitResult? ArtifactCommit,
    ScannerPluginScanArea? AppliedScanArea = null)
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
