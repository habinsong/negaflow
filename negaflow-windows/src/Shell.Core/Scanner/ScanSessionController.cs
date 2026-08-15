using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell;

/// <summary>
/// 스캔 절이 지금 무엇을 보여 줘야 하는지입니다. macOS <c>ScannerControlsSection</c> 의
/// 세 갈래(플러그인 없음 · 승인 필요 · 연결 대기)와 같은 구분입니다.
/// </summary>
public enum ScanSessionState
{
    /// <summary>설치된 플러그인이 없습니다. 스캔 절 자체를 내지 않습니다.</summary>
    NoPlugin,

    /// <summary>플러그인은 있으나 사용자가 아직 그 바이트를 승인하지 않았습니다.</summary>
    NeedsApproval,

    Searching,

    /// <summary>승인된 플러그인이 있으나 장치를 아직 찾지 못했습니다.</summary>
    NoDevice,

    Ready,

    Scanning,
}

/// <summary>
/// 플러그인 경계를 시험에서 갈아 끼우기 위한 자리입니다. 실제 구현은 별도 프로세스를 띄웁니다.
/// </summary>
public interface IScannerPluginGateway
{
    IReadOnlyList<InstalledScannerPlugin> Discover();

    Task<ScannerPluginDetectResult> DetectAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        CancellationToken cancellationToken);

    Task<ScannerPluginCapabilitiesResult> GetCapabilitiesAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        ScannerPluginDevice device,
        CancellationToken cancellationToken);

    Task<ScannerPluginLibraryScanResult> ScanAndPublishAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        ScannerPluginScanRequest request,
        LibraryHostService library,
        CancellationToken cancellationToken);

    /// <summary>
    /// 스캔만 하고 카탈로그에는 올리지 않습니다. 프리뷰가 이 길을 씁니다 — 프리뷰는 판을 보려고
    /// 찍는 것이지 사용자의 사진이 아니므로 라이브러리에 남기지 않습니다.
    /// </summary>
    Task<ScannerPluginScanResult> ScanAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        ScannerPluginScanRequest request,
        CancellationToken cancellationToken);
}

/// <summary>실제 플러그인 프로세스를 부르는 구현입니다.</summary>
public sealed class ScannerPluginGateway : IScannerPluginGateway
{
    private readonly string? pluginDirectory;

    public ScannerPluginGateway(string? pluginDirectory = null) =>
        this.pluginDirectory = pluginDirectory;

    public IReadOnlyList<InstalledScannerPlugin> Discover() =>
        ScannerPluginDiscovery.Discover(pluginDirectory);

    public Task<ScannerPluginDetectResult> DetectAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        CancellationToken cancellationToken) =>
        ScannerPluginClient.DetectAsync(plugin, approvedIdentity, cancellationToken);

    public Task<ScannerPluginCapabilitiesResult> GetCapabilitiesAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        ScannerPluginDevice device,
        CancellationToken cancellationToken) =>
        ScannerPluginClient.GetCapabilitiesAsync(
            plugin,
            approvedIdentity,
            device,
            cancellationToken);

    public Task<ScannerPluginLibraryScanResult> ScanAndPublishAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        ScannerPluginScanRequest request,
        LibraryHostService library,
        CancellationToken cancellationToken) =>
        ScannerPluginClient.ScanAndPublishAsync(
            plugin,
            approvedIdentity,
            request,
            library,
            cancellationToken: cancellationToken);

    public Task<ScannerPluginScanResult> ScanAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        ScannerPluginScanRequest request,
        CancellationToken cancellationToken) =>
        ScannerPluginClient.ScanAsync(plugin, approvedIdentity, request, cancellationToken);
}

/// <summary>사용자가 스캔 절에서 고른 값입니다.</summary>
public sealed record ScanOptions
{
    public FilmType FilmType { get; init; } = FilmType.ColorNegative;

    public int ResolutionDpi { get; init; }

    public int BitDepth { get; init; }

