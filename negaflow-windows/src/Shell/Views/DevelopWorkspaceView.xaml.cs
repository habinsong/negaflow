using System.IO;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Develop.Host;
using Negaflow.Shell.Views.Layout;

namespace Negaflow.Shell.Views;

public sealed partial class DevelopWorkspaceView : UserControl
{
    internal readonly ThreePaneResizeController resizeController = new();
    internal readonly DevelopInspectorPresentationState inspectorPresentation = new();
    internal WorkspacePresentationState? workspaceState;
    internal DevelopPanelState? panel;
    internal LibraryHostService? libraryHost;
    internal PreviewCoordinator? previewCoordinator;
    internal SoftProofPreferences softProofPreferences = new();
    internal AutoAdjustCoordinator? autoAdjustCoordinator;
    internal bool isSynchronizingInspector;
    internal bool isSynchronizingFrameSelection;
    internal bool isSynchronizingInspectorPresentation;
    internal bool isInspectorPresentationReady;
    internal Negaflow.Shell.Library.ThumbnailService? thumbnails;
    internal string engineVersion = "unknown";
    internal readonly CropWorkspaceState crop = new();
    internal readonly DevelopFrameList frames;
    internal readonly DevelopInspectorChrome inspectorChrome;
    internal readonly DevelopInspectorSync inspectorSync;
    internal readonly DevelopWorkspaceLayout layout;
    internal readonly DevelopAutoAdjustActions autoAdjust;
    internal readonly DevelopCropSession cropSession;
    internal readonly DevelopWorkspaceCopy copy;

    public DevelopWorkspaceView()
    {
        InitializeComponent();
        frames = new DevelopFrameList(this);
        inspectorChrome = new DevelopInspectorChrome(this);
        inspectorSync = new DevelopInspectorSync(this);
        layout = new DevelopWorkspaceLayout(this);
        autoAdjust = new DevelopAutoAdjustActions(this);
        cropSession = new DevelopCropSession(this);
        copy = new DevelopWorkspaceCopy(this);
        isInspectorPresentationReady = true;
        frames.Hook();
        inspectorChrome.Hook();
        inspectorSync.Hook();
        layout.Hook();
        autoAdjust.Hook();
        cropSession.Hook();
        PreviewCanvas.Attach(crop);
        PreviewCanvas.BindSampler(
            () => workspaceState?.Current.PixelSamplerEnabled == true,
            () => panel?.SelectedFrame?.SourcePath,
            () => softProofPreferences.IsEnabled);
        PreviewCanvas.TryHandlePointerPressed = GrainMendPanel.TryHandlePointerPressed;
        PreviewCanvas.TryHandlePointerMoved = GrainMendPanel.TryHandlePointerMoved;
        PreviewCanvas.TryHandlePointerReleased = GrainMendPanel.TryHandlePointerReleased;
        PreviewCanvas.HandlePointerCancelled = GrainMendPanel.HandlePointerCancelled;
        PreviewCanvas.TryHandleKeyDown = GrainMendPanel.TryHandleKeyDown;
        PreviewCanvas.HostSizeChanged += (_, _) => GrainMendPanel.RenderGuidedSelection();
        inspectorChrome.Apply();
        copy.Localize();
    }

    public event EventHandler? QuickExportAvailabilityChanged;

    /// <summary>macOS의 스캐너 가져오기 명령을 공유 Library 소스에 요청합니다.</summary>
    public event EventHandler? ScannerSetupRequested;

    public bool CanQuickExport => panel?.CanExport == true;

    public void Initialize(
        WorkspacePresentationState state,
        NativeEngineStatus nativeEngineStatus)
    {
        ArgumentNullException.ThrowIfNull(state);
        ArgumentNullException.ThrowIfNull(nativeEngineStatus);
        workspaceState = state;
        state.Changed += OnStateChanged;
        Filmstrip.Initialize(state);
        GrainMendPanel.Attach(
            state,
            crop,
            PreviewCanvas,
            cropSession.End,
            text => ExportStatusText.Text = text,
            RequestPreview);
        LeftPanel.Attach(state);
        LeftPanel.ExportPanel.RunQuickExport = QuickExportAsync;
        StatusBar.Initialize(nativeEngineStatus);
        engineVersion = nativeEngineStatus.BuildInfo?.AbiVersion.ToString() ?? "unknown";
        layout.Update(state.Current);
        Unloaded += OnUnloaded;
    }

    /// <summary>
    /// 정착한 미리보기를 라이브러리 썸네일로 넘겨줄 서비스입니다.
    /// </summary>
    public void AttachThumbnails(Negaflow.Shell.Library.ThumbnailService service)
    {
        ArgumentNullException.ThrowIfNull(service);
        if (thumbnails is not null)
        {
            thumbnails.ThumbnailReady -= OnThumbnailReady;
        }
        thumbnails = service;
        thumbnails.ThumbnailReady += OnThumbnailReady;
    }

