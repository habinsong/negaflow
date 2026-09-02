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

    /// <summary>
    /// 설정 · 일반의 개발자 모드입니다. 부분 보정(닷지·번)은 화면에 아무것도 그려지지 않아
    /// 이 값이 켜졌을 때만 냅니다.
    /// </summary>
    internal bool developerMode;
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
    internal readonly DevelopInspectorHeader inspectorHeader;
    // macOS `pickFilmBase` 가 Task 로 샘플하는 동안 피커를 먼저 끕니다. 그 사이
    // onChange 가 현상본을 요청하면 샘플과 렌더가 겹치고, 취소된 렌더가 빈 캔버스를 남깁니다.
    private bool basePickInFlight;
    private string? presentedFrameId;
    private long frameEditRefreshGeneration;

    public DevelopWorkspaceView()
    {
        using (Diagnostics.StartupTrace.Measure("DevelopWorkspaceView.xaml"))
        {
            InitializeComponent();
        }
        frames = new DevelopFrameList(this);
        inspectorChrome = new DevelopInspectorChrome(this);
        inspectorSync = new DevelopInspectorSync(this);
        layout = new DevelopWorkspaceLayout(this);
        autoAdjust = new DevelopAutoAdjustActions(this);
        cropSession = new DevelopCropSession(this);
        copy = new DevelopWorkspaceCopy(this);
        inspectorHeader = new DevelopInspectorHeader(this);
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
        // macOS `basePickerOverlay` 는 결함 도구보다 위에 놓입니다 — 스포이드가 켜져 있으면
        // 클릭이 먼저 여기로 옵니다.
        // macOS 는 부분 보정을 켜면 다른 캔버스 도구를 모두 끄므로, 켜져 있을 때는 이쪽이
        // 먼저 포인터를 받습니다.
        PreviewCanvas.TryHandlePointerPressed = args =>
            TryHandleLocalAdjustment(args, LocalPointerPhase.Pressed) ||
            TryHandleBasePick(args) ||
            GrainMendPanel.TryHandlePointerPressed(args);
        BaseCard.BasePickerModeChanged += (_, _) =>
        {
            if (BaseCard.IsBasePickerActive)
            {
                ExitCanvasToolsForBasePicker();
            }
            PreviewCanvas.ShowBasePickerPrompt(BaseCard.IsBasePickerActive);
            // macOS `onChange(of: basePickerMode)` — 켜면 Raw, 끄면 현상본.
            if (previewCoordinator is not null)
            {
                previewCoordinator.UninvertedSource =
                    BaseCard.IsBasePickerActive ||
                    panel?.Compare.ActiveMode == CanvasCompareMode.Raw;
            }
            // 집기 중이면 샘플이 끝난 뒤 ApplyPickedFilmBase 가 한 번만 요청합니다.
            if (!basePickInFlight)
            {
                RequestPreview();
            }
        };
        BaseCard.ManualBaseResetRequested += (_, _) => ResetManualBase();
        PreviewCanvas.TryHandlePointerMoved = args =>
            TryHandleLocalAdjustment(args, LocalPointerPhase.Moved) ||
            GrainMendPanel.TryHandlePointerMoved(args);
        PreviewCanvas.TryHandlePointerReleased = args =>
            TryHandleLocalAdjustment(args, LocalPointerPhase.Released) ||
            GrainMendPanel.TryHandlePointerReleased(args);
        PreviewCanvas.LocalAdjustmentFinishPolygonRequested += (_, _) =>
        {
            LocalAdjustmentCard.CanvasInput.FinishPolygon();
            SyncLocalAdjustmentPrompt();
        };
        PreviewCanvas.LocalAdjustmentCloseRequested += (_, _) =>
        {
            LocalAdjustmentCard.StopDrawing();
            SyncLocalAdjustmentPrompt();
        };
        PreviewCanvas.HandlePointerCancelled = GrainMendPanel.HandlePointerCancelled;
        PreviewCanvas.TryHandleKeyDown = GrainMendPanel.TryHandleKeyDown;
        PreviewCanvas.HostSizeChanged += (_, _) => GrainMendPanel.RenderGuidedSelection();
        inspectorChrome.Apply();
        copy.Localize();
    }

    public event EventHandler? QuickExportAvailabilityChanged;

    /// <summary>출력 패널이 알린 진행입니다. 위 막대가 같은 값을 보여 줍니다.</summary>
    public event EventHandler<Negaflow.Shell.Develop.ExportProgress>? ExportProgressChanged;

    /// <summary>언어가 바뀌면 문구를 다시 겁니다.</summary>
    public void Localize()
    {
        copy.Localize();
        // 진행 카드의 단계 이름과 상태줄도 리소스에서 옵니다.
        ScanProgress.Localize();
    }

    /// <summary>macOS의 스캐너 가져오기 명령을 공유 Library 소스에 요청합니다.</summary>
    public event EventHandler? ScannerSetupRequested;

    public bool CanQuickExport => panel?.CanExport == true;

    /// <summary>
    /// macOS <c>canExportSelection</c> = <c>canQuickExportSelection</c> 에 이름 규칙이
    /// 올바른지를 더한 것입니다(<c>AppModel+BatchExport.swift:7-9</c>).
    /// </summary>
    public bool CanExportPhoto =>
        CanQuickExport &&
        ExportNamingTemplate.IsValid(LeftPanel.ExportPanel.Settings.NamingTemplate);

    public void Initialize(
        WorkspacePresentationState state,
        NativeEngineStatus nativeEngineStatus)
    {
        ArgumentNullException.ThrowIfNull(state);
        ArgumentNullException.ThrowIfNull(nativeEngineStatus);
        workspaceState = state;
        // 하단바가 필름스트립의 크기·차례·범위를 정합니다. 바뀌면 목록을 다시 냅니다.
        StatusBar.Attach(state);
        StatusBar.FilmstripPresentationChanged += (_, _) => frames.Refresh();
        state.Changed += OnStateChanged;
        Filmstrip.Initialize(state);
        GrainMendPanel.Attach(
            state,
            crop,
            PreviewCanvas,
            cropSession.End,
            ExitCanvasToolsForRegionDefect,
            text => ExportStatusText.Text = text,
            RequestPreview,
            RequestPreviewReplacingCurrent);
        LeftPanel.Attach(state);
        LeftPanel.ExportPanel.RunQuickExport = QuickExportAsync;
        LeftPanel.ExportPanel.ProgressChanged +=
            (_, progress) => ExportProgressChanged?.Invoke(this, progress);
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
            libraryHost.SelectionChanged -= OnLibrarySelectionChangedForFlatbed;
            libraryHost.InfraredCleanStatusChanged -= OnInfraredCleanStatusChanged;
        }
        libraryHost = host;
        // 격자에서 고른 장수가 바뀌면 내보내기 단추의 이름도 따라갑니다.
        host.SelectionChanged += frames.OnLibrarySelectionChanged;
        // 평판 프레임 사각형은 **그 프리뷰 사진에서만** 보여야 합니다. 사진을 넘길 때
        // 다시 판정하지 않으면 옛 사각형이 다음 사진 위에 그대로 남습니다.
        host.SelectionChanged += OnLibrarySelectionChangedForFlatbed;
        host.InfraredCleanStatusChanged += OnInfraredCleanStatusChanged;
        panel = new DevelopPanelState(host, limits, negativeLimits);
        PreviewCanvas.AttachViewport(panel.Viewport);
        PreviewCanvas.AttachCompare(panel.Compare, OnCompareModeChosen, OnCompareBeforeChosen);
        PreviewCanvas.SetCompareFrameOptions(CompareFrameOptions());
        GrainMendPanel.Bind(panel);
        LeftPanel.Bind(panel, host, windowId, engineVersion);
        InfoCards.Bind(panel, host);
        Adjustments.Bind(panel);
        Adjustments.DebugStateChanged += OnDebugStateChanged;
        BaseCard.Bind(panel);
        LocalAdjustmentCard.Bind(panel);
        LocalAdjustmentCard.AdjustmentsChanged += (_, _) => RequestPreview();
        LocalAdjustmentCard.DrawingToggled += OnLocalAdjustmentDrawingToggled;
        LocalAdjustmentCard.PromptChanged += (_, _) => SyncLocalAdjustmentPrompt();
        // 사용자 프리셋은 카탈로그가 아니라 앱 설정 옆에 삽니다. macOS 의 UserDefaults 자리입니다.
        panel.OpenUserPresets(Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Negaflow",
            "Development",
            "user-presets.json"));
        Adjustments.ConfigureRanges(
            panel.Tone.MaximumExposureStops,
            panel.Tone.MaximumToneControl,
            panel.Tone.MaximumEndpointToneControl);
        HistogramView.ConfigureRanges(panel.Tone.MaximumExposureStops, panel.Tone.MaximumToneControl);
        BaseCard.ConfigureRanges();
        GeometryCard.ConfigureRanges();
        // 미리보기는 캔버스에 맞는 크기면 충분합니다. 전체 해상도로 그리면 슬라이더를 끄는
        // 동안 엔진이 밀립니다.
        // 이 메서드는 UI 스레드에서만 불리므로 여기서 dispatcher 를 잡을 수 있습니다.
        if (DispatcherQueueUiDispatcher.CaptureForCurrentThread() is { } uiDispatcher)
        {
            PreviewTrace.Write("ShowLibrary coordinator created");
            previewCoordinator = new PreviewCoordinator(
                new NativeDevelopExporterAdapter(),
                uiDispatcher,
                DisplayTargetPixels);
            previewCoordinator.ClippingOverlayEnabled =
                workspaceState?.Current.ClippingOverlayEnabled == true;
            GrainMendPanel.SetDetectCoordinator(new GrainMendDetectCoordinator(
                new NativeDevelopExporterAdapter(),
                uiDispatcher));
            autoAdjustCoordinator = new AutoAdjustCoordinator(
                new NativeDevelopExporterAdapter(),
                uiDispatcher);
        }
        else
        {
            PreviewTrace.Write("ShowLibrary coordinator NOT created — no DispatcherQueue");
        }
        frames.Refresh();
    }

    public void SelectFrame(string frameId) => frames.Select(frameId);

    /// <summary>
    /// macOS 는 <c>AppModel</c> 하나가 스캐너를 들고, 라이브러리 사이드바와 현상 사이드바가
    /// 같은 <c>LibrarySourceSection</c> 을 냅니다. 여기서 그 한 벌을 물려받습니다.
    /// </summary>
    public void AttachScanSessionHost(Views.Library.Scanner.ScanSessionHost host)
    {
        LeftPanel.AttachScanSessionHost(host);
        AttachFlatbedOverlay(host);
        host.BindGrainMendCarryover(
            GrainMendPanel.CaptureScannerPreviewCarryover,
            QueueScannerGuidedCarryover);
    }

    /// <summary>
    /// 라이브러리에서 카탈로그가 바깥에서 바뀌었을 때 현상뷰를 그 값으로 다시 맞춥니다.
    /// </summary>
    /// <remarks>
    /// macOS 는 <c>ScanFrame</c> 이 <c>ObservableObject</c> 라 폴더 일괄 적용이 파라미터를
    /// 바꾸는 순간 현상뷰가 저절로 따라옵니다. WinUI 에는 그런 관찰이 없어 현상뷰가 열릴 때
    /// 읽은 스냅샷에 머물렀습니다 — <b>프로세스와 타깃을 바꾸고 적용을 눌러도 현상뷰가 옛
    /// 값을 보이던 원인</b>이 이것입니다. <see cref="DevelopFrameList.Refresh"/> 는 목록을
    /// 다시 만들고 고른 프레임을 다시 활성화하므로 좌측탭 기본값·인스펙터·미리보기가 한
    /// 번에 새 값으로 갑니다.
    /// </remarks>
    public void ReloadFrames() => frames.Refresh();

    public void NotifyFrameEdited() => _ = NotifyFrameEditedAsync();

    /// <summary>
    /// 별·깃발·제외가 바뀌었습니다. 하단 필름스트립의 표시만 맞춥니다.
    /// </summary>
    internal void RefreshFrameMarks()
    {
        if (libraryHost is { } host)
        {
            Filmstrip.RefreshFrames(host.Frames);
        }
    }

    private async Task NotifyFrameEditedAsync()
    {
        long generation = checked(++frameEditRefreshGeneration);
        if (libraryHost is not { } host || panel?.SelectedFrame is not { } selected ||
            host.Frames.FirstOrDefault(candidate =>
                string.Equals(candidate.Id, selected.Id, StringComparison.Ordinal)) is not { } current ||
            ReferenceEquals(selected, current))
        {
            return;
        }

        // **별·깃발·제외는 현상 레시피가 아닙니다.** 그것만 바뀌었으면 목록을 다시 지을
        // 이유가 없습니다 — 다시 지으면 좌측 트리 둘이 다시 서고 썸네일이 전부 다시
        // 디코드되며, 별을 누를 때마다 눈에 보이게 멈춥니다. 표시는 셸의 `FrameEdited` 가
        // 항목 객체에서 그 자리에 맞췄고(`RefreshFrameMarks`), 여기서는 스냅샷만 지금 것으로
        // 갈아 끼웁니다. 그러지 않으면 사이드카가 옛 별점을 적습니다.
        bool sameRecipe = await GrainMendDetectionToken.SameDevelopRecipeAsync(selected, current);
        if (generation != frameEditRefreshGeneration ||
            !ReferenceEquals(panel?.SelectedFrame, selected) ||
            libraryHost is not { } currentHost ||
            !ReferenceEquals(
                currentHost.Frames.FirstOrDefault(candidate =>
                    string.Equals(candidate.Id, current.Id, StringComparison.Ordinal)),
                current))
        {
            return;
        }
        if (sameRecipe)
        {
            _ = panel.RefreshSelectedFrame();
            return;
        }
        frames.Refresh();
    }

    internal void RaiseScannerSetupRequested() =>
        ScannerSetupRequested?.Invoke(this, EventArgs.Empty);

    internal void NotifyQuickExportAvailabilityChanged() =>
        QuickExportAvailabilityChanged?.Invoke(this, EventArgs.Empty);

    internal void SynchronizeInspectorValues() => inspectorSync.Synchronize();

    internal void SyncBaseControls() => inspectorSync.SyncBase();

    internal void SyncToneControls() => inspectorSync.SyncTone();

    internal void UpdateImageTransform(Func<DevelopPanelState, LibraryFrameError> update) =>
        inspectorSync.UpdateImageTransform(update);

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
        // 베이스 모드는 거절 사유가 아닙니다. 수동에 고른 값이 없어도, preset 에 필름을
        // 고르지 않았어도 macOS 는 자동 추정으로 현상합니다
        // (`ChromabaseEngine+NegativePipeline.resolveFilmBase`, `DevelopRequestFactory` 의 같은 자리).
        return DevelopRequestRefusal.None;
    }

    /// <summary>
    /// macOS <c>quickExportSelection()</c> — 도구막대 명령과 좌측탭 단추가 같은 길입니다.
    /// </summary>
    /// <remarks>
    /// 예전에는 여기서 따로 한 장만 내보내고 상태를 캔버스 줄에 적었습니다. 그래서 좌측탭
    /// 단추를 눌러도 <b>패널 안에는 아무 표시가 나지 않았고</b>, 여러 장을 골라도 한 장만
    /// 나갔습니다. macOS 는 둘 다 <c>quickExportSelection</c> 하나이므로 여기서도 패널이
    /// 들고 있는 그 하나를 부릅니다.
    /// </remarks>
    public async Task QuickExportAsync()
    {
        if (panel?.SelectedFrame is null)
        {
            return;
        }
        NotifyQuickExportAvailabilityChanged();
        await LeftPanel.ExportPanel.runner.RunQuickExportAsync();
        NotifyQuickExportAvailabilityChanged();
    }

    /// <summary>macOS <c>exportSelectionToFolder</c> — 출력 패널이 정한 폴더·형식입니다.</summary>
    public Task ExportPhotoAsync()
    {
        return LeftPanel.ExportPanel.runner.RunExportAsync();
    }

    internal bool TryExitGrainMendInteraction() =>
        GrainMendPanel.TryExitRegionDefectInteraction();

    internal async Task PrepareForTerminationAsync()
    {
        Task grainMendDrain = GrainMendPanel.PrepareForTerminationAsync();
        Task previewDrain = previewCoordinator?.CancelAndDrainAsync() ?? Task.CompletedTask;
        await Task.WhenAll(grainMendDrain, previewDrain);
    }

    private void OnThumbnailReady(string frameId) => frames.OnThumbnailReady(frameId);

    private void OnStateChanged(object? sender, ShellPreferences preferences)
    {
        _ = sender;
        layout.Update(preferences);
        if (previewCoordinator is { } coordinator &&
            coordinator.ClippingOverlayEnabled != preferences.ClippingOverlayEnabled)
        {
            coordinator.ClippingOverlayEnabled = preferences.ClippingOverlayEnabled;
            RequestPreview();
        }
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