    public string ColorMode { get; init; } = ScanSessionController.ColorModeColor;

    public bool Infrared { get; init; }

    /// <summary>이번 롤이 들어갈 폴더 이름입니다. 비면 "무제 필름" 자리를 씁니다.</summary>
    public string FolderName { get; init; } = string.Empty;

    /// <summary>한 번 누를 때 이어서 뜰 프레임 수입니다. macOS 처럼 1...12 입니다.</summary>
    public int BatchCount { get; init; } = 1;

    /// <summary>평판에 올린 필름의 규격입니다. 프레임 찾기가 이 크기를 기준으로 셉니다.</summary>
    public FlatbedFrameFormat FrameFormat { get; init; } = FlatbedFrameFormat.FullFrame35mm;

    public FlatbedFrameDetectionMode FrameDetectionMode { get; init; } =
        FlatbedFrameDetectionMode.Automatic;
}

public sealed record ScanRunOutcome(
    int Requested,
    int Published,
    ScannerPluginLibraryScanStatus? LastStatus,
    ScannerPluginScanStatus? LastScanStatus)
{
    public bool IsSuccess => Published == Requested && Requested > 0;
}

/// <summary>
/// 라이브러리의 스캔 절 뒤에 있는 상태 기계입니다. XAML 을 참조하지 않으므로 UI 없이 시험합니다.
/// 플러그인 발견·장치 검출·capability 읽기·옵션 보정·스캔 실행과 카탈로그 게시까지 여기서 엮습니다.
/// </summary>
/// <remarks>
/// macOS 와 같은 규칙을 그대로 지킵니다. 본 스캔 해상도 목록은 600 dpi 미만을 감추고(그 아래는
/// 프리뷰가 쓰는 작업용 값입니다), 모드는 color 와 gray 만 내며, 심도를 보고하지 않는 장치는
/// 스캔 자체가 불가능합니다.
/// </remarks>
public sealed class ScanSessionController
{
    public const string ColorModeColor = "color";
    public const string ColorModeGray = "gray";

    /// <summary>본 스캔 목록에 올릴 최소 해상도입니다. macOS 와 같은 값입니다.</summary>
    public const int MinimumSelectableScanDpi = 600;

    public const int MaximumBatchCount = 12;

    private readonly IScannerPluginGateway gateway;
    private readonly SimulatedScannerGateway simulator;
    private readonly ScannerPluginTrustStore trust;
    private readonly IUiDispatcher dispatcher;

    public ScanSessionController(
        IScannerPluginGateway gateway,
        ScannerPluginTrustStore trust,
        IUiDispatcher dispatcher,
        SimulatedScannerGateway? simulator = null)
    {
        ArgumentNullException.ThrowIfNull(gateway);
        ArgumentNullException.ThrowIfNull(trust);
        ArgumentNullException.ThrowIfNull(dispatcher);
        this.simulator = simulator ?? new SimulatedScannerGateway();
        this.gateway = gateway;
        this.trust = trust;
        this.dispatcher = dispatcher;
        Refresh();
    }

    public event EventHandler? Changed;

    public IReadOnlyList<InstalledScannerPlugin> Plugins { get; private set; } = [];

    public IReadOnlyList<InstalledScannerPlugin> PluginsRequiringApproval { get; private set; } = [];

    public IReadOnlyList<ScannerPluginDevice> Devices { get; private set; } = [];

    public ScannerPluginDevice? SelectedDevice { get; private set; }

    public ScannerPluginCapabilities? Capabilities { get; private set; }

    public ScanOptions Options { get; private set; } = new();

    public bool IsDetecting { get; private set; }

    public bool IsScanning { get; private set; }

    /// <summary>마지막 실패의 이유입니다. 성공하면 지웁니다.</summary>
    public string? LastFailureName { get; private set; }

