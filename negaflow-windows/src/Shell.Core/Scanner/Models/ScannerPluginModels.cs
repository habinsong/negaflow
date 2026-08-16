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
    string? CapabilityToken,
    double? MaxScanWidthMm = null,
    double? MaxScanHeightMm = null);

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
    int? HardwareExposureTime = null,
    ImageRotation Rotation = ImageRotation.Degrees0);

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
