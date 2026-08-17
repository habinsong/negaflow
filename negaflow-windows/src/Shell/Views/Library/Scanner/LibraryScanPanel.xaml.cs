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
    internal bool initialScannerDetectionStarted;
    internal bool isSynchronizingScan;
    /// <summary>마지막 프리뷰 스캔의 밝기 값입니다. 자동 프레임 찾기가 이것으로 셉니다.</summary>
    internal PreviewLuminance flatbedPreview = PreviewLuminance.None;
    internal ImageRotation defaultRotation = ImageRotation.Degrees0;
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

    /// <summary>플러그인 승인·장치가 있어 가져오기 절을 펼쳐야 할 때 올립니다.</summary>
    public event EventHandler? ExpandRequested;

    /// <summary>카탈로그에 올린 뒤 격자를 다시 그릴 때 올립니다.</summary>
    public event EventHandler? LibraryChanged;

    public void Bind(LibraryHostService host)
    {
        ArgumentNullException.ThrowIfNull(host);
        libraryHost = host;
    }

    /// <summary>설정에서 고른 기본 스캔 회전입니다. 세션이 아직 없어도 기억해 둡니다.</summary>
    public void ApplyDefaultRotation(ImageRotation rotation)
    {
        defaultRotation = rotation;
        if (scanSession is not null)
        {
            scanSession.DefaultRotation = rotation;
        }
    }

    public void Localize() => copy.Localize();

    public void Render() => renderer.Render();

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

    internal void EnsureSession()
    {
        if (scanSession is not null)
        {
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
            renderer.Render();
            return;
        }
        _ = DispatcherQueue.TryEnqueue(renderer.Render);
    }

    private void OnScanApprovePluginClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (scanSession?.PluginsRequiringApproval is not { Count: > 0 } pending)
        {
            return;
        }
        foreach (InstalledScannerPlugin plugin in pending)
        {
            scanSession.Approve(plugin);
        }
    }

    /// <summary>
    /// 하드웨어 없이 스캔 흐름을 돌립니다. 켜면 가상 장치가 나타나고, 스캔은 합성 네거티브를
    /// 실제와 같은 게시 경로로 카탈로그에 올립니다.
    /// </summary>
    private async void OnScanSimulatorToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingScan || scanSession is null)
        {
            return;
        }
        scanSession.SetSimulatorEnabled(ScanSimulatorToggle.IsOn);
        if (scanSession.State is ScanSessionState.NoDevice)
        {
            await scanSession.RefreshDevicesAsync();
        }
    }

    private async void OnScanRescanClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (scanSession is not null)
        {
            await scanSession.RefreshDevicesAsync();
        }
    }

    private async void OnScanDeviceChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingScan ||
            scanSession is null ||
            ScanDeviceSelector.SelectedItem is not ComboBoxItem { Tag: string deviceId })
        {
            return;
        }
        await scanSession.SelectDeviceAsync(deviceId);
    }

    private void OnScanFilmChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingScan ||
            ScanFilmSelector.SelectedItem is not ComboBoxItem { Tag: FilmType filmType })
        {
            return;
        }
        scanSession?.UpdateOptions(options => options with { FilmType = filmType });
    }

    private void OnScanFolderNameChanged(object sender, TextChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingScan)
        {
            return;
        }
        scanSession?.UpdateOptions(options => options with { FolderName = ScanFolderNameBox.Text });
    }

    private void OnScanResolutionChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingScan ||
            ScanResolutionSelector.SelectedItem is not ComboBoxItem { Tag: int dpi })
        {
            return;
        }
        scanSession?.UpdateOptions(options => options with { ResolutionDpi = dpi });
    }

    private void OnScanColorModeChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingScan ||
            ScanColorModeSelector.SelectedItem is not ComboBoxItem { Tag: string mode })
        {
            return;
        }
        scanSession?.UpdateOptions(options => options with { ColorMode = mode });
    }

    private void OnScanBitDepthChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingScan ||
            ScanBitDepthSelector.SelectedItem is not ComboBoxItem { Tag: int depth })
        {
            return;
        }
        scanSession?.UpdateOptions(options => options with { BitDepth = depth });
    }

    private void OnScanFrameCountChanged(NumberBox sender, NumberBoxValueChangedEventArgs args)
    {
        _ = sender;
        if (isSynchronizingScan || double.IsNaN(args.NewValue))
        {
            return;
        }
        scanSession?.UpdateOptions(options => options with { BatchCount = (int)args.NewValue });
    }

    private void OnScanInfraredToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingScan)
        {
            return;
        }
        scanSession?.UpdateOptions(options => options with { Infrared = ScanInfraredToggle.IsOn });
    }

    private void OnScanFrameFormatChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingScan ||
            ScanFrameFormatSelector.SelectedItem is not ComboBoxItem { Tag: FlatbedFrameFormat format })
        {
            return;
        }
        scanSession?.UpdateOptions(options => options with { FrameFormat = format });
    }

    private void OnScanDetectionModeChecked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingScan || scanSession is null)
        {
            return;
        }
        scanSession.UpdateOptions(options => options with
        {
            FrameDetectionMode = ScanDetectionManualButton.IsChecked == true
                ? FlatbedFrameDetectionMode.Manual
                : FlatbedFrameDetectionMode.Automatic,
        });
    }

    /// <summary>
    /// 자동이면 프리뷰에서 다시 찾고, 수동이면 지우고 규격 프레임 하나를 놓아 다시 시작할 자리를
    /// 만듭니다 — macOS 새로고침과 같은 규칙입니다.
    /// </summary>
    private void OnScanRefreshFramesClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (scanSession is null)
        {
            return;
        }
        // 프리뷰 픽셀이 아직 없으면 찾을 근거가 없습니다. macOS 도 프리뷰 전에는 잠급니다.
        _ = scanSession.RefreshRegions(
            flatbedPreview.Values,
            flatbedPreview.Width,
            flatbedPreview.Height);
        renderer.Render();
    }

    private void OnScanAddFrameClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        _ = scanSession?.AddRegion();
        renderer.Render();
    }

    private void OnScanRemoveFrameClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        _ = scanSession?.DeleteSelectedRegion();
        renderer.Render();
    }

    private void OnScanCopyFrameClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        _ = scanSession?.CopySelectedRegion();
        renderer.Render();
    }

    private void OnScanPasteFrameClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        _ = scanSession?.PasteRegion();
        renderer.Render();
    }

    private async void OnScanPreviewClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        await runner.RunAsync(preview: true);
    }

    private async void OnScanStartClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        await runner.RunAsync(preview: false);
    }
}