    /// <summary>
    /// 마지막 프리뷰 스캔이 남긴 파일입니다. 자동 프레임 찾기가 이 그림에서 프레임을 셉니다.
    /// 프리뷰는 카탈로그에 올리지 않으므로 여기서만 붙잡습니다.
    /// </summary>
    public string? LastPreviewPath { get; private set; }

    /// <summary>
    /// 하드웨어 없이 스캔 흐름을 돌립니다. macOS 의 스캐너 시뮬레이터와 같은 자리이며, 켜면
    /// 설치된 플러그인 대신 가상 장치를 씁니다.
    /// </summary>
    public bool SimulatorEnabled { get; private set; }

    public void SetSimulatorEnabled(bool enabled)
    {
        if (SimulatorEnabled == enabled)
        {
            return;
        }
        SimulatorEnabled = enabled;
        Devices = [];
        SelectedDevice = null;
        Capabilities = null;
        Refresh();
    }

    /// <summary>지금 쓰는 경계입니다. 시뮬레이터가 켜져 있으면 가상 백엔드입니다.</summary>
    private IScannerPluginGateway ActiveGateway => SimulatorEnabled ? simulator : gateway;

    /// <summary>
    /// 평판 흐름을 쓰는 장치인지. macOS 와 같은 조건입니다 — 위치를 지정한 스캔 영역과 프리뷰를
    /// 둘 다 낼 수 있어야 프레임을 판 위에 놓는 방식이 뜻을 가집니다.
    /// </summary>
    public bool UsesFlatbedRegionWorkflow =>
        Capabilities is { SupportsPositionedScanArea: true, SupportsPreview: true } &&
        Capabilities.MaxScanWidthMm is not null &&
        Capabilities.MaxScanHeightMm is not null;

    /// <summary>이 장치에 올릴 수 있는 프레임 규격입니다.</summary>
    public IReadOnlyList<FlatbedFrameFormat> AvailableFrameFormats =>
        Capabilities is null
            ? []
            : FilmFrameFormats.Available(
                Capabilities.MaxScanWidthMm,
                Capabilities.MaxScanHeightMm);

    /// <summary>판 위에 놓인 프레임들입니다. 평판 흐름이 아니면 비어 있습니다.</summary>
    public IReadOnlyList<FlatbedScanRegion> Regions { get; private set; } = [];

    public string? SelectedRegionId { get; private set; }

    /// <summary>복사해 둔 프레임입니다. 앱이 사는 동안만 남습니다.</summary>
    public FlatbedScanRegion? CopiedRegion { get; private set; }

    public void SelectRegion(string? regionId)
    {
        if (regionId is not null &&
            !Regions.Any(region => string.Equals(region.Id, regionId, StringComparison.Ordinal)))
        {
            return;
        }
        if (string.Equals(SelectedRegionId, regionId, StringComparison.Ordinal))
        {
            return;
        }
        SelectedRegionId = regionId;
        Changed?.Invoke(this, EventArgs.Empty);
    }

    /// <summary>
    /// 규격 크기의 프레임 하나를 판 왼쪽 위에 놓습니다. 이미 놓인 것이 있으면 그 아래로
    /// 내려 붙여, 새 프레임이 기존 것을 가리지 않게 합니다.
    /// </summary>
    public string? AddRegion()
    {
        if (!UsesFlatbedRegionWorkflow || Capabilities is not { } capabilities)
        {
            return null;
        }
        double width = FilmFrameFormats.StripWidthMm(Options.FrameFormat);
        double height = FilmFrameFormats.StripHeightMm(Options.FrameFormat);
        double maxWidth = capabilities.MaxScanWidthMm!.Value;
        double maxHeight = capabilities.MaxScanHeightMm!.Value;
        if (width > maxWidth || height > maxHeight)
        {
            (width, height) = (height, width);
        }
        double top = Regions.Count == 0
            ? 0.0
            : Regions.Max(region => region.OriginYmm + region.HeightMm);
        if (top + height > maxHeight)
        {
            return null;
        }
        FlatbedScanRegion created = FlatbedScanRegion.Create(0.0, top, width, height);
        Regions = [.. Regions, created];
        SelectedRegionId = created.Id;
        Changed?.Invoke(this, EventArgs.Empty);
        return created.Id;
    }

