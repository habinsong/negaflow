using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Interop;

namespace Negaflow.Shell.Views.Library.Scanner;

/// <summary>
/// 라이브러리 가져오기 절의 스캔 카드입니다. 플러그인 탐색·승인·스캔 실행을 맡습니다.
/// </summary>
public sealed partial class LibraryScanPanel : UserControl
{
    internal LibraryHostService? libraryHost;
    internal ScanSessionController? scanSession;
    internal ScannerPluginTrustStore? scannerTrust;
    internal ScanSessionHost? sessionHost;
    internal bool initialScannerDetectionStarted;
    internal bool isSynchronizingScan;
    /// <summary>마지막 프리뷰 스캔의 밝기 값입니다. 자동 프레임 찾기가 이것으로 셉니다.</summary>
    internal PreviewLuminance flatbedPreview = PreviewLuminance.None;
    internal ImageRotation defaultRotation = ImageRotation.Degrees0;

    /// <summary>
    /// 설정 · 디스크 탭이 정한 자리들입니다. 스캔 원본과 프리뷰 캐시가 여기서 나옵니다.
    /// </summary>
    /// <remarks>
    /// <b>빈 상태가 없습니다.</b> 앞 판은 경로 두 개를 문자열로 들고 있었고 그 문자열은
    /// <c>Changed</c> 가 한 번 올 때까지 비어 있었습니다 — 설정을 건드리지 않은 첫 세션에서
    /// 스캔 원본이 통째로 카탈로그 폴더 아래로 떨어진 자리입니다. macOS
    /// <c>DiskStorageStore</c> 는 늘 값이 있으므로 여기도 기본 설정으로 시작합니다.
    /// </remarks>
    internal Negaflow.Shell.Storage.DiskStorageLocations diskLocations =
        new(new Negaflow.Shell.Storage.DiskStorageSettings());
    internal readonly LibraryScanRenderer renderer;
    internal readonly LibraryScanRunner runner;
    internal readonly LibraryScanCopy copy;

    public LibraryScanPanel()
    {
        InitializeComponent();
        renderer = new LibraryScanRenderer(this);
        runner = new LibraryScanRunner(this);
        copy = new LibraryScanCopy(this);
    }

    /// <summary>가져오기 스캐너 단추가 켜져 있는지. 절 가시성이 이 값에 따릅니다.</summary>
    public Func<bool>? IsWanted { get; set; }

    /// <summary>폴더 고르개를 띄울 창입니다. 없으면 스캔 폴더를 고를 수 없습니다.</summary>
    public Microsoft.UI.WindowId? WindowId { get; set; }

    /// <summary>플러그인 승인·장치가 있어 가져오기 절을 펼쳐야 할 때 올립니다.</summary>
    public event EventHandler? ExpandRequested;

    /// <summary>카탈로그에 올린 뒤 격자를 다시 그릴 때 올립니다.</summary>
    public event EventHandler? LibraryChanged;

    /// <summary>
    /// 평판 프리뷰나 그 위의 프레임이 바뀌었습니다. 라이브러리 화면이 오버레이를 다시
    /// 그립니다 - macOS 는 프리뷰 프레임이 곧 캔버스라 이 알림이 필요 없습니다.
    /// </summary>
    public event EventHandler? FlatbedPreviewChanged;

    /// <summary>
    /// 세션 값이 화면에 반영될 때마다 올립니다. 창 안 메뉴막대가 macOS 스캐너 메뉴처럼
    /// 지금 상태를 되비추려면 이 신호가 필요합니다.
    /// </summary>
    public event EventHandler? MenuStateChanged;

    /// <summary>macOS 스캐너 메뉴가 읽는 값입니다.</summary>
    public ScannerMenuState MenuState => scanSession is { } session
        ? new ScannerMenuState(
            !session.IsDetecting && !session.IsScanning,
            session.SimulatorEnabled,
            session.CanPreview,
            session.CanScan,
            session.UsesFlatbedRegionWorkflow)
        : ScannerMenuState.Empty;

    /// <summary>
    /// macOS <c>hasScanner</c> — <c>backend != nil</c>, 즉 <b>고를 수 있는 장치가 실제로 잡혀
    /// 있는가</b>입니다. 플러그인이 깔려 있는지는 macOS <c>hasScannerPlugin</c> 이라 별개이며,
    /// 위 막대의 "사진 스캔"은 macOS <c>WorkspaceToolbar</c> 와 같이 이 값만 봅니다 —
    /// 플러그인 존재로 재면 스캐너를 꽂지 않아도 단추가 남습니다.
    /// </summary>
    internal bool HasScanner => scanSession?.SelectedDevice is not null;

