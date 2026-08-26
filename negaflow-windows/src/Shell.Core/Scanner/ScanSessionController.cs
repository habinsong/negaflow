using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;

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
    private string? previewFrameId;

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
            () => RaiseChanged());
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

    /// <summary>
    /// 스캔 진행 상태입니다. macOS 는 <c>AppModel</c> 이 <c>scanPhase</c>/<c>scanFraction</c> 을
    /// 들고 <c>ScanProgressOverlay</c> 가 그것을 그립니다. 여기가 그 자리입니다.
    /// </summary>
    public ScanProgressState Progress { get; } = new();

    public bool IsScanning { get; private set; }

    /// <summary>
    /// macOS <c>selectScanStorageRoot(_:)</c> — 스캔 원본을 둘 폴더입니다.
    /// <see langword="null"/> 이면 라이브러리 아래 <c>Scans</c> 를 씁니다.
    /// </summary>
    public string? ScanStorageRoot { get; set; }

    /// <summary>마지막 실패의 이유입니다. 성공하면 지웁니다.</summary>
    public string? LastFailureName { get; private set; }

    /// <summary>
    /// 마지막 프리뷰 스캔이 남긴 파일입니다. 자동 프레임 찾기가 이 그림에서 프레임을 셉니다.
    /// 프리뷰 frame은 메모리에만 게시하며 원본 파일 경로는 여기서 붙잡습니다.
    /// </summary>
    public string? LastPreviewPath { get; private set; }

    /// <summary>선택된 scanner preview의 Guided 영역을 전체 스캔 시작 직전에 캡처합니다.</summary>
    public Func<GrainMendGuidedCarryover?>? GuidedCarryoverProvider { get; set; }

    /// <summary>첫 전체 스캔 frame이 게시된 뒤 캡처한 Guided 영역을 소비자에게 넘깁니다.</summary>
    public Action<string, GrainMendGuidedCarryover>? GuidedCarryoverPublished { get; set; }

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

    /// <summary>지금 쓰는 게이트웨이입니다. 배치 계약 시험이 이것을 그대로 씁니다.</summary>
    internal IScannerPluginGateway ActiveGatewayForTests => ActiveGateway;

    public bool UsesFlatbedRegionWorkflow =>
        ScanOptionPolicy.UsesFlatbedRegionWorkflow(Capabilities);

    public IReadOnlyList<FlatbedFrameFormat> AvailableFrameFormats =>
        ScanOptionPolicy.AvailableFrameFormats(Capabilities);

    public IReadOnlyList<FlatbedScanRegion> Regions => regionEditor.Regions;

    public string? SelectedRegionId => regionEditor.SelectedRegionId;

    public FlatbedScanRegion? CopiedRegion => regionEditor.CopiedRegion;

    /// <summary>
    /// 바뀜을 알립니다. <b>구독자 하나가 던져도 여기서 멈추지 않습니다.</b>
    /// </summary>
    /// <remarks>
    /// 이 알림은 장치 탐색 도중 <b>워커 스레드</b>에서도 올라갑니다(`ConfigureAwait(false)`
    /// 뒤). 구독자가 그 스레드에서 XAML 을 건드리면 WinUI 가 `COMException` 을 던지고, 그
    /// 예외가 그대로 올라와 <b>장치 탐색을 통째로 끊었습니다</b> — 실기에서 스캐너가 아예
    /// 안 잡히거나 "심도 옵션을 보고하지 않아 스캔할 수 없습니다" 로 끝났습니다.
    ///
    /// 구독자를 고치는 것과 별개로, 알림 하나가 장치 목록을 못 죽이게 여기서 막습니다 —
    /// 화면 한 곳이 잘못돼도 스캐너는 잡혀야 합니다. 삼킨 예외는 기록에 남깁니다.
    /// </remarks>
    private void RaiseChanged()
    {
        try
        {
            Changed?.Invoke(this, EventArgs.Empty);
        }
        catch (Exception error)
        {
            ScannerDiagnosticsLog.Write(
                $"scan session listener threw: {error.GetType().Name} {error.Message}");
        }
    }

    public void SelectRegion(string? regionId) => regionEditor.Select(regionId);

    public string? AddRegion(FlatbedScanRegion? unitRect = null) =>
        regionEditor.Add(Capabilities, Options, unitRect);

    /// <summary>프레임 하나를 새 자리로 옮깁니다. 오버레이의 끌기가 이것으로 들어옵니다.</summary>
    public bool UpdateRegion(string regionId, FlatbedScanRegion moved) =>
        regionEditor.Update(regionId, moved);

    /// <summary>선택한 프레임을 방향키 한 칸만큼 밉니다.</summary>
    public bool NudgeSelectedRegion(
        double deltaX,
        double deltaY,
        bool coarse = false,
        ImageTransformRecipe? previewTransform = null,
        uint sourceWidth = 0,
        uint sourceHeight = 0) =>
        regionEditor.NudgeSelected(
            Capabilities,
            deltaX,
            deltaY,
            coarse,
            previewTransform,
            sourceWidth,
            sourceHeight);

    /// <summary>프리뷰가 담은 실제 영역입니다. 비율을 밀리미터로 되돌리는 자입니다.</summary>
    public FlatbedPreviewArea PreviewArea => regionEditor.ResolvePreviewArea(Capabilities);

    /// <summary>화면에 걸린 프리뷰 프레임의 카탈로그 식별자입니다.</summary>
    public string? PreviewFrameId => previewFrameId;

    /// <summary>새 프리뷰를 받았습니다. macOS <c>prepareFlatbedPreview</c> 자리입니다.</summary>
    public void PrepareForPreview(string? frameId, ScannerPluginScanArea? scanArea)
    {
        previewFrameId = frameId;
        regionEditor.PrepareForPreview(frameId, scanArea);
    }

    public void ClearPreview()
    {
        previewFrameId = null;
        regionEditor.ClearPreview();
    }

    public bool DeleteSelectedRegion() => regionEditor.DeleteSelected();

    public bool CopySelectedRegion() => regionEditor.CopySelected();

    public bool PasteRegion() => regionEditor.Paste(Capabilities, Options);

    public FlatbedFrameGridStatus RefreshRegions(
        ReadOnlySpan<float> previewLuminance,
        uint previewWidth,
        uint previewHeight,
        double previewPhysicalWidthMm = 0,
        double previewPhysicalHeightMm = 0) =>
        regionEditor.Refresh(
            Capabilities,
            Options,
            previewLuminance,
            previewWidth,
            previewHeight,
            previewPhysicalWidthMm,
            previewPhysicalHeightMm);

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
        RaiseChanged();
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
        RaiseChanged();
        var found = new List<ScannerPluginDevice>();
        ScannerDiagnosticsLog.Write(
            $"detect start plugins={Plugins.Count} simulator={SimulatorEnabled}");
        try
        {
            foreach (InstalledScannerPlugin plugin in Plugins)
            {
                if (ApprovedIdentityFor(plugin) is not { } identity)
                {
                    ScannerDiagnosticsLog.Write(
                        $"detect skip {plugin.Manifest.Id} - not approved");
                    continue;
                }
                ScannerPluginDetectResult result =
                    await ActiveGateway.DetectAsync(plugin, identity, cancellationToken)
                        .ConfigureAwait(false);
                if (result.IsSuccess)
                {
                    found.AddRange(result.Devices);
                    ScannerDiagnosticsLog.Write(
                        $"detect ok {plugin.Manifest.Id} devices={result.Devices.Count}");
                }
                else
                {
                    LastFailureName ??= result.IsMalformedResponse
                        ? "malformed_detect_response"
                        : result.Process.Status.ToString();
                    ScannerDiagnosticsLog.Write(
                        $"detect failed {plugin.Manifest.Id} - {LastFailureName} " +
                        $"(malformed={result.IsMalformedResponse} " +
                        $"process={result.Process.Status} exit={result.Process.ExitCode?.ToString() ?? "none"})");
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
        ScannerDiagnosticsLog.Write(
            $"detect end devices={found.Count} selected={SelectedDevice?.Id ?? "none"}");
        RaiseChanged();
        if (SelectedDevice is not null)
        {
            await LoadCapabilitiesAsync(cancellationToken).ConfigureAwait(false);
        }
        else
        {
            Capabilities = null;
            RaiseChanged();
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
        RaiseChanged();
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
            RaiseChanged();
            return;
        }
        Capabilities = null;
        LastFailureName ??= "capabilities_unavailable";
        RaiseChanged();
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
        RaiseChanged();
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
            regionEditor.ResolvePreviewArea(Capabilities),
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
        CancellationToken cancellationToken = default,
        Action<int>? framePublished = null)
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
        GrainMendGuidedCarryover? guidedCarryover = !preview && !UsesFlatbedRegionWorkflow
            ? GuidedCarryoverProvider?.Invoke()
            : null;
        IsScanning = true;
        LastFailureName = null;
        RaiseChanged();
        // **취소권은 세션이 가집니다.** 스캔 패널은 라이브러리뷰와 현상뷰 양쪽에 하나씩
        // 있고 각자 자기 실행을 들고 있었습니다. 그런데 취소 단추가 보이는 조건은 공유되는
        // `IsScanning` 이라, 스캔을 시작하지 않은 쪽 패널에서도 단추가 떴고 그것을 누르면
        // 자기에게는 끊을 것이 없어 **아무 일도 일어나지 않았습니다.**
        using CancellationTokenSource run =
            CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        activeRun = run;
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
                index => InitialTransformForRegion(index, library),
                guidedCarryover,
                GuidedCarryoverPublished,
                framePublished,
                run.Token,
                Progress).ConfigureAwait(false);
            LastFailureName = execution.FailureName;
            if (execution.PreviewPath is not null)
            {
                LastPreviewPath = execution.PreviewPath;
            }
            if (preview && execution.PreviewFrameId is not null)
            {
                previewFrameId = execution.PreviewFrameId;
            }
            if (preview && UsesFlatbedRegionWorkflow && execution.PreviewScanArea is not null)
            {
                // 이 프리뷰가 담은 영역이 앞으로 프레임 비율을 밀리미터로 되돌리는 자입니다.
                regionEditor.PrepareForPreview(
                    execution.PreviewFrameId, execution.PreviewScanArea);
            }
            if (!preview && execution.Outcome.Published > 0 &&
                (!UsesFlatbedRegionWorkflow || execution.Outcome.Published == requested))
            {
                _ = library.RemoveScannerPreviewFrames();
                previewFrameId = null;
            }
            return execution.Outcome;
        }
        finally
        {
            if (ReferenceEquals(activeRun, run))
            {
                activeRun = null;
            }
            IsScanning = false;
            _ = dispatcher.TryEnqueue(() => RaiseChanged());
        }
    }

    /// <summary>돌고 있는 스캔을 멈춥니다. 어느 화면의 취소 단추든 이리로 옵니다.</summary>
    /// <returns>멈출 것이 있었으면 <see langword="true"/> 입니다.</returns>
    public bool CancelActiveRun()
    {
        if (activeRun is not { IsCancellationRequested: false } run)
        {
            ScannerDiagnosticsLog.Write("cancel requested but no run is active");
            return false;
        }
        ScannerDiagnosticsLog.Write("cancel requested - stopping the active run");
        try
        {
            run.Cancel();
        }
        catch (ObjectDisposedException)
        {
            // 방금 끝났습니다. 멈출 것이 없습니다.
            return false;
        }
        return true;
    }

    /// <summary>지금 돌고 있는 실행입니다. 없으면 <see langword="null"/> 입니다.</summary>
    private CancellationTokenSource? activeRun;

    private ImageTransformRecipe? InitialTransformForRegion(
        int regionIndex,
        LibraryHostService library)
    {
        if (!UsesFlatbedRegionWorkflow || regionEditor.RegionAt(regionIndex) is not { } region)
        {
            return null;
        }
        ImageTransformRecipe? previewTransform = previewFrameId is { } frameId
            ? library.Frames.FirstOrDefault(frame =>
                string.Equals(frame.Id, frameId, StringComparison.Ordinal))?.ImageTransform
            : null;
        return FlatbedInitialTransform(previewTransform, DefaultRotation, region);
    }

    internal static ImageTransformRecipe FlatbedInitialTransform(
        ImageTransformRecipe? previewTransform,
        ImageRotation defaultRotation,
        FlatbedScanRegion region)
    {
        ArgumentNullException.ThrowIfNull(region);
        ImageTransformRecipe orientation = previewTransform is null
            ? ImageTransformRecipe.Identity
            : previewTransform with
            {
                Crop = null,
                StraightenAngle = 0.0,
                CropAspect = null,
            };
        if (orientation == ImageTransformRecipe.Identity)
        {
            orientation = ImageTransformRecipe.Identity with { Rotation = defaultRotation };
        }
        return orientation with
        {
            Crop = null,
            StraightenAngle = orientation.FlipHorizontal != orientation.FlipVertical
                ? -region.StraightenAngle
                : region.StraightenAngle,
            CropAspect = null,
        };
    }

    private (InstalledScannerPlugin? Plugin, ScannerPluginTrustIdentity? Identity)
        ResolveApprovedPlugin()
    {
        InstalledScannerPlugin? plugin = Plugins.FirstOrDefault(candidate =>
            ApprovedIdentityFor(candidate) is not null);
        return (plugin, plugin is null ? null : ApprovedIdentityFor(plugin));
    }
}