    public bool DeleteSelectedRegion()
    {
        if (SelectedRegionId is not { } regionId)
        {
            return false;
        }
        FlatbedScanRegion[] remaining = [.. Regions.Where(region =>
            !string.Equals(region.Id, regionId, StringComparison.Ordinal))];
        if (remaining.Length == Regions.Count)
        {
            return false;
        }
        Regions = remaining;
        SelectedRegionId = null;
        Changed?.Invoke(this, EventArgs.Empty);
        return true;
    }

    public bool CopySelectedRegion()
    {
        if (Regions.FirstOrDefault(region =>
                string.Equals(region.Id, SelectedRegionId, StringComparison.Ordinal))
            is not { } selected)
        {
            return false;
        }
        CopiedRegion = selected;
        Changed?.Invoke(this, EventArgs.Empty);
        return true;
    }

    /// <summary>복사한 프레임을 같은 크기로 아래에 붙입니다. 자리가 없으면 붙이지 않습니다.</summary>
    public bool PasteRegion()
    {
        if (CopiedRegion is not { } copied ||
            !UsesFlatbedRegionWorkflow ||
            Capabilities?.MaxScanHeightMm is not { } maxHeight)
        {
            return false;
        }
        double top = Regions.Count == 0
            ? 0.0
            : Regions.Max(region => region.OriginYmm + region.HeightMm);
        if (top + copied.HeightMm > maxHeight)
        {
            return false;
        }
        FlatbedScanRegion pasted = FlatbedScanRegion.Create(
            copied.OriginXmm,
            top,
            copied.WidthMm,
            copied.HeightMm);
        Regions = [.. Regions, pasted];
        SelectedRegionId = pasted.Id;
        Changed?.Invoke(this, EventArgs.Empty);
        return true;
    }

    /// <summary>
    /// 프리뷰에서 프레임을 찾아 목록을 다시 만듭니다. 자동일 때만 찾고, 수동이면 비운 뒤 규격
    /// 프레임 하나를 놓아 다시 시작할 자리를 만듭니다 — macOS 새로고침과 같은 규칙입니다.
    /// </summary>
    public FlatbedFrameGridStatus RefreshRegions(
        ReadOnlySpan<float> previewLuminance,
        uint previewWidth,
        uint previewHeight)
    {
        if (!UsesFlatbedRegionWorkflow || Capabilities is not { } capabilities)
        {
            return FlatbedFrameGridStatus.InvalidInput;
        }
        if (Options.FrameDetectionMode == FlatbedFrameDetectionMode.Manual)
        {
            Regions = [];
            SelectedRegionId = null;
            _ = AddRegion();
            return FlatbedFrameGridStatus.Ok;
        }

        // 자동으로 찾으려면 프리뷰 픽셀이 있어야 합니다. 없으면 찾은 척하지 않고 거부합니다.
        if (previewLuminance.IsEmpty || previewWidth == 0U || previewHeight == 0U ||
            previewLuminance.Length != (int)((ulong)previewWidth * previewHeight))
        {
            return FlatbedFrameGridStatus.InvalidInput;
        }

        double plateWidth = capabilities.MaxScanWidthMm!.Value;
        double plateHeight = capabilities.MaxScanHeightMm!.Value;
        FlatbedFrameGridResult detected = NativeFlatbedFrameGridDetector.Detect(
            previewLuminance,
            previewWidth,
            previewHeight,
            plateWidth,
            plateHeight,
            Options.FrameFormat);
        if (detected.Status != FlatbedFrameGridStatus.Ok)
        {
            return detected.Status;
        }
        // 검출은 정규화 좌표로 돌아옵니다. 유리판 크기를 곱해 밀리미터로 옮깁니다 — 프리뷰
        // 해상도가 바뀌어도 사용자가 본 자리가 그대로여야 합니다.
        Regions = [.. detected.Detections
            .Select(detection => FlatbedScanRegion.Create(
                detection.X * plateWidth,
                detection.Y * plateHeight,
                detection.Width * plateWidth,
                detection.Height * plateHeight))
            .Where(region => region.IsValid)];
        SelectedRegionId = Regions.Count > 0 ? Regions[0].Id : null;
        Changed?.Invoke(this, EventArgs.Empty);
        return FlatbedFrameGridStatus.Ok;
    }