    /// <summary>macOS <c>hasScannerPlugin</c> — 설치된 플러그인이 하나라도 있는지입니다.</summary>
    internal bool HasScannerPlugin => scanSession?.Plugins.Count > 0;

    /// <summary>macOS <c>capabilities.supportsPreview</c> 에 해당합니다.</summary>
    internal bool SupportsPreview => scanSession?.Capabilities?.SupportsPreview == true;

    /// <summary>macOS <c>.detectScanners</c> — 다시 찾기 단추와 같은 길입니다.</summary>
    public async Task DetectScannersFromMenuAsync()
    {
        EnsureSession();
        RaiseMenuStateChanged();
        if (scanSession is { IsDetecting: false, IsScanning: false } session)
        {
            await session.RefreshDevicesAsync();
        }
    }

    /// <summary>macOS <c>.toggleScannerSimulator</c> — 시뮬레이터 스위치와 같은 길입니다.</summary>
    public async Task ToggleSimulatorFromMenuAsync()
    {
        EnsureSession();
        if (scanSession is not { } session)
        {
            RaiseMenuStateChanged();
            return;
        }
        session.SetSimulatorEnabled(!session.SimulatorEnabled);
        SimulatorPublisher?.Invoke(session.SimulatorEnabled);
        RaiseMenuStateChanged();
        if (session.State is ScanSessionState.NoDevice)
        {
            await session.RefreshDevicesAsync();
        }
    }

    /// <summary>macOS <c>.previewScan</c>.</summary>
    public Task PreviewScanFromMenuAsync() => runner.RunAsync(preview: true);

    /// <summary>macOS <c>.scanFrame</c> — 한 장입니다.</summary>
    public Task ScanFrameFromMenuAsync() => runner.RunAsync(preview: false);

    /// <summary>macOS <c>.addFlatbedFrame</c>.</summary>
    public void AddFlatbedFrameFromMenu()
    {
        _ = scanSession?.AddRegion();
        renderer.Render();
    }

    /// <summary>macOS <c>.removeFlatbedFrame</c>.</summary>
    public void RemoveFlatbedFrameFromMenu()
    {
        _ = scanSession?.DeleteSelectedRegion();
        renderer.Render();
    }

    /// <summary>macOS의 사진 삭제 라우팅처럼 actionable preview에서는 사진 대신 프레임을 지웁니다.</summary>
    internal bool TryDeleteSelectedFlatbedRegion()
    {
        if (scanSession is not { Regions.Count: > 0 } session ||
            libraryHost?.ActiveFrameId is not { } activeFrameId ||
            libraryHost.Frames.FirstOrDefault(frame => frame.Id == activeFrameId)?.IsPreviewScan != true ||
            !session.DeleteSelectedRegion())
        {
            return false;
        }
        renderer.Render();
        return true;
    }

    internal void SetScanStatus(string text)
    {
        ScanStatusText.Text = text;
        ScanStatusText.Visibility = string.IsNullOrWhiteSpace(text)
            ? Visibility.Collapsed
            : Visibility.Visible;
    }