    /// <summary>
    /// 라이브러리를 붙입니다. **UI 스레드에서만** 부르십시오. 현상 자체는 워커에서 돌지만
    /// 여기서 만지는 것은 전부 컨트롤입니다.
    /// </summary>
    public void ShowLibrary(
        LibraryHostService host,
        ToneLimits limits,
        NegativeLimits negativeLimits,
        Microsoft.UI.WindowId windowId)
    {
        ArgumentNullException.ThrowIfNull(host);
        ArgumentNullException.ThrowIfNull(limits);
        ArgumentNullException.ThrowIfNull(negativeLimits);

        if (libraryHost is not null)
        {
            libraryHost.SelectionChanged -= frames.OnLibrarySelectionChanged;
        }
        libraryHost = host;
        // 격자에서 고른 장수가 바뀌면 내보내기 단추의 이름도 따라갑니다.
        host.SelectionChanged += frames.OnLibrarySelectionChanged;
        panel = new DevelopPanelState(host, limits, negativeLimits);
        GrainMendPanel.Bind(panel);
        LeftPanel.Bind(panel, host, windowId, engineVersion);
        InfoCards.Bind(panel, host);
        Adjustments.Bind(panel);
        BaseCard.Bind(panel);
        // 사용자 프리셋은 카탈로그가 아니라 앱 설정 옆에 삽니다. macOS 의 UserDefaults 자리입니다.
        panel.OpenUserPresets(Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Negaflow",
            "Development",
            "user-presets.json"));
        Adjustments.ConfigureRanges(panel.Tone.MaximumExposureStops, panel.Tone.MaximumToneControl);
        HistogramView.ConfigureRanges(panel.Tone.MaximumExposureStops, panel.Tone.MaximumToneControl);
        BaseCard.ConfigureRanges(panel.MinimumManualDmin, panel.MaximumManualDmin);
        GeometryCard.ConfigureRanges();
        // 미리보기는 캔버스에 맞는 크기면 충분합니다. 전체 해상도로 그리면 슬라이더를 끄는
        // 동안 엔진이 밀립니다.
        // 이 메서드는 UI 스레드에서만 불리므로 여기서 dispatcher 를 잡을 수 있습니다.
        if (DispatcherQueueUiDispatcher.CaptureForCurrentThread() is { } uiDispatcher)
        {
            previewCoordinator = new PreviewCoordinator(
                new NativeDevelopExporterAdapter(),
                uiDispatcher,
                DisplayTargetPixels);
            GrainMendPanel.SetDetectCoordinator(new GrainMendDetectCoordinator(
                new NativeDevelopExporterAdapter(),
                uiDispatcher));
            autoAdjustCoordinator = new AutoAdjustCoordinator(
                new NativeDevelopExporterAdapter(),
                uiDispatcher);
        }
        frames.Refresh();
    }

    public void SelectFrame(string frameId) => frames.Select(frameId);

    internal void RaiseScannerSetupRequested() =>
        ScannerSetupRequested?.Invoke(this, EventArgs.Empty);

    internal void NotifyQuickExportAvailabilityChanged() =>
        QuickExportAvailabilityChanged?.Invoke(this, EventArgs.Empty);

    internal void SynchronizeInspectorValues() => inspectorSync.Synchronize();

    internal void SyncBaseControls() => inspectorSync.SyncBase();

    internal void SyncToneControls() => inspectorSync.SyncTone();

    internal void UpdateImageTransform(Func<DevelopPanelState, LibraryFrameError> update) =>
        inspectorSync.UpdateImageTransform(update);

    /// <summary>
    /// 현재 선택을 미리보기로 그립니다. 겹쳐 들어온 요청은 coordinator 가 합치되 마지막 것은
    /// 반드시 그리므로, 슬라이더를 끌어도 최종 상태가 화면에 남습니다.
    /// </summary>
    internal void RequestPreview()
    {
        // 레이어 강도를 끄는 동안에는 아직 저장하지 않은 값을 얹은 사본을 그립니다 — 저장은
        // 원본 파일 전체를 다시 해싱하므로 드래그 중에 하면 슬라이더가 멈춥니다.
        if (previewCoordinator is null || panel?.DefectLayers.PreviewFrame is not { } frame)
        {
            return;
        }
        _ = previewCoordinator.RequestAsync(frame, ShowPreview);
    }

    /// <summary>
    /// macOS <c>canvasDisplayTargetPixels</c> — 캔버스 긴 변 × DPI 배율입니다.
    /// </summary>
    private double DisplayTargetPixels()
    {
        double scale = PreviewCanvas.XamlRoot?.RasterizationScale ?? 1;
        if (scale <= 0)
        {
            scale = 1;
        }

        return Math.Max(PreviewCanvas.ActualWidth, PreviewCanvas.ActualHeight) * scale;
    }

    private void ShowPreview(PreviewOutcome outcome)
    {
        // 샘플러가 읽을 버퍼는 화면에 그린 것과 같아야 합니다 — 다른 것을 읽으면 보이는 색과
        // 적히는 수가 갈립니다.
        PreviewCanvas.KeepPreviewPixels(outcome.Pixels, outcome.Width, outcome.Height);
        if (outcome.Kind != DevelopExportOutcomeKind.Completed ||
            outcome.Pixels is not { } pixels ||
            outcome.Width == 0U ||
            outcome.Height == 0U)
        {
            PreviewCanvas.ShowEmpty();
            HistogramView.Clear();
            // 현상이 실패한 것과 사진이 없는 것은 다릅니다. 같은 빈 화면만 내면 사용자는
            // 사진을 넣으라는 말을 다시 읽을 뿐이고, 무엇이 잘못됐는지 알 길이 없습니다.
            string reason = outcome.Kind == DevelopExportOutcomeKind.Completed
                ? $"{outcome.Result?.FailedStage} {outcome.Result?.FailureName}"
                : outcome.Refusal.ToString();
            ExportStatusText.Text =
                $"{AppResources.Get("developPreviewFailed", "Text")} ({reason})";
            return;
        }

        int width = (int)outcome.Width;
        int height = (int)outcome.Height;
        PreviewCanvas.Present(pixels, width, height);
        HistogramView.UpdatePixels(pixels, width, height);
        // 방금 현상한 그림이 곧 라이브러리 카드의 썸네일입니다. 같은 픽셀을 두 번 만들지
        // 않으려고 여기서 넘깁니다.
        if (panel?.SelectedFrame is { } settled)
        {
            thumbnails?.Publish(settled.Id, pixels, width, height);
        }

        crop.MarkPreviewReady();
        PreviewCanvas.RenderCropOverlay();
    }

    internal static DevelopRequestRefusal RefusalFor(LibraryFrameSnapshot frame)
    {
        if (frame.Route.FilmLookSource != FilmLookSource.FilmScan)
        {
            return DevelopRequestRefusal.UnsupportedDigitalSource;
        }
        if (frame.Route.FilmType is not (FilmType.ColorNegative or FilmType.BlackAndWhiteNegative))
        {
            return DevelopRequestRefusal.UnsupportedPositiveFilm;
        }
        return frame.Base.Mode switch
        {
            BaseEstimationMode.Preset when string.IsNullOrWhiteSpace(frame.Base.FilmStockDminId) =>
                DevelopRequestRefusal.MissingFilmStock,
            BaseEstimationMode.Manual when frame.ManualBase is null => DevelopRequestRefusal.MissingManualBase,
            _ => DevelopRequestRefusal.None,
        };
    }

    public async Task QuickExportAsync()
    {
        if (panel?.SelectedFrame is not { } frame)
        {
            return;
        }

        // 편집은 메모리에만 있었으므로, 현상하기 전에 저장해 파일과 catalog 가 어긋나지 않게 합니다.
        CatalogStoreError saved = panel.Save();
        if (saved != CatalogStoreError.None)
        {
            ExportStatusText.Text = AppResources.Get("developExportSaveFailed", "Text");
            return;
        }

        ExportStatusText.Text = AppResources.Get("developExportRunning", "Text");
        Task<bool> exportTask = panel.ExportAsync(
            LeftPanel.ExportPanel.QuickSettings.Destination.PathFor(frame.SourcePath),
            LeftPanel.ExportPanel.QuickSettings.Format,
            outcome => ExportStatusText.Text = DevelopPanelState.Describe(outcome),
            LeftPanel.ExportPanel.QuickSettings.Encoding);
        NotifyQuickExportAvailabilityChanged();
        bool delivered = await exportTask;
        if (!delivered)
        {
            // 큐가 닫혔다는 뜻이므로 창이 사라지는 중입니다. 컨트롤을 더 건드리지 않습니다.
            return;
        }
        NotifyQuickExportAvailabilityChanged();
    }

    /// <summary>
    /// 고른 프로파일의 용지 흰색과 잉크 검정을 미리보기에 겁니다.
    /// </summary>
    /// <remarks>
    /// 목적지는 현상 대상이 정합니다 — PRINT 로 현상할 때는 프린터 출력 프로파일이 목적지이며,
    /// 그래야 프루프가 화면이 아니라 인화될 종이를 보여 줍니다. 프로파일을 읽지 못하면 용지·
    /// 잉크를 흉내 내지 않습니다: 없는 값을 지어내느니 프로파일만 보는 쪽이 정직합니다.
    /// </remarks>
    internal void ApplySoftProof()
    {
        if (previewCoordinator is not { } coordinator)
        {
            return;
        }
        DevelopTarget target = panel?.SelectedFrame?.DevelopTarget ?? DevelopTarget.Main;
        coordinator.SoftProof = softProofPreferences.ToSettings(
            SoftProofProfileReader.Read(softProofPreferences.DestinationProfilePath(target)));
        RequestPreview();
    }

    private void OnThumbnailReady(string frameId) => frames.OnThumbnailReady(frameId);

    private void OnStateChanged(object? sender, ShellPreferences preferences)
    {
        _ = sender;
        layout.Update(preferences);
    }

    private void OnUnloaded(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        cropSession.Cancel();
        if (workspaceState is not null)
        {
            workspaceState.Changed -= OnStateChanged;
        }
    }
}