    public ScanSessionState State
    {
        get
        {
            if (Plugins.Count == 0)
            {
                return ScanSessionState.NoPlugin;
            }
            if (IsScanning)
            {
                return ScanSessionState.Scanning;
            }
            if (PluginsRequiringApproval.Count == Plugins.Count)
            {
                return ScanSessionState.NeedsApproval;
            }
            if (IsDetecting)
            {
                return ScanSessionState.Searching;
            }
            return SelectedDevice is null ? ScanSessionState.NoDevice : ScanSessionState.Ready;
        }
    }

    /// <summary>본 스캔에서 고를 수 있는 해상도입니다.</summary>
    public IReadOnlyList<int> Resolutions
    {
        get
        {
            IReadOnlyList<int> supported = Capabilities?.ResolutionsDpi ?? [];
            int[] positive = [.. supported.Where(dpi => dpi > 0).Distinct().Order()];
            int[] usable = [.. positive.Where(dpi => dpi >= MinimumSelectableScanDpi)];
            if (usable.Length == 0)
            {
                return positive;
            }
            // 걸러 낸 목록에 지금 고른 값이 없으면 메뉴가 빈칸으로 보입니다.
            return usable.Contains(Options.ResolutionDpi) || Options.ResolutionDpi == 0
                ? usable
                : [.. usable.Append(Options.ResolutionDpi).Order()];
        }
    }

    public IReadOnlyList<int> BitDepths =>
        [.. (Capabilities?.BitDepths ?? []).Where(depth => depth > 0).Distinct().Order()];

    public IReadOnlyList<string> ColorModes =>
        [.. (Capabilities?.Modes ?? []).Where(mode =>
            string.Equals(mode, ColorModeColor, StringComparison.Ordinal) ||
            string.Equals(mode, ColorModeGray, StringComparison.Ordinal))];

    /// <summary>심도·모드·해상도를 하나도 보고하지 않는 장치로는 스캔할 수 없습니다.</summary>
    public bool HasUsableCapabilities =>
        Capabilities is not null &&
        Capabilities.ResolutionsDpi.Any(dpi => dpi > 0) &&
        ColorModes.Count > 0 &&
        BitDepths.Count > 0;

    public bool CanScan =>
        State is ScanSessionState.Ready && HasUsableCapabilities;

    public bool CanPreview => CanScan && Capabilities?.SupportsPreview == true;

    /// <summary>
    /// macOS 처럼 적외선은 장치가 실제로 IR 을 내고, 필름이 자동 보정을 허용할 때만 켤 수 있습니다.
    /// </summary>
    public bool CanUseInfrared =>
        Capabilities?.SupportsInfrared == true && AllowsInfrared(Options.FilmType);

    public static bool AllowsInfrared(FilmType filmType) =>
        filmType is FilmType.ColorNegative or FilmType.ColorPositive;

    /// <summary>플러그인 목록과 승인 상태를 다시 읽습니다. 장치는 건드리지 않습니다.</summary>
    public void Refresh()
    {
        Plugins = ActiveGateway.Discover();
        // 시뮬레이터는 이 앱의 코드입니다. 승인은 우리가 고르지 않은 제3자 바이트를 실행하기
        // 전에 묻는 것이므로 물을 것이 없습니다.
        PluginsRequiringApproval = SimulatorEnabled ? [] : trust.PluginsRequiringApproval(Plugins);
        if (Plugins.Count == 0)
        {
            Devices = [];
            SelectedDevice = null;
            Capabilities = null;
        }
        Changed?.Invoke(this, EventArgs.Empty);
    }