    internal void RaiseMenuStateChanged()
    {
        PublishCapabilities();
        MenuStateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void Bind(LibraryHostService host)
    {
        ArgumentNullException.ThrowIfNull(host);
        libraryHost = host;
    }

    /// <summary>
    /// 설정 창이 "스캐너 정보" 를 읽어 갈 자리입니다. 세션이 성능을 새로 받을 때마다
    /// 여기로 올립니다.
    /// </summary>
    public Action<ScannerPluginCapabilities?>? CapabilitiesPublisher { get; set; }

    /// <summary>
    /// 설정 · 워크플로의 "스캐너 시뮬레이터" 입니다. macOS <c>model.demoMode</c> 와 같은
    /// 자리이며, 켜면 세션이 진짜 플러그인 대신 <c>SimulatedScannerGateway</c> 를 씁니다.
    /// </summary>
    /// <remarks>
    /// 설정 창과 패널의 스위치와 메뉴 명령이 <b>같은 값 하나</b>를 봐야 합니다. 각자 따로
    /// 들고 있으면 설정에서 켜도 스캔 화면은 진짜 장치를 찾습니다 - 지금까지 그랬습니다.
    /// </remarks>
    public async Task ApplySimulatorEnabledAsync(bool enabled)
    {
        if (scanSession is not { } session || session.SimulatorEnabled == enabled)
        {
            pendingSimulatorEnabled = enabled;
            return;
        }
        pendingSimulatorEnabled = enabled;
        session.SetSimulatorEnabled(enabled);
        Render();
        RaiseMenuStateChanged();
        if (session.State is ScanSessionState.NoDevice)
        {
            await session.RefreshDevicesAsync();
            Render();
        }
    }

    /// <summary>세션이 아직 없을 때 받아 둔 값입니다. 세션이 생기면 그때 겁니다.</summary>
    internal bool pendingSimulatorEnabled;

    /// <summary>패널이나 메뉴에서 스위치를 움직이면 설정에도 적어 둡니다.</summary>
    public Action<bool>? SimulatorPublisher { get; set; }

    /// <summary>설정 · 디스크 탭이 정한 자리를 겁니다(스캔 원본 · 프리뷰 캐시).</summary>
    public void ApplyDiskStorage(Negaflow.Shell.Storage.DiskStorageSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        diskLocations = new Negaflow.Shell.Storage.DiskStorageLocations(settings);
    }

    /// <summary>설정에서 고른 기본 스캔 회전입니다. 세션이 아직 없어도 기억해 둡니다.</summary>
    public void ApplyDefaultRotation(ImageRotation rotation)
    {
        defaultRotation = rotation;
        sessionHost?.ApplyDefaultRotation(rotation);
        if (scanSession is not null)
        {
            scanSession.DefaultRotation = rotation;
        }
    }

    /// <summary>세션이 성능을 새로 받았습니다. 설정 창에 그대로 넘깁니다.</summary>
    internal void PublishCapabilities() =>
        CapabilitiesPublisher?.Invoke(scanSession?.Capabilities);

    /// <summary>진단이 읽는 값들입니다. 세션이 없으면 비어 있습니다.</summary>
    internal bool SimulatorEnabledForDiagnostics => scanSession?.SimulatorEnabled ?? false;

    internal string SelectedDeviceNameForDiagnostics =>
        scanSession?.SelectedDevice?.DisplayName ?? string.Empty;

    internal IReadOnlyList<InstalledScannerPlugin> PluginsForDiagnostics =>
        scanSession?.Plugins ?? [];

    /// <summary>
    /// 이름표뿐 아니라 <b>목록</b>도 다시 겁니다 — 필름 종류(컬러 네거티브·흑백 포지티브 …),
    /// 색 방식, 스캔 단추 이름은 <see cref="Render"/> 가 만들어 넣는 것이라 이름표만 다시
    /// 걸면 옛 언어로 남습니다.
    /// </summary>
    public void Localize()
    {
        copy.Localize();
        Render();
    }

    public void Render()
    {
        renderer.Render();
        PublishCapabilities();
    }

    /// <summary>공유 현상 사이드바의 스캐너 명령이 이 세션을 엽니다.</summary>
    public async void Open()
    {
        ExpandRequested?.Invoke(this, EventArgs.Empty);
        await OpenAsync();
    }

    public async Task DetectOnLoadAsync()
    {
        if (initialScannerDetectionStarted)
        {
            return;
        }
        initialScannerDetectionStarted = true;
        EnsureSession();
        if (scanSession is null)
        {
            return;
        }
        if (scanSession.State is ScanSessionState.NeedsApproval)
        {
            ExpandRequested?.Invoke(this, EventArgs.Empty);
            renderer.Render();
            return;
        }
        if (scanSession.State is not ScanSessionState.NoDevice)
        {
            return;
        }
        await scanSession.RefreshDevicesAsync();
        if (scanSession.Devices.Count > 0)
        {
            ExpandRequested?.Invoke(this, EventArgs.Empty);
            renderer.Render();
        }
    }

    /// <summary>
    /// 라이브러리뷰와 현상뷰가 나눠 쓰는 스캐너 상태를 겁니다.
    /// </summary>
    /// <remarks>
    /// macOS 는 <c>AppModel</c> 하나가 스캐너를 들고 두 사이드바가 같은
    /// <c>ScannerControlsSection</c> 을 냅니다. 붙이지 않으면 이 패널은 아무 것도 그리지
    /// 못합니다 — 세션이 없으면 상태가 늘 "플러그인 없음" 이기 때문입니다.
    /// </remarks>
    public void AttachSessionHost(ScanSessionHost host)
    {
        ArgumentNullException.ThrowIfNull(host);
        if (ReferenceEquals(sessionHost, host))
        {
            return;
        }
        if (sessionHost is not null)
        {
            sessionHost.SessionCreated -= OnHostSessionCreated;
            sessionHost.ShowScannerControlsChanged -= OnHostSessionCreated;
        }
        sessionHost = host;
        sessionHost.SessionCreated += OnHostSessionCreated;
        sessionHost.ShowScannerControlsChanged += OnHostSessionCreated;
        sessionHost.ApplyDefaultRotation(defaultRotation);
        AdoptHostSession();
        renderer.Render();
    }

    private void OnHostSessionCreated(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        AdoptHostSession();
        renderer.Render();
    }

    /// <summary>공유 세션을 이 패널에 겁니다. 이미 같은 것이면 아무 일도 하지 않습니다.</summary>
    private void AdoptHostSession()
    {
        if (sessionHost?.Session is not { } shared || ReferenceEquals(shared, scanSession))
        {
            return;
        }
        if (scanSession is not null)
        {
            scanSession.Changed -= OnScanSessionChanged;
        }
        scanSession = shared;
        scannerTrust = sessionHost.Trust;
        scanSession.Changed += OnScanSessionChanged;
    }

    internal void EnsureSession()
    {
        if (scanSession is not null)
        {
            return;
        }
        // 공유 자리가 있으면 거기서만 만듭니다. 패널마다 만들면 두 사이드바가 서로 다른
        // 스캐너 상태를 보게 됩니다.
        if (sessionHost is not null)
        {
            _ = sessionHost.Ensure();
            AdoptHostSession();
            return;
        }
        if (DispatcherQueueUiDispatcher.CaptureForCurrentThread() is not { } uiDispatcher)
        {
            return;
        }
        scannerTrust = new ScannerPluginTrustStore();
        scanSession = new ScanSessionController(
            new ScannerPluginGateway(),
            scannerTrust,
            uiDispatcher);
        scanSession.DefaultRotation = defaultRotation;
        scanSession.Changed += OnScanSessionChanged;
    }

    internal bool Wanted => IsWanted?.Invoke() == true;

    internal void RequestLibraryReload() => LibraryChanged?.Invoke(this, EventArgs.Empty);

    internal void RaiseFlatbedPreviewChanged() =>
        FlatbedPreviewChanged?.Invoke(this, EventArgs.Empty);

    /// <summary>오버레이가 그릴 프리뷰 파일입니다. 없으면 null 입니다.</summary>
    internal string? FlatbedPreviewPath =>
        scanSession is { UsesFlatbedRegionWorkflow: true } &&
            !string.IsNullOrWhiteSpace(scanSession.LastPreviewPath)
            ? scanSession.LastPreviewPath
            : null;

    /// <summary>오버레이가 붙잡을 세션입니다.</summary>
    internal ScanSessionController? SessionForOverlay => scanSession;

    /// <summary>오버레이가 프레임을 고쳤습니다. 개수 표시와 단추를 다시 그립니다.</summary>
    internal void OnOverlayRegionsChanged() => renderer.Render();

    internal async Task OpenAsync()
    {
        EnsureSession();
        if (scanSession is null || !Wanted)
        {
            renderer.Render();
            return;
        }
        // 열 때마다 플러그인 목록을 다시 읽습니다 — 방금 설치한 플러그인이 보여야 합니다.
        scanSession.Refresh();
        if (scanSession.State is ScanSessionState.NoDevice)
        {
            await scanSession.RefreshDevicesAsync();
        }
    }

    private void OnScanSessionChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (DispatcherQueue.HasThreadAccess)
        {
            RenderAndNotify();
            return;
        }
        _ = DispatcherQueue.TryEnqueue(RenderAndNotify);
    }

    /// <summary>
    /// 화면과 메뉴막대는 같은 값을 봅니다. 스캔 절이 접혀 있어도(<c>Render</c> 가 일찍
    /// 돌아가도) 메뉴는 갱신돼야 하므로 여기서 함께 올립니다.
    /// </summary>
    private void RenderAndNotify()
    {
        renderer.Render();
        RaiseMenuStateChanged();
    }
}
