using Negaflow.Catalog;
using Negaflow.Interop;

namespace Negaflow.Shell;

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
    public const string ColorModeColor = ScanOptionPolicy.ColorModeColor;
    public const string ColorModeGray = ScanOptionPolicy.ColorModeGray;

    /// <summary>본 스캔 목록에 올릴 최소 해상도입니다. macOS 와 같은 값입니다.</summary>
    public const int MinimumSelectableScanDpi = ScanOptionPolicy.MinimumSelectableScanDpi;

    public const int MaximumBatchCount = ScanOptionPolicy.MaximumBatchCount;

    private readonly IScannerPluginGateway gateway;
    private readonly FlatbedRegionEditor regionEditor;
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
        regionEditor = new FlatbedRegionEditor(
            () => Changed?.Invoke(this, EventArgs.Empty));
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

    private IScannerPluginGateway ActiveGateway => SimulatorEnabled ? simulator : gateway;

    public bool UsesFlatbedRegionWorkflow =>
        ScanOptionPolicy.UsesFlatbedRegionWorkflow(Capabilities);

    public IReadOnlyList<FlatbedFrameFormat> AvailableFrameFormats =>
        ScanOptionPolicy.AvailableFrameFormats(Capabilities);

    public IReadOnlyList<FlatbedScanRegion> Regions => regionEditor.Regions;

    public string? SelectedRegionId => regionEditor.SelectedRegionId;

    public FlatbedScanRegion? CopiedRegion => regionEditor.CopiedRegion;

    public void SelectRegion(string? regionId) => regionEditor.Select(regionId);

    public string? AddRegion() => regionEditor.Add(Capabilities, Options);

    public bool DeleteSelectedRegion() => regionEditor.DeleteSelected();

    public bool CopySelectedRegion() => regionEditor.CopySelected();

    public bool PasteRegion() => regionEditor.Paste(Capabilities);

    public FlatbedFrameGridStatus RefreshRegions(
        ReadOnlySpan<float> previewLuminance,
        uint previewWidth,
        uint previewHeight) =>
        regionEditor.Refresh(Capabilities, Options, previewLuminance, previewWidth, previewHeight);

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

    public IReadOnlyList<int> Resolutions =>
        ScanOptionPolicy.Resolutions(Capabilities, Options.ResolutionDpi);

    public IReadOnlyList<int> BitDepths => ScanOptionPolicy.BitDepths(Capabilities);

    public IReadOnlyList<string> ColorModes => ScanOptionPolicy.ColorModes(Capabilities);

    public bool HasUsableCapabilities => ScanOptionPolicy.HasUsableCapabilities(Capabilities);

    public bool CanScan => State is ScanSessionState.Ready && HasUsableCapabilities;

    public bool CanPreview => CanScan && Capabilities?.SupportsPreview == true;

    public bool CanUseInfrared =>
        Capabilities?.SupportsInfrared == true && AllowsInfrared(Options.FilmType);

    public static bool AllowsInfrared(FilmType filmType) =>
        ScanOptionPolicy.AllowsInfrared(filmType);

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
        => ScanOptionPolicy.Clamp(Capabilities, Options.ResolutionDpi, options);

    /// <summary>
    /// 지금 옵션으로 보낼 요청입니다. 스캔을 돌리기 전에 무엇이 나갈지 시험할 수 있도록 따로
    /// 냅니다 — 요청을 만드는 규칙이 스캔 실행 안에 숨으면 확인할 방법이 없습니다.
    /// </summary>
    public ScannerPluginScanRequest? BuildRequest(
        bool preview,
        string destinationVisiblePath,
        int regionIndex = -1)
        => ScanOptionPolicy.BuildRequest(
            SelectedDevice,
            Capabilities,
            Options,
            preview,
            destinationVisiblePath,
            UsesFlatbedRegionWorkflow ? regionEditor.RegionAt(regionIndex) : null,
            DefaultRotation);

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

        int requested = preview
            ? 1
            : UsesFlatbedRegionWorkflow ? Regions.Count : Options.BatchCount;
        IsScanning = true;
        LastFailureName = null;
        Changed?.Invoke(this, EventArgs.Empty);
        try
        {
            ScanRunExecution execution = await ScanRunCoordinator.RunAsync(
                ActiveGateway,
                ResolveApprovedPlugin,
                library,
                destinationForIndex,
                BuildRequest,
                preview,
                requested,
                cancellationToken).ConfigureAwait(false);
            LastFailureName = execution.FailureName;
            if (execution.PreviewPath is not null)
            {
                LastPreviewPath = execution.PreviewPath;
            }
            return execution.Outcome;
        }
        finally
        {
            IsScanning = false;
            _ = dispatcher.TryEnqueue(() => Changed?.Invoke(this, EventArgs.Empty));
        }
    }

    private (InstalledScannerPlugin? Plugin, ScannerPluginTrustIdentity? Identity)
        ResolveApprovedPlugin()
    {
        InstalledScannerPlugin? plugin = Plugins.FirstOrDefault(candidate =>
            ApprovedIdentityFor(candidate) is not null);
        return (plugin, plugin is null ? null : ApprovedIdentityFor(plugin));
    }
}