    private ScannerPluginTrustIdentity? ApprovedIdentityFor(InstalledScannerPlugin plugin) =>
        SimulatorEnabled ? plugin.TrustIdentity : trust.ApprovedIdentityFor(plugin);

    public void Approve(InstalledScannerPlugin plugin)
    {
        trust.Approve(plugin);
        Refresh();
    }

    /// <summary>
    /// 승인된 플러그인 전부에 장치를 물어 목록을 다시 채웁니다. 이전에 고른 장치가 아직 있으면
    /// 그것을 지킵니다 — 목록을 새로 고쳤다고 선택이 튀면 사용자가 다시 골라야 합니다.
    /// </summary>
    public async Task RefreshDevicesAsync(CancellationToken cancellationToken = default)
    {
        if (IsDetecting || IsScanning)
        {
            return;
        }
        IsDetecting = true;
        LastFailureName = null;
        Changed?.Invoke(this, EventArgs.Empty);
        var found = new List<ScannerPluginDevice>();
        try
        {
            foreach (InstalledScannerPlugin plugin in Plugins)
            {
                if (ApprovedIdentityFor(plugin) is not { } identity)
                {
                    continue;
                }
                ScannerPluginDetectResult result =
                    await ActiveGateway.DetectAsync(plugin, identity, cancellationToken)
                        .ConfigureAwait(false);
                if (result.IsSuccess)
                {
                    found.AddRange(result.Devices);
                }
                else
                {
                    LastFailureName ??= result.IsMalformedResponse
                        ? "malformed_detect_response"
                        : result.Process.Status.ToString();
                }
            }
        }
        finally
        {
            IsDetecting = false;
        }

        Devices = found;
        string? keep = SelectedDevice?.Id;
        SelectedDevice = found.FirstOrDefault(device =>
            string.Equals(device.Id, keep, StringComparison.Ordinal)) ?? found.FirstOrDefault();
        Changed?.Invoke(this, EventArgs.Empty);
        if (SelectedDevice is not null)
        {
            await LoadCapabilitiesAsync(cancellationToken).ConfigureAwait(false);
        }
        else
        {
            Capabilities = null;
            Changed?.Invoke(this, EventArgs.Empty);
        }
    }

    public async Task SelectDeviceAsync(
        string deviceId,
        CancellationToken cancellationToken = default)
    {
        if (Devices.FirstOrDefault(device =>
                string.Equals(device.Id, deviceId, StringComparison.Ordinal)) is not { } chosen ||
            ReferenceEquals(chosen, SelectedDevice))
        {
            return;
        }
        SelectedDevice = chosen;
        Changed?.Invoke(this, EventArgs.Empty);
        await LoadCapabilitiesAsync(cancellationToken).ConfigureAwait(false);
    }

    /// <summary>
    /// 고른 장치의 capability 를 읽고 옵션을 그 안으로 접습니다. 장치가 낼 수 없는 값을 들고
    /// 있으면 스캔이 CapabilityMismatch 로 거부되므로, 목록이 바뀌는 순간에 맞춥니다.
    /// </summary>
    public async Task LoadCapabilitiesAsync(CancellationToken cancellationToken = default)
    {
        if (SelectedDevice is not { } device)
        {
            return;
        }
        foreach (InstalledScannerPlugin plugin in Plugins)
        {
            if (ApprovedIdentityFor(plugin) is not { } identity)
            {
                continue;
            }
            ScannerPluginCapabilitiesResult result = await ActiveGateway
                .GetCapabilitiesAsync(plugin, identity, device, cancellationToken)
                .ConfigureAwait(false);
            if (!result.IsSuccess)
            {
                continue;
            }
            Capabilities = result.Capabilities;
            Options = ClampToCapabilities(Options);
            Changed?.Invoke(this, EventArgs.Empty);
            return;
        }
        Capabilities = null;
        LastFailureName ??= "capabilities_unavailable";
        Changed?.Invoke(this, EventArgs.Empty);
    }

    public void UpdateOptions(Func<ScanOptions, ScanOptions> update)
    {
        ArgumentNullException.ThrowIfNull(update);
        ScanOptions next = ClampToCapabilities(update(Options));
        if (next == Options)
        {
            return;
        }
        Options = next;
        Changed?.Invoke(this, EventArgs.Empty);
    }

    /// <summary>
    /// 고른 값을 장치가 낼 수 있는 값 안으로 접습니다. 목록이 비면 0 으로 두어 UI 가 왜 잠겼는지
    /// 보여 줄 수 있게 합니다 — 아무 값이나 지어내지 않습니다.
    /// </summary>
    public ScanOptions ClampToCapabilities(ScanOptions options)
    {
        ArgumentNullException.ThrowIfNull(options);
        IReadOnlyList<int> resolutions = Resolutions;
        IReadOnlyList<int> depths = BitDepths;
        IReadOnlyList<string> modes = ColorModes;
        int resolution = resolutions.Contains(options.ResolutionDpi)
            ? options.ResolutionDpi
            : resolutions.Count > 0 ? resolutions[^1] : 0;
        int depth = depths.Contains(options.BitDepth)
            ? options.BitDepth
            : depths.Count > 0 ? depths[^1] : 0;
        string mode = modes.Contains(options.ColorMode)
            ? options.ColorMode
            : modes.Count > 0 ? modes[0] : ColorModeColor;
        bool infrared = options.Infrared &&
            Capabilities?.SupportsInfrared == true &&
            AllowsInfrared(options.FilmType);
        IReadOnlyList<FlatbedFrameFormat> formats = AvailableFrameFormats;
        return options with
        {
            FrameFormat = formats.Count == 0 || formats.Contains(options.FrameFormat)
                ? options.FrameFormat
                : formats[0],
            ResolutionDpi = resolution,
            BitDepth = depth,
            ColorMode = mode,
            Infrared = infrared,
            BatchCount = Math.Clamp(options.BatchCount, 1, MaximumBatchCount),
            FolderName = ExportNamingTemplate.SanitizeComponent(options.FolderName),
        };
    }

    /// <summary>
    /// 지금 옵션으로 보낼 요청입니다. 스캔을 돌리기 전에 무엇이 나갈지 시험할 수 있도록 따로
    /// 냅니다 — 요청을 만드는 규칙이 스캔 실행 안에 숨으면 확인할 방법이 없습니다.
    /// </summary>
    /// <summary>평판 흐름이면 그 번째 프레임의 자리입니다. 아니면 null 입니다.</summary>
    private FlatbedScanRegion? RegionAt(int index) =>
        UsesFlatbedRegionWorkflow && index >= 0 && index < Regions.Count ? Regions[index] : null;

    public ScannerPluginScanRequest? BuildRequest(
        bool preview,
        string destinationVisiblePath,
        int regionIndex = -1)
    {
        if (SelectedDevice is not { } device || Capabilities is not { } capabilities)
        {
            return null;
        }
        return new ScannerPluginScanRequest(
            device,
            capabilities,
            DevelopProcesses.From(Options.FilmType, isDigitalSource: false),
            // 프로토콜에서 프리뷰는 해상도 0 입니다 — 어떤 해상도를 쓸지는 플러그인이 정합니다.
            preview ? 0 : Options.ResolutionDpi,
            Options.BitDepth,
            Options.ColorMode,
            preview,
            // 프리뷰에는 IR 을 걸지 않습니다. macOS 도 프리뷰에서 IR 토글을 잠급니다.
            !preview && Options.Infrared,
            MultiExposure: false,
            // 프리뷰는 판 전체를 훑습니다 — 프레임을 찾으려면 판이 다 보여야 합니다.
            ScanArea: preview ? null : RegionAt(regionIndex)?.ToScanArea(),
            OutputRawTiff: false,
            destinationVisiblePath,
            // 프리뷰는 프레임을 찾기 위한 것이므로 돌리지 않습니다 — 돌리면 찾은 좌표가
            // 실제 판의 좌표와 어긋납니다.
            Rotation: preview ? Catalog.ImageRotation.Degrees0 : DefaultRotation);
    }

    /// <summary>
    /// 설정에서 정한 기본 스캔 회전입니다. 셸이 꽂아 줍니다 — Shell.Core 는 설정 파일을
    /// 읽지 않습니다.
    /// </summary>
    public Catalog.ImageRotation DefaultRotation { get; set; } = Catalog.ImageRotation.Degrees0;

    /// <summary>
    /// 스캔해서 카탈로그에 게시합니다. 배치는 macOS 처럼 한 장씩 이어서 돌며, 한 장이 실패하면
    /// 거기서 멈춥니다 — 반쯤 실패한 롤을 조용히 이어 붙이지 않습니다.
    /// </summary>
    public async Task<ScanRunOutcome> RunAsync(
        LibraryHostService library,
        Func<int, string> destinationForIndex,
        bool preview,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(library);
        ArgumentNullException.ThrowIfNull(destinationForIndex);
        if (!CanScan || (preview && !CanPreview))
        {
            return new ScanRunOutcome(0, 0, null, null);
        }

        // macOS 처럼 평판에서는 판 위에 놓인 프레임 수가 곧 스캔 수입니다.
        int requested = preview
            ? 1
            : UsesFlatbedRegionWorkflow ? Regions.Count : Options.BatchCount;
        IsScanning = true;
        LastFailureName = null;
        Changed?.Invoke(this, EventArgs.Empty);
        int published = 0;
        ScannerPluginLibraryScanStatus? lastStatus = null;
        ScannerPluginScanStatus? lastScanStatus = null;
        try
        {
            for (int index = 0; index < requested; ++index)
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (BuildRequest(preview, destinationForIndex(index), index) is not { } request)
                {
                    break;
                }
                InstalledScannerPlugin? plugin = Plugins.FirstOrDefault(candidate =>
                    ApprovedIdentityFor(candidate) is not null);
                if (plugin is null || ApprovedIdentityFor(plugin) is not { } identity)
                {
                    break;
                }
                if (preview)
                {
                    // 프리뷰는 판을 보려고 찍는 것이지 사용자의 사진이 아닙니다. 카탈로그에
                    // 올리지 않고 파일만 붙잡아 자동 프레임 찾기에 넘깁니다.
                    ScannerPluginScanResult scanned = await ActiveGateway
                        .ScanAsync(plugin, identity, request, cancellationToken)
                        .ConfigureAwait(false);
                    lastScanStatus = scanned.Status;
                    if (!scanned.IsSuccess)
                    {
                        LastFailureName = scanned.Status.ToString();
                        break;
                    }
                    LastPreviewPath = scanned.ArtifactCommit?.Artifacts?.VisiblePath;
                    ++published;
                    continue;
                }

                ScannerPluginLibraryScanResult result = await ActiveGateway
                    .ScanAndPublishAsync(plugin, identity, request, library, cancellationToken)
                    .ConfigureAwait(false);
                lastStatus = result.Status;
                lastScanStatus = result.Scan.Status;
                if (!result.IsSuccess)
                {
                    LastFailureName = result.Scan.Status == ScannerPluginScanStatus.Completed
                        ? result.Status.ToString()
                        : result.Scan.Status.ToString();
                    break;
                }
                ++published;
            }
        }
        finally
        {
            IsScanning = false;
            _ = dispatcher.TryEnqueue(() => Changed?.Invoke(this, EventArgs.Empty));
        }
        return new ScanRunOutcome(requested, published, lastStatus, lastScanStatus);
    }
}
