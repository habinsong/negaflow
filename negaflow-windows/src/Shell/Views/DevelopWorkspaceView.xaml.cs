using System.Text.Json.Nodes;
using System.IO;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Input;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Controls;
using Negaflow.Shell.Views.Develop.Inspector;
using Negaflow.Shell.Views.Layout;
using Windows.System;
using Windows.UI.Core;

namespace Negaflow.Shell.Views;

public sealed partial class DevelopWorkspaceView : UserControl
{
    private readonly ThreePaneResizeController resizeController = new();
    private readonly DevelopInspectorPresentationState inspectorPresentation = new();
    private WorkspacePresentationState? workspaceState;
    private DevelopPanelState? panel;
    private LibraryHostService? libraryHost;
    private ToneLimits? toneLimits;
    private PreviewCoordinator? previewCoordinator;
    private SoftProofPreferences softProofPreferences = new();
    private AutoAdjustCoordinator? autoAdjustCoordinator;
    private bool isSynchronizingInspector;
    private bool isSynchronizingFrameSelection;
    private bool isSynchronizingInspectorPresentation;
    private bool isInspectorPresentationReady;
    private Negaflow.Shell.Library.ThumbnailService? thumbnails;
    private GrainMendDetectCoordinator? grainMendDetectCoordinator;
    private string engineVersion = "unknown";
    private readonly CropWorkspaceState crop = new();
    private CropDisplayPoint guidedDefectDragStart;
    private CropDisplayPoint guidedDefectDragCurrent;
    private bool guidedDefectDragging;
    private readonly GrainMendWorkspaceState grainMend = new();

    public DevelopWorkspaceView()
    {
        InitializeComponent();
        isInspectorPresentationReady = true;
        DefectLayers.Command += OnDefectLayerCommand;
        LeftPanel.FrameSelected += OnSourceFrameSelected;
        LeftPanel.FramesImported += OnSourceFramesImported;
        LeftPanel.ScannerSetupRequested += OnSourceScannerSetupRequested;
        Adjustments.PreviewRequested += OnAdjustmentsPreviewRequested;
        Adjustments.RefreshRequested += OnAdjustmentsRefreshRequested;
        Adjustments.ResetRequested += OnAdjustmentsResetRequested;
        Adjustments.SectionToggleRequested += OnAdjustmentSectionToggle;
        Adjustments.SectionExpansionRequested += OnAdjustmentSectionExpansion;
        Adjustments.AutoColorToggled += OnAdjustmentAutoColorToggled;
        Adjustments.AutoLevelsToggled += OnAdjustmentAutoLevelsToggled;
        Adjustments.AutoToneClicked += OnAdjustmentAutoToneClicked;
        Adjustments.AutoWhiteBalanceClicked += OnAdjustmentAutoWhiteBalanceClicked;
        BaseCard.RecipeChanged += OnBaseRecipeChanged;
        BaseCard.ManualBaseCommitted += OnManualBaseCommitted;
        GeometryCard.CropClicked += OnGeometryCropClicked;
        GeometryCard.TransformRequested += OnGeometryTransformRequested;
        GeometryCard.AspectChosen += OnGeometryAspectChosen;
        GeometryCard.AspectLockToggled += OnGeometryAspectLockToggled;
        PreviewCanvas.Attach(crop);
        PreviewCanvas.BindSampler(
            () => workspaceState?.Current.PixelSamplerEnabled == true,
            () => panel?.SelectedFrame?.SourcePath,
            () => softProofPreferences.IsEnabled);
        PreviewCanvas.TryHandlePointerPressed = TryHandleGrainMendPointerPressed;
        PreviewCanvas.TryHandlePointerMoved = TryHandleGrainMendPointerMoved;
        PreviewCanvas.TryHandlePointerReleased = TryHandleGrainMendPointerReleased;
        PreviewCanvas.HandlePointerCancelled = EndGuidedDefectSelection;
        PreviewCanvas.TryHandleKeyDown = TryHandleGrainMendKeyDown;
        PreviewCanvas.CropApplyRequested += OnCropApplyClicked;
        PreviewCanvas.CropCancelRequested += OnCropCancelClicked;
        PreviewCanvas.CropFullRequested += OnCropFullClicked;
        PreviewCanvas.HostSizeChanged += OnPreviewCanvasSizeChanged;
        ApplyInspectorPresentation();
        LocalizeControls();
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
        Filmstrip.FrameSelected += OnFilmstripFrameSelected;
        LeftPanel.Attach(state);
        LeftPanel.ExportPanel.RunQuickExport = QuickExportAsync;
        StatusBar.Initialize(nativeEngineStatus);
        engineVersion = nativeEngineStatus.BuildInfo?.AbiVersion.ToString() ?? "unknown";
        UpdateState(state.Current);
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
            libraryHost.SelectionChanged -= OnLibrarySelectionChanged;
        }
        libraryHost = host;
        // 격자에서 고른 장수가 바뀌면 내보내기 단추의 이름도 따라갑니다.
        host.SelectionChanged += OnLibrarySelectionChanged;
        toneLimits = limits;
        panel = new DevelopPanelState(host, limits, negativeLimits);
        LeftPanel.Bind(panel, host, windowId, engineVersion);
        InfoCards.Bind(panel, host);
        Adjustments.Bind(panel);
        BaseCard.Bind(panel);
        LeftPanel.VersionsPanel.VersionRestored += OnVersionRestored;
        LeftPanel.PresetsPanel.RecipeReplaced += OnPresetRecipeReplaced;
        LeftPanel.FilmLookPanel.LookChanged += OnFilmLookChanged;
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
                1600,
                1200);
            grainMendDetectCoordinator = new GrainMendDetectCoordinator(
                new NativeDevelopExporterAdapter(),
                uiDispatcher);
            autoAdjustCoordinator = new AutoAdjustCoordinator(
                new NativeDevelopExporterAdapter(),
                uiDispatcher);
        }
        RefreshFrames();
    }

    private void RefreshFrames()
    {
        if (libraryHost is null)
        {
            return;
        }

        IReadOnlyList<LibraryFrameListItem> items =
            LibraryFrameListItems.From(libraryHost.Frames);
        bool hasFrames = items.Count > 0;
        FramePanel.Visibility = hasFrames ? Visibility.Visible : Visibility.Collapsed;
        NoFrameLeftPanel.Visibility = hasFrames ? Visibility.Collapsed : Visibility.Visible;
        NoFrameCard.Visibility = hasFrames ? Visibility.Collapsed : Visibility.Visible;
        DevelopInspectorContent.Visibility = hasFrames ? Visibility.Visible : Visibility.Collapsed;
        if (!hasFrames)
        {
            LeftPanel.SetHeaderTitle(AppResources.Get("noFrame", "Text"));
            FrameSelector.ItemsSource = null;
            Filmstrip.ShowFrames([], -1);
            HistogramView.Clear();
            LeftPanel.RebuildLibraryTree();
            SyncToneControls();
            NotifyQuickExportAvailabilityChanged();
            return;
        }

        int selectedIndex = IndexOf(items, libraryHost.ActiveFrameId);
        if (selectedIndex < 0)
        {
            selectedIndex = 0;
        }
        isSynchronizingFrameSelection = true;
        try
        {
            FrameSelector.ItemsSource = items;
            FrameSelector.SelectedIndex = selectedIndex;
            // 필름스트립과 왼쪽 목록은 같은 항목을 봅니다. 썸네일이 도착하면 둘 다 채워집니다.
            LeftPanel.RebuildLibraryTree();
            Filmstrip.ShowFrames(items, selectedIndex);
        }
        finally
        {
            isSynchronizingFrameSelection = false;
        }
        ActivateFrame(items[selectedIndex], selectedIndex, publishSelection: false);
        foreach (LibraryFrameListItem item in items)
        {
            if (thumbnails?.TryGet(item.Id) is not null)
            {
                continue;
            }
            thumbnails?.Request(item.Frame);
        }
    }

    private void OnFilmstripFrameSelected(object? sender, LibraryFrameListItem item)
    {
        _ = sender;
        SelectFrame(item.Id);
    }

    /// <summary>
    /// 라이브러리에서 넘어온 frame 을 고릅니다. 목록에 없으면 아무 것도 바꾸지 않습니다 —
    /// 방금 지워진 frame 때문에 보고 있던 사진이 바뀌지 않게 합니다.
    /// </summary>
    public void SelectFrame(string frameId)
    {
        ArgumentException.ThrowIfNullOrEmpty(frameId);
        if (FrameSelector.ItemsSource is not IReadOnlyList<LibraryFrameListItem> current)
        {
            return;
        }
        for (int index = 0; index < current.Count; ++index)
        {
            if (string.Equals(current[index].Id, frameId, StringComparison.Ordinal))
            {
                FrameSelector.SelectedIndex = index;
                return;
            }
        }
    }

    private void OnThumbnailReady(string frameId)
    {
        if (FrameSelector.ItemsSource is not IReadOnlyList<LibraryFrameListItem> current ||
            thumbnails?.TryGet(frameId) is not { } jpeg)
        {
            return;
        }
        foreach (LibraryFrameListItem item in current)
        {
            if (string.Equals(item.Id, frameId, StringComparison.Ordinal))
            {
                item.Thumbnail = LibraryWorkspaceView.DecodeThumbnail(jpeg);
                return;
            }
        }
    }

    private void OnInspectorTabClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (!isInspectorPresentationReady ||
            isSynchronizingInspectorPresentation ||
            sender is not ToggleButton { Tag: string tag } ||
            !Enum.TryParse(tag, out DevelopInspectorTab tab))
        {
            return;
        }

        if (tab != DevelopInspectorTab.Edit)
        {
            CancelCrop();
        }

        inspectorPresentation.SelectTab(tab);
        ApplyInspectorPresentation();
    }

    private void OnAdjustmentSectionToggle(object? sender, DevelopInspectorSection section)
    {
        _ = sender;
        if (!isInspectorPresentationReady || isSynchronizingInspectorPresentation)
        {
            return;
        }

        if (inspectorPresentation.ExpandedSection == section)
        {
            inspectorPresentation.Collapse(section);
        }
        else
        {
            inspectorPresentation.Expand(section);
        }
        ApplyInspectorPresentation();
    }

    private void OnAdjustmentSectionExpansion(
        object? sender,
        DevelopInspectorSectionExpansion request)
    {
        _ = sender;
        if (!isInspectorPresentationReady || isSynchronizingInspectorPresentation)
        {
            return;
        }

        if (request.IsExpanded)
        {
            inspectorPresentation.Expand(request.Section);
        }
        else
        {
            inspectorPresentation.Collapse(request.Section);
        }
        ApplyInspectorPresentation();
    }

    private void ApplyInspectorPresentation()
    {
        if (!isInspectorPresentationReady)
        {
            return;
        }

        isSynchronizingInspectorPresentation = true;
        BasicTabButton.IsChecked = inspectorPresentation.SelectedTab == DevelopInspectorTab.Basic;
        BaseTabButton.IsChecked = inspectorPresentation.SelectedTab == DevelopInspectorTab.Base;
        EditTabButton.IsChecked = inspectorPresentation.SelectedTab == DevelopInspectorTab.Edit;
        DefectsTabButton.IsChecked = inspectorPresentation.SelectedTab == DevelopInspectorTab.Defects;
        InfoTabButton.IsChecked = inspectorPresentation.SelectedTab == DevelopInspectorTab.Info;
        ResetTabButton.IsChecked = inspectorPresentation.SelectedTab == DevelopInspectorTab.Reset;
        BaseCard.Visibility = inspectorPresentation.SelectedTab == DevelopInspectorTab.Base
            ? Visibility.Visible
            : Visibility.Collapsed;
        InfoCards.Apply(inspectorPresentation.SelectedTab == DevelopInspectorTab.Info);
        GrainMendCard.Visibility = inspectorPresentation.SelectedTab == DevelopInspectorTab.Defects
            ? Visibility.Visible
            : Visibility.Collapsed;
        // 레이어 목록은 GrainMend 카드와 한 탭에 삽니다. macOS 도 같은 인스펙터에 붙습니다.
        DefectLayers.Visibility = GrainMendCard.Visibility;
        if (inspectorPresentation.SelectedTab != DevelopInspectorTab.Defects)
        {
            // 탭을 떠나면 도구도 놓습니다. 보이지 않는 도구가 캔버스를 잡고 있으면
            // 크롭이나 확대가 먹지 않는 것처럼 보입니다.
            SetGrainMendTool(GrainMendTool.None);
        }
        UpdateGrainMendCard();
        UpdateDefectLayers();
        GeometryCard.Visibility = inspectorPresentation.SelectedTab == DevelopInspectorTab.Edit
            ? Visibility.Visible
            : Visibility.Collapsed;
        Adjustments.Apply(inspectorPresentation);
        isSynchronizingInspectorPresentation = false;
    }

    private void OnSourceFrameSelected(object? sender, string frameId)
    {
        _ = sender;
        if (panel is null)
        {
            return;
        }
        panel.Select(frameId);
        SynchronizeInspectorValues();
        RequestPreview();
        LeftPanel.RebuildLibraryTree();
    }

    private void OnSourceFramesImported(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        RefreshFrames();
    }

    private void OnSourceScannerSetupRequested(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        ScannerSetupRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnFrameSelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingFrameSelection || panel is null ||
            FrameSelector.SelectedItem is not LibraryFrameListItem item)
        {
            return;
        }

        ActivateFrame(item, FrameSelector.SelectedIndex, publishSelection: true);
    }

    private void ActivateFrame(
        LibraryFrameListItem item,
        int selectedIndex,
        bool publishSelection)
    {
        if (panel is null)
        {
            return;
        }

        CancelCrop();
        if (publishSelection)
        {
            libraryHost?.SetSelection([item.Id], item.Id);
        }
        panel.Select(item.Id);
        Filmstrip.SynchronizeSelection(selectedIndex);
        LeftPanel.SetHeaderTitle(item.DisplayName);
        UpdateSelectedFrameText();
        SynchronizeInspectorValues();
        SyncBaseControls();
        SyncToneControls();
        NotifyQuickExportAvailabilityChanged();
        ExportStatusText.Text = item.CanDevelop
            ? string.Empty
            : DevelopPanelState.Describe(new DevelopExportOutcome(
                DevelopExportOutcomeKind.Refused,
                null,
                RefusalFor(item.Frame),
                null));
        RequestPreview();
    }

    private static int IndexOf(IReadOnlyList<LibraryFrameListItem> items, string? frameId)
    {
        if (frameId is null)
        {
            return -1;
        }
        for (int index = 0; index < items.Count; ++index)
        {
            if (string.Equals(items[index].Id, frameId, StringComparison.Ordinal))
            {
                return index;
            }
        }
        return -1;
    }

    private void SynchronizeInspectorValues()
    {
        if (panel is null)
        {
            return;
        }

        isSynchronizingInspector = true;
        Adjustments.Show(panel);
        GeometryCard.Show(panel);
        GeometryCard.UpdateAspectControls(panel, crop.IsAspectLocked);
        LeftPanel.FilmLookPanel.Update();
        UpdateVersionControls();
        LeftPanel.PresetsPanel.Update();
        HistogramView.SynchronizeValues(
            panel.Tone.Shadows,
            panel.Tone.Density,
            panel.Tone.Exposure,
            panel.Tone.Highlights);
        // Auto에는 수동 base가 없으므로 slider에는 시작 위치만 보입니다. 사용자가 값을 바꾸면
        // manual mode로 전환되며, 그 전까지 preview/export는 native Auto resolver를 사용합니다.
        BaseCard.ShowManualValues(panel);
        isSynchronizingInspector = false;
    }

    private void OnManualBaseCommitted(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null)
        {
            return;
        }

        // slider 변경은 Auto를 Manual로 전환합니다. 선택 행과 export 상태도 즉시 같은 snapshot으로
        // 갱신해야 preview/export의 요청 mode가 화면과 어긋나지 않습니다.
        UpdateSelectedFrameText();
        NotifyQuickExportAvailabilityChanged();
        if (panel.SelectedFrame is { CanDevelop: true })
        {
            ExportStatusText.Text = string.Empty;
        }
        RequestPreview();
    }

    private void OnBaseRecipeChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        UpdateAfterBaseRecipeChanged();
    }

    private void UpdateSelectedFrameText()
    {
        if (panel?.SelectedFrame is { } frame)
        {
            SelectedFrameText.Text = new LibraryFrameListItem(frame).Detail;
        }
    }

    /// <summary>
    /// 현재 선택을 미리보기로 그립니다. 겹쳐 들어온 요청은 coordinator 가 합치되 마지막 것은
    /// 반드시 그리므로, 슬라이더를 끌어도 최종 상태가 화면에 남습니다.
    /// </summary>
    private void RequestPreview()
    {
        // 레이어 강도를 끄는 동안에는 아직 저장하지 않은 값을 얹은 사본을 그립니다 — 저장은
        // 원본 파일 전체를 다시 해싱하므로 드래그 중에 하면 슬라이더가 멈춥니다.
        if (previewCoordinator is null || panel?.DefectLayers.PreviewFrame is not { } frame)
        {
            return;
        }
        _ = previewCoordinator.RequestAsync(frame, ShowPreview);
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

    private void OnGeometryCropClicked(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        OnCropClicked(this, new RoutedEventArgs());
    }

    private void OnCropClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (crop.IsActive)
        {
            CancelCrop();
            return;
        }
        if (panel is null || panel.SelectedFrame is null || !PreviewCanvas.HasPreview)
        {
            return;
        }

        // macOS와 같이 crop을 먼저 해제해 전체 프레임에서 새 선택을 만들게 합니다. 드래그 중
        // catalog를 쓰지 않고 Apply/Cancel에서 한 번만 저장합니다.
        if (panel.SetCrop(null) != LibraryFrameError.None)
        {
            return;
        }
        crop.Begin(panel.ImageTransform.Crop, LockedNormalizedAspectRatio());
        GeometryCard.SetDialVisible(true);
        PreviewCanvas.FocusHost();
        RequestPreview();
    }

    private void OnCropApplyClicked(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (!crop.IsActive || panel is null)
        {
            return;
        }
        if (panel.SetCrop(crop.Apply()) != LibraryFrameError.None)
        {
            return;
        }
        EndCropSession();
        RequestPreview();
    }

    private void OnCropFullClicked(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (!crop.Full())
        {
            return;
        }
        PreviewCanvas.RenderCropOverlay();
    }

    private void OnCropCancelClicked(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        CancelCrop();
    }

    private void CancelCrop()
    {
        if (!crop.IsActive)
        {
            return;
        }
        ImageCropRect? restore = crop.Cancel();
        if (panel?.SetCrop(restore) != LibraryFrameError.None)
        {
            return;
        }
        EndCropSession();
        RequestPreview();
    }

    private void EndCropSession()
    {
        crop.End();
        PreviewCanvas.HideCropOverlay();
        GeometryCard.SetDialVisible(false);
    }

    private void OnPreviewCanvasSizeChanged(object? sender, SizeChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        RenderGuidedDefectSelection();
    }

    private bool TryHandleGrainMendPointerPressed(PointerRoutedEventArgs args)
    {
        if (TryTogglePendingDefectComponent(args))
        {
            args.Handled = true;
            return true;
        }
        if (TryBeginGuidedDefectSelection(args))
        {
            args.Handled = true;
            return true;
        }
        if (TryBeginGrainMendStroke(args))
        {
            args.Handled = true;
            return true;
        }
        return false;
    }

    private bool TryHandleGrainMendPointerMoved(PointerRoutedEventArgs args)
    {
        if (TryContinueGuidedDefectSelection(args))
        {
            args.Handled = true;
            return true;
        }
        if (TryContinueGrainMendStroke(args))
        {
            args.Handled = true;
            return true;
        }
        return false;
    }

    private bool TryHandleGrainMendPointerReleased(PointerRoutedEventArgs args)
    {
        if (TryFinishGuidedDefectSelection(args))
        {
            args.Handled = true;
            return true;
        }
        if (TryFinishGrainMendStroke(args))
        {
            args.Handled = true;
            return true;
        }
        return false;
    }

    private bool TryBeginGuidedDefectSelection(PointerRoutedEventArgs args)
    {
        if (grainMend.Strokes.Tool != GrainMendTool.Guided || grainMend.IsDetecting ||
            panel?.SelectedFrame is null ||
            !TryCanvasUnitPoint(args, out CropDisplayPoint point))
        {
            return false;
        }
        guidedDefectDragStart = point;
        guidedDefectDragCurrent = point;
        guidedDefectDragging = true;
        RenderGuidedDefectSelection();
        PreviewCanvas.CaptureHost(args.Pointer);
        return true;
    }

    /// <summary>
    /// 보류 중인 자동/가이드 마스크의 연결 성분을 클릭하면 포함과 제외를 바꿉니다. 이 단계는
    /// recipe를 건드리지 않으며, Enter 또는 제거 단추를 눌러야만 sidecar로 갑니다.
    /// </summary>
    private bool TryTogglePendingDefectComponent(PointerRoutedEventArgs args)
    {
        if (grainMend.PendingReview is null || grainMend.PendingEdit is null ||
            panel?.SelectedFrame is not { SourceMetadata: { } metadata } frame ||
            !TryCanvasUnitPoint(args, out CropDisplayPoint displayPoint) ||
            !DevelopDisplayGeometry.TryMapDisplayToRaw(
                frame.ImageTransform,
                metadata.PixelWidth,
                metadata.PixelHeight,
                displayPoint.X,
                displayPoint.Y,
                out double rawX,
                out double rawY) ||
            !grainMend.ToggleReviewAtRaw(new DefectPoint(rawX, rawY)))
        {
            return false;
        }

        ExportStatusText.Text = AppResources.FormatIntegers(
            "developGrainMendFoundFormat",
            "Value",
            grainMend.IncludedCount);
        ShowDefectOverlay(grainMend.PendingEdit);
        UpdateGrainMendCard();
        return true;
    }

    private bool TryContinueGuidedDefectSelection(PointerRoutedEventArgs args)
    {
        if (!guidedDefectDragging || !TryCanvasUnitPoint(args, out CropDisplayPoint point))
        {
            return false;
        }
        guidedDefectDragCurrent = point;
        RenderGuidedDefectSelection();
        return true;
    }

    private bool TryFinishGuidedDefectSelection(PointerRoutedEventArgs args)
    {
        if (!guidedDefectDragging)
        {
            return false;
        }
        if (TryCanvasUnitPoint(args, out CropDisplayPoint point))
        {
            guidedDefectDragCurrent = point;
        }
        PreviewCanvas.ReleaseHost(args.Pointer);
        guidedDefectDragging = false;
        PreviewCanvas.HideGuidedSelection();

        double width = Math.Abs(guidedDefectDragCurrent.X - guidedDefectDragStart.X);
        double height = Math.Abs(guidedDefectDragCurrent.Y - guidedDefectDragStart.Y);
        if (width <= 0.012 || height <= 0.012 || panel is null)
        {
            return true;
        }
        DefectRect displayRoi = new(
            Math.Min(guidedDefectDragStart.X, guidedDefectDragCurrent.X),
            Math.Min(guidedDefectDragStart.Y, guidedDefectDragCurrent.Y),
            width,
            height);
        if (panel.TryMapDisplayRectToRaw(displayRoi, out DefectRect rawRoi))
        {
            _ = DetectGrainMendAsync(rawRoi);
        }
        return true;
    }

    private void EndGuidedDefectSelection(PointerRoutedEventArgs args)
    {
        if (!guidedDefectDragging)
        {
            return;
        }
        PreviewCanvas.ReleaseHost(args.Pointer);
        guidedDefectDragging = false;
        PreviewCanvas.HideGuidedSelection();
    }

    private void RenderGuidedDefectSelection()
    {
        if (!guidedDefectDragging)
        {
            PreviewCanvas.HideGuidedSelection();
            return;
        }
        PreviewCanvas.ShowGuidedSelection(guidedDefectDragStart, guidedDefectDragCurrent);
    }

    private bool TryHandleGrainMendKeyDown(KeyRoutedEventArgs args)
    {
        // 검토 중인 검출이 있으면 그것이 먼저입니다. 도움말이 안내하는 대로 Enter 가 받아들이고
        // Esc 가 버립니다.
        if (grainMend.PendingEdit is not null)
        {
            if (args.Key == VirtualKey.Enter)
            {
                AcceptPendingDefectEdit();
                args.Handled = true;
                return true;
            }
            if (args.Key == VirtualKey.Escape)
            {
                CancelPendingDefectEdit();
                args.Handled = true;
                return true;
            }
        }
        if (args.Key == VirtualKey.Escape && grainMend.Strokes.Tool == GrainMendTool.Guided)
        {
            SetGrainMendTool(GrainMendTool.None);
            args.Handled = true;
            // 크롭이 켜져 있으면 Esc 는 이어서 크롭도 닫습니다. 여기서 삼키지 않습니다.
        }
        return false;
    }

    private bool TryCanvasUnitPoint(PointerRoutedEventArgs args, out CropDisplayPoint point) =>
        PreviewCanvas.TryMapPointer(args, out point);

    private void SyncBaseControls() => BaseCard.Sync();

    private void SyncToneControls()
    {
        bool canEdit = panel?.CanEditTone == true;
        bool canAutoAdjust = panel?.SelectedFrame?.CanDevelop == true &&
                             autoAdjustCoordinator is not null;
        Adjustments.SetEnabled(canEdit, canAutoAdjust);
        GeometryCard.SetEnabled(canEdit);
        HistogramView.IsEnabled = canEdit;
    }

    private void OnAdjustmentAutoColorToggled(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingInspector)
        {
            return;
        }
        UpdateImageTransform(state =>
            state.SetAutoNeutralBalance(Adjustments.AutoColorIsOn));
    }

    private void OnAdjustmentAutoLevelsToggled(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingInspector)
        {
            return;
        }
        UpdateImageTransform(state => state.SetAutoLevels(Adjustments.AutoLevelsIsOn));
    }

    private async void OnAdjustmentAutoToneClicked(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        await RunAutoAdjustAsync(AutoAdjustOperation.Tone);
    }

    private async void OnAdjustmentAutoWhiteBalanceClicked(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        await RunAutoAdjustAsync(AutoAdjustOperation.WhiteBalance);
    }

    private async Task RunAutoAdjustAsync(AutoAdjustOperation operation)
    {
        if (autoAdjustCoordinator is null || panel?.SelectedFrame is not { } frame)
        {
            return;
        }

        Adjustments.SetAutoAdjustEnabled(false);
        Adjustments.SetAutoAdjustStatus(string.Empty);
        Action<AutoAdjustOutcome> completed = outcome =>
        {
            if (outcome.Kind == DevelopExportOutcomeKind.Completed && outcome.Settings is not null &&
                panel?.SelectedFrame == frame)
            {
                LibraryFrameError error = operation == AutoAdjustOperation.Tone
                    ? panel.Tone.ApplyAutoTone(outcome.Settings)
                    : panel.Tone.ApplyAutoWhiteBalance(outcome.Settings);
                if (error == LibraryFrameError.None)
                {
                    SynchronizeInspectorValues();
                    RequestPreview();
                }
                else
                {
                    Adjustments.SetAutoAdjustStatus(AppResources.Get("developAutoAdjustFailed", "Text"));
                }
            }
            else if (outcome.Kind != DevelopExportOutcomeKind.Completed)
            {
                Adjustments.SetAutoAdjustStatus(AppResources.Get("developAutoAdjustFailed", "Text"));
            }
            SyncToneControls();
        };

        bool delivered = operation == AutoAdjustOperation.Tone
            ? await autoAdjustCoordinator.RunToneAsync(frame, completed)
            : await autoAdjustCoordinator.RunWhiteBalanceAsync(frame, completed);
        if (!delivered)
        {
            Adjustments.SetAutoAdjustStatus(AppResources.Get("developAutoAdjustFailed", "Text"));
            SyncToneControls();
        }
    }

    private void UpdateAfterBaseRecipeChanged()
    {
        if (panel is null)
        {
            return;
        }

        SyncBaseControls();
        UpdateSelectedFrameText();
        NotifyQuickExportAvailabilityChanged();
        ExportStatusText.Text = string.Empty;
        RequestPreview();
    }

    private static DevelopRequestRefusal RefusalFor(LibraryFrameSnapshot frame)
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

    private void OnHistogramValueChanged(object? sender, DevelopHistogramValueChangedEventArgs args)
    {
        _ = sender;
        if (panel is null || isSynchronizingInspector)
        {
            return;
        }

        LibraryFrameError error = args.Region switch
        {
            DevelopHistogramRegion.Shadow => panel.Tone.SetShadows(args.Value),
            DevelopHistogramRegion.Density => panel.Tone.SetDensity(args.Value),
            DevelopHistogramRegion.Exposure => panel.Tone.SetExposure(args.Value),
            DevelopHistogramRegion.Highlight => panel.Tone.SetHighlights(args.Value),
            _ => LibraryFrameError.InvalidToneValue,
        };
        if (error == LibraryFrameError.None)
        {
            SynchronizeInspectorValues();
            RequestPreview();
        }
    }

    private void OnGeometryTransformRequested(
        object? sender,
        Func<DevelopPanelState, LibraryFrameError> update)
    {
        _ = sender;
        UpdateImageTransform(update);
    }

    /// <summary>
    /// recipe 가 통째로 바뀌었을 때 화면 전체를 다시 맞춥니다. 붙여넣기와 프리셋 적용이 같은
    /// 자리를 쓰므로 한쪽만 갱신되는 일이 없습니다.
    /// </summary>
    private void ReloadAfterRecipeReplaced()
    {
        SynchronizeInspectorValues();
        SyncBaseControls();
        SyncToneControls();
        LeftPanel.FilmLookPanel.Update();
        LeftPanel.PresetsPanel.Update();
        RequestPreview();
    }

    private void OnPresetRecipeReplaced(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        ReloadAfterRecipeReplaced();
    }

    private bool updatingGrainMendSensitivity;
    private bool updatingGrainMendMicroSpecks;

    private async void OnGrainMendAutoClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        SetGrainMendTool(GrainMendTool.None);
        await DetectGrainMendAsync(new DefectRect(0.0, 0.0, 1.0, 1.0));
    }

    private void OnGrainMendGuidedClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ClearPendingDefectEdit();
        SetGrainMendTool(grainMend.Strokes.Tool == GrainMendTool.Guided
            ? GrainMendTool.None
            : GrainMendTool.Guided);
        if (grainMend.Strokes.Tool == GrainMendTool.Guided)
        {
            PreviewCanvas.FocusHost();
        }
    }

    private async Task DetectGrainMendAsync(DefectRect rawRoi)
    {
        if (panel?.SelectedFrame is not { } frame || grainMendDetectCoordinator is null ||
            grainMend.IsDetecting)
        {
            return;
        }
        grainMend.BeginDetection();
        HideDefectOverlay();
        ExportStatusText.Text = AppResources.Get("developGrainMendDetecting", "Text");
        UpdateGrainMendCard();
        try
        {
            bool automatic = IsWholeFrameGrainMendRoi(rawRoi);
            GrainMendDetectionOptions options = GrainMendSensitivity.ToDetectionOptions(
                GetGrainMendSensitivity(automatic),
                automatic,
                GetGrainMendMicroSpecks(automatic));
            await grainMendDetectCoordinator.RunAsync(
                frame,
                rawRoi,
                options,
                outcome => ShowDetectedDefects(outcome, rawRoi));
        }
        finally
        {
            grainMend.EndDetection();
            UpdateGrainMendCard();
        }
    }

    private void ShowDetectedDefects(GrainMendDetectOutcome outcome, DefectRect rawRoi)
    {
        if (outcome.Kind is DevelopExportOutcomeKind.Refused
            or DevelopExportOutcomeKind.Faulted)
        {
            ExportStatusText.Text = AppResources.Get("developGrainMendDetectFailed", "Text");
            return;
        }
        if (outcome.Edit is not { } edit)
        {
            ExportStatusText.Text = AppResources.Get("developGrainMendFoundNothing", "Text");
            return;
        }

        if (!grainMend.SetDetectedEdit(edit, rawRoi))
        {
            ExportStatusText.Text = AppResources.Get("developGrainMendFoundNothing", "Text");
            return;
        }
        ExportStatusText.Text = AppResources.FormatIntegers(
            "developGrainMendFoundFormat",
            "Value",
            grainMend.IncludedCount);
        ShowDefectOverlay(edit);
        UpdateGrainMendCard();
        // Enter 와 Esc 를 받으려면 캔버스가 초점을 가져야 합니다.
        PreviewCanvas.FocusHost();
    }

    /// <summary>
    /// 마스크를 미리보기 위에 얹습니다. 표시된 화소만 칠하고 나머지는 완전히 투명하게 둡니다 —
    /// 반투명한 판을 통째로 덮으면 사진이 아니라 판을 보게 됩니다.
    /// </summary>
    private void ShowDefectOverlay(DefectEditItem edit)
    {
        if (panel?.SelectedFrame is not { } frame || PreviewCanvas.PreviewBitmap is null)
        {
            return;
        }

        int width = PreviewCanvas.PreviewBitmap.PixelWidth;
        int height = PreviewCanvas.PreviewBitmap.PixelHeight;
        if (GrainMendOverlayRenderer.Render(
                frame,
                width,
                height,
                edit,
                grainMend.PendingReview) is not { } bgra)
        {
            return;
        }
        PreviewCanvas.ShowDefectPixels(bgra, width, height);
    }

    private void ClearPendingDefectEdit()
    {
        grainMend.ClearPending();
        HideDefectOverlay();
    }

    private void HideDefectOverlay() => PreviewCanvas.HideDefectOverlay();

    private static bool IsWholeFrameGrainMendRoi(DefectRect roi) =>
        roi.X == 0.0 && roi.Y == 0.0 && roi.Width == 1.0 && roi.Height == 1.0;

    private double GetGrainMendSensitivity(bool automatic)
    {
        return panel?.SelectedFrame is { } frame
            ? grainMend.Sensitivity(frame.Id, automatic)
            : GrainMendSensitivity.Default;
    }

    private void SetGrainMendSensitivity(bool automatic, double value)
    {
        if (panel?.SelectedFrame is not { } frame)
        {
            return;
        }
        grainMend.SetSensitivity(frame.Id, automatic, value);
    }

    private bool GetGrainMendMicroSpecks(bool automatic)
    {
        return panel?.SelectedFrame is { } frame
            ? grainMend.MicroSpecks(
                frame.Id,
                automatic,
                MicroSpeckDefault(automatic: true),
                MicroSpeckDefault(automatic: false))
            : MicroSpeckDefault(automatic);
    }

    /// <summary>설정에 담긴 기본값입니다. 설정을 못 읽으면 macOS 기본인 켬입니다.</summary>
    private bool MicroSpeckDefault(bool automatic) =>
        workspaceState?.Current is { } preferences
            ? automatic
                ? preferences.AutoDefectDetectsMicroSpecks
                : preferences.GuidedDefectDetectsMicroSpecks
            : true;

    private void SetGrainMendMicroSpecks(bool automatic, bool enabled)
    {
        if (panel?.SelectedFrame is not { } frame)
        {
            return;
        }
        grainMend.SetMicroSpecks(
            frame.Id,
            automatic,
            enabled,
            MicroSpeckDefault(automatic: true),
            MicroSpeckDefault(automatic: false));
    }

    private void OnGrainMendSensitivityValueChanged(
        object sender,
        RangeBaseValueChangedEventArgs args)
    {
        _ = sender;
        if (updatingGrainMendSensitivity || grainMend.PendingEdit is null)
        {
            return;
        }
        SetGrainMendSensitivity(
            grainMend.PendingEdit.Label.Kind == DefectEditLabelKind.Automatic,
            args.NewValue);
    }

    private async void OnGrainMendSensitivityPointerReleased(
        object sender,
        PointerRoutedEventArgs args)
    {
        _ = sender;
        args.Handled = true;
        await RedetectGrainMendForSensitivityAsync();
    }

    private async void OnGrainMendSensitivityKeyUp(object sender, KeyRoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        await RedetectGrainMendForSensitivityAsync();
    }

    private async Task RedetectGrainMendForSensitivityAsync()
    {
        if (grainMend.TakeSensitivityRedetectionRoi() is not { } rawRoi)
        {
            return;
        }
        await DetectGrainMendAsync(rawRoi);
    }

    private async void OnGrainMendMicroSpecksToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (updatingGrainMendMicroSpecks || grainMend.PendingEdit is null ||
            grainMend.PendingRawRoi is not { } rawRoi || grainMend.IsDetecting)
        {
            return;
        }
        bool automatic = grainMend.PendingEdit.Label.Kind == DefectEditLabelKind.Automatic;
        SetGrainMendMicroSpecks(automatic, GrainMendMicroSpecksToggle.IsOn);
        await DetectGrainMendAsync(rawRoi);
    }

    /// <summary>검토 중인 검출을 받아들여 recipe 에 담습니다.</summary>
    private void AcceptPendingDefectEdit()
    {
        if (panel is null || grainMend.PendingEdit is null)
        {
            return;
        }
        DefectEditItem? edit = grainMend.BuildAcceptedEdit();
        if (edit is null)
        {
            CancelPendingDefectEdit();
            return;
        }
        ClearPendingDefectEdit();
        if (panel.AcceptDefectRegion(edit) != LibraryFrameError.None)
        {
            ExportStatusText.Text = AppResources.Get("developGrainMendDetectFailed", "Text");
            return;
        }
        ExportStatusText.Text = string.Empty;
        UpdateGrainMendCard();
        RequestPreview();
    }

    private void CancelPendingDefectEdit()
    {
        ClearPendingDefectEdit();
        ExportStatusText.Text = string.Empty;
        UpdateGrainMendCard();
    }

    private void OnGrainMendRemoveClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        AcceptPendingDefectEdit();
    }

    private void OnGrainMendCancelClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        CancelPendingDefectEdit();
    }

    private void OnGrainMendBrushClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        SetGrainMendTool(grainMend.Strokes.Tool == GrainMendTool.Brush
            ? GrainMendTool.None
            : GrainMendTool.Brush);
    }

    private void OnGrainMendCloneClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        SetGrainMendTool(grainMend.Strokes.Tool == GrainMendTool.Clone
            ? GrainMendTool.None
            : GrainMendTool.Clone);
    }

    private void OnGrainMendAutoResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ClearPendingDefectEdit();
        RemoveGrainMendEdits(DefectEditLabelKind.Automatic);
    }

    private void OnGrainMendGuidedResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ClearPendingDefectEdit();
        RemoveGrainMendEdits(DefectEditLabelKind.Guided);
    }

    private void OnGrainMendBrushResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        RemoveGrainMendEdits(DefectEditKind.Brush);
    }

    private void OnGrainMendCloneResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        RemoveGrainMendEdits(DefectEditKind.Clone);
    }

    private void RemoveGrainMendEdits(DefectEditKind kind)
    {
        if (panel is null)
        {
            return;
        }
        SetGrainMendTool(GrainMendTool.None);
        if (panel.RemoveDefectEdits(kind) != LibraryFrameError.None)
        {
            return;
        }
        UpdateGrainMendCard();
        RequestPreview();
    }

    private void RemoveGrainMendEdits(DefectEditLabelKind label)
    {
        if (panel is null)
        {
            return;
        }
        SetGrainMendTool(GrainMendTool.None);
        if (panel.RemoveDefectEdits(label) != LibraryFrameError.None)
        {
            return;
        }
        UpdateGrainMendCard();
        RequestPreview();
    }

    private void SetGrainMendTool(GrainMendTool tool)
    {
        if (grainMend.Strokes.Tool == tool)
        {
            return;
        }
        grainMend.Strokes.Select(tool);
        if (tool != GrainMendTool.Guided)
        {
            guidedDefectDragging = false;
            PreviewCanvas.HideGuidedSelection();
        }
        if (tool != GrainMendTool.None && crop.IsActive)
        {
            // 크롭과 결함 도구는 같은 포인터를 두고 다툽니다. macOS 도 서로를 끕니다.
            EndCropSession();
        }
        UpdateGrainMendCard();
    }

    private void UpdateGrainMendCard()
    {
        if (GrainMendAutoButton is null)
        {
            return;
        }
        GrainMendTitleText.Text = AppResources.Get("developGrainMend", "Text");
        GrainMendAutoText.Text = AppResources.Get("developGrainMendAuto", "Content");
        GrainMendGuidedText.Text = AppResources.Get("developGrainMendGuided", "Content");
        GrainMendBrushText.Text = AppResources.Get("developGrainMendBrush", "Content");
        GrainMendCloneText.Text = AppResources.Get("developGrainMendClone", "Content");
        GrainMendRemoveButton.Content = AppResources.Get("developGrainMendRemove", "Content");
        GrainMendCancelButton.Content = AppResources.Get("developCropCancel", "Text");
        GrainMendSensitivityLabel.Text = AppResources.Get("developGrainMendSensitivity", "Text");
        SetLocalizedNameAndTooltip(
            GrainMendBrushButton, AppResources.Get("developGrainMendBrushHelp", "Value"));
        SetLocalizedNameAndTooltip(
            GrainMendCloneButton, AppResources.Get("developGrainMendCloneHelp", "Value"));
        SetLocalizedNameAndTooltip(
            GrainMendAutoButton, AppResources.Get("developGrainMendAutoHelp", "Value"));
        SetLocalizedNameAndTooltip(
            GrainMendGuidedButton,
            AppResources.Get("developGrainMendGuidedHelp", "Value"));
        SetLocalizedNameAndTooltip(
            GrainMendRemoveButton, AppResources.Get("developGrainMendRemove", "Content"));
        SetLocalizedNameAndTooltip(
            GrainMendCancelButton, AppResources.Get("developCropCancel", "Text"));
        string grainMendSensitivity = AppResources.Get("developGrainMendSensitivity", "Text");
        AutomationProperties.SetName(GrainMendSensitivitySlider, grainMendSensitivity);
        ToolTipService.SetToolTip(GrainMendSensitivitySlider, grainMendSensitivity);
        string grainMendMicroSpecks = AppResources.Get("developGrainMendMicroSpecks", "Text");
        GrainMendMicroSpecksToggle.OnContent = grainMendMicroSpecks;
        GrainMendMicroSpecksToggle.OffContent = grainMendMicroSpecks;
        AutomationProperties.SetName(GrainMendMicroSpecksToggle, grainMendMicroSpecks);
        ToolTipService.SetToolTip(GrainMendMicroSpecksToggle, grainMendMicroSpecks);
        GrainMendCardState card = GrainMendCardProjection.Create(
            panel?.SelectedFrame is not null,
            grainMend.IsDetecting,
            grainMend.PendingEdit?.Label.Kind,
            grainMend.PendingReview?.IncludedCount,
            grainMend.Strokes.Tool,
            panel?.HasDefectEdits(DefectEditLabelKind.Automatic) == true,
            panel?.HasDefectEdits(DefectEditLabelKind.Guided) == true,
            panel?.HasDefectEdits(DefectEditKind.Brush) == true,
            panel?.HasDefectEdits(DefectEditKind.Clone) == true);
        GrainMendAutoButton.IsEnabled = card.AutoEnabled;
        GrainMendAutoResetButton.IsEnabled = card.AutoResetEnabled;
        GrainMendGuidedButton.IsEnabled = card.GuidedEnabled;
        GrainMendGuidedResetButton.IsEnabled = card.GuidedResetEnabled;
        GrainMendReviewTuning.Visibility = card.Reviewing ? Visibility.Visible : Visibility.Collapsed;
        GrainMendReviewActions.Visibility = card.Reviewing ? Visibility.Visible : Visibility.Collapsed;
        GrainMendSensitivitySlider.IsEnabled = card.SensitivityEnabled;
        GrainMendMicroSpecksToggle.IsEnabled = card.MicroSpecksEnabled;
        if (card.Reviewing)
        {
            updatingGrainMendSensitivity = true;
            GrainMendSensitivitySlider.Value = GetGrainMendSensitivity(card.ReviewingAutomatic);
            updatingGrainMendSensitivity = false;
            updatingGrainMendMicroSpecks = true;
            GrainMendMicroSpecksToggle.IsOn = GetGrainMendMicroSpecks(card.ReviewingAutomatic);
            updatingGrainMendMicroSpecks = false;
        }
        GrainMendRemoveButton.IsEnabled = card.RemoveEnabled;
        GrainMendCancelButton.IsEnabled = card.CancelEnabled;

        string reset = AppResources.Get("developGrainMendReset", "Value");
        SetLocalizedNameAndTooltip(GrainMendAutoResetButton, reset);
        SetLocalizedNameAndTooltip(GrainMendGuidedResetButton, reset);
        SetLocalizedNameAndTooltip(GrainMendBrushResetButton, reset);
        SetLocalizedNameAndTooltip(GrainMendCloneResetButton, reset);

        GrainMendBrushButton.IsEnabled = card.BrushEnabled;
        GrainMendCloneButton.IsEnabled = card.CloneEnabled;
        GrainMendBrushResetButton.IsEnabled = card.BrushResetEnabled;
        GrainMendCloneResetButton.IsEnabled = card.CloneResetEnabled;

        ApplyGrainMendPill(GrainMendAutoPill, GrainMendAutoButton, card.AutoActive);
        ApplyGrainMendPill(GrainMendGuidedPill, GrainMendGuidedButton, card.GuidedActive);
        ApplyGrainMendPill(GrainMendBrushPill, GrainMendBrushButton, card.BrushActive);
        ApplyGrainMendPill(GrainMendClonePill, GrainMendCloneButton, card.CloneActive);
        // 카드가 바뀌는 모든 자리는 목록도 바뀌는 자리입니다. 열두 군데를 따로 부르면
        // 언젠가 한 군데가 빠지고 목록만 옛 값을 붙듭니다.
        UpdateDefectLayers();
    }

    /// <summary>
    /// macOS InspectorActionPill 의 켜짐 표시입니다. 캡슐 바탕과 낭독기 상태가 함께 바뀌어야
    /// 눈으로 보는 것과 읽어 주는 것이 어긋나지 않습니다.
    /// </summary>
    private static void ApplyGrainMendPill(Border pill, Button action, bool isActive)
    {
        pill.Background = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources[
            isActive ? "NegaflowSelectionBrush" : "NegaflowSubtleFillBrush"];
        AutomationProperties.SetItemStatus(
            action,
            AppResources.Get(isActive ? "selected" : "notSelected", "Value"));
    }

    /// <summary>
    /// 도구가 잡고 있으면 포인터를 가로챕니다. 크롭 세션과 같은 이벤트를 쓰므로 어느 쪽이
    /// 먼저인지가 분명해야 합니다 — 도구가 켜져 있으면 크롭은 이미 꺼져 있습니다.
    /// </summary>
    private bool TryBeginGrainMendStroke(PointerRoutedEventArgs args)
    {
        if (panel?.SelectedFrame is null ||
            !TryCanvasUnitPoint(args, out CropDisplayPoint point))
        {
            return false;
        }

        bool alt = InputKeyboardSource
            .GetKeyStateForCurrentThread(Windows.System.VirtualKey.Menu)
            .HasFlag(CoreVirtualKeyStates.Down);
        bool handled = grainMend.Strokes.Begin(
            new DefectPoint(point.X, point.Y),
            alt);
        if (grainMend.Strokes.IsDragging)
        {
            PreviewCanvas.CaptureHost(args.Pointer);
        }
        return handled;
    }

    private bool TryContinueGrainMendStroke(PointerRoutedEventArgs args)
    {
        if (!TryCanvasUnitPoint(args, out CropDisplayPoint point))
        {
            return false;
        }
        return grainMend.Strokes.Continue(new DefectPoint(point.X, point.Y));
    }

    private bool TryFinishGrainMendStroke(PointerRoutedEventArgs args)
    {
        if (!grainMend.Strokes.IsDragging)
        {
            return false;
        }
        PreviewCanvas.ReleaseHost(args.Pointer);
        if (panel is null)
        {
            grainMend.Strokes.CancelStroke();
            return true;
        }
        if (!grainMend.Strokes.Finish(panel, out LibraryFrameError error))
        {
            return false;
        }
        if (error == LibraryFrameError.None)
        {
            UpdateGrainMendCard();
            RequestPreview();
        }
        return true;
    }

    private void UpdateVersionControls() => LeftPanel.VersionsPanel.Update();

    private void OnVersionRestored(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        // 되돌린 recipe 가 인스펙터와 캔버스에 함께 반영돼야 합니다.
        SynchronizeInspectorValues();
        SyncBaseControls();
        SyncToneControls();
        RequestPreview();
    }

    private void UpdateFilmLookControls() => LeftPanel.FilmLookPanel.Update();

    private void OnFilmLookChanged(
        object? sender,
        Func<DevelopPanelState, LibraryFrameError> update)
    {
        _ = sender;
        UpdateImageTransform(update);
    }


    private void OnLibrarySelectionChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (libraryHost?.ActiveFrameId is { } activeFrameId &&
            (FrameSelector.ItemsSource is not IReadOnlyList<LibraryFrameListItem> items ||
             IndexOf(items, activeFrameId) < 0))
        {
            RefreshFrames();
        }
        else
        {
            SynchronizeSharedSelection();
        }
        LeftPanel.RebuildLibraryTree();
        LeftPanel.ExportPanel.RefreshPreview();
    }

    private void SynchronizeSharedSelection()
    {
        if (libraryHost?.ActiveFrameId is not { } activeFrameId ||
            FrameSelector.ItemsSource is not IReadOnlyList<LibraryFrameListItem> items)
        {
            return;
        }
        int index = IndexOf(items, activeFrameId);
        if (index < 0 || index == FrameSelector.SelectedIndex)
        {
            return;
        }
        isSynchronizingFrameSelection = true;
        try
        {
            FrameSelector.SelectedIndex = index;
        }
        finally
        {
            isSynchronizingFrameSelection = false;
        }
        ActivateFrame(items[index], index, publishSelection: false);
    }


    /// <summary>
    /// 드래그를 가둘 정규 비율입니다. 잠금이 꺼져 있거나 비율이 없으면 null 입니다. 화소
    /// 비율을 정규 비율로 바꾸려면 원본의 가로세로가 필요합니다 — 회전이 걸려 있으면 뒤집습니다.
    /// </summary>
    private double? LockedNormalizedAspectRatio()
    {
        if (panel?.SelectedFrame is not { SourceMetadata: { } metadata })
        {
            return null;
        }
        return CropInteraction.LockedNormalizedAspectRatio(
            crop.IsAspectLocked,
            panel.ImageTransform.CropAspect,
            metadata.PixelWidth,
            metadata.PixelHeight,
            panel.ImageTransform.Rotation);
    }

    private void OnGeometryAspectChosen(object? sender, CropAspectOption option)
    {
        _ = sender;
        // 비율이 crop 을 다시 만드는 동안에는 진행 중인 crop session 을 접습니다 — 두 곳이
        // 같은 사각형을 서로 다르게 들고 있으면 Apply 가 어느 쪽을 쓸지 알 수 없습니다.
        CancelCrop();
        UpdateImageTransform(state => state.SetCropAspect(option));
    }

    private void OnGeometryAspectLockToggled(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        bool nextLocked = crop.ToggleAspectLock();
        // 잠금은 catalog 가 아니라 다음 crop 드래그의 동작만 바꿉니다.
        GeometryCard.SetLockGlyph(nextLocked);
        crop.SyncLockedAspect(LockedNormalizedAspectRatio());
        if (panel is not null)
        {
            GeometryCard.UpdateAspectControls(panel, crop.IsAspectLocked);
        }
    }

    private void UpdateImageTransform(Func<DevelopPanelState, LibraryFrameError> update)
    {
        if (panel is null || isSynchronizingInspector || update(panel) != LibraryFrameError.None)
        {
            return;
        }
        SynchronizeInspectorValues();
        RequestPreview();
    }

    private void ResetInspectorSection(Func<DevelopPanelState, LibraryFrameError> reset)
    {
        if (panel is null || reset(panel) != LibraryFrameError.None)
        {
            return;
        }

        SynchronizeInspectorValues();
        RequestPreview();
    }

    private void OnAdjustmentsPreviewRequested(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        RequestPreview();
    }

    private void OnAdjustmentsRefreshRequested(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        SynchronizeInspectorValues();
        RequestPreview();
    }

    private void OnAdjustmentsResetRequested(
        object? sender,
        Func<DevelopPanelState, LibraryFrameError> reset)
    {
        _ = sender;
        ResetInspectorSection(reset);
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


    private void NotifyQuickExportAvailabilityChanged() =>
        QuickExportAvailabilityChanged?.Invoke(this, EventArgs.Empty);

    private void OnRootSizeChanged(object sender, SizeChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (workspaceState is not null)
        {
            SynchronizeWidths(workspaceState.Current);
        }
    }

    private void OnLeftResizeStarted(object sender, DragStartedEventArgs args)
    {
        _ = sender;
        _ = args;
        resizeController.BeginLeft();
    }

    private void OnLeftResizeDelta(object sender, DragDeltaEventArgs args)
    {
        _ = sender;
        LeftPanel.Width = resizeController.UpdateLeft(args.HorizontalChange, Root.ActualWidth);
        UpdateCompactRail();
    }

    private void OnLeftResizeCompleted(object sender, DragCompletedEventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.SetSidebarWidth(resizeController.EndLeft());
    }

    private void OnRightResizeStarted(object sender, DragStartedEventArgs args)
    {
        _ = sender;
        _ = args;
        resizeController.BeginRight();
    }

    private void OnRightResizeDelta(object sender, DragDeltaEventArgs args)
    {
        _ = sender;
        RightPanel.Width = resizeController.UpdateRight(args.HorizontalChange, Root.ActualWidth);
    }

    private void OnRightResizeCompleted(object sender, DragCompletedEventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.SetInspectorWidth(resizeController.EndRight());
    }

    private void OnStateChanged(object? sender, ShellPreferences preferences)
    {
        _ = sender;
        UpdateState(preferences);
    }

    private void UpdateState(ShellPreferences preferences)
    {
        LeftPanel.Visibility = preferences.IsSidebarVisible ? Visibility.Visible : Visibility.Collapsed;
        LeftDivider.Visibility = LeftPanel.Visibility;
        LeftResizeThumb.Visibility = LeftPanel.Visibility;
        RightPanel.Visibility = preferences.IsInspectorVisible ? Visibility.Visible : Visibility.Collapsed;
        RightDivider.Visibility = RightPanel.Visibility;
        RightResizeThumb.Visibility = RightPanel.Visibility;
        Filmstrip.Visibility = preferences.IsFilmstripVisible ? Visibility.Visible : Visibility.Collapsed;
        SynchronizeWidths(preferences);
        LeftPanel.SynchronizeTab(preferences.SelectedDevelopSidebarTab);
        if (LeftPanel.ExportPanel.Settings != preferences.Export ||
            LeftPanel.ExportPanel.QuickSettings != preferences.QuickExport ||
            LeftPanel.ExportPanel.Recipes != preferences.ExportRecipes)
        {
            LeftPanel.ExportPanel.ApplyPreferences(
                preferences.Export,
                preferences.QuickExport,
                preferences.ExportRecipes);
        }

        // 프루프는 보기용이므로 미리보기에만 겁니다. 게시하는 파일은 그대로입니다.
        if (softProofPreferences != preferences.SoftProof)
        {
            softProofPreferences = preferences.SoftProof;
            ApplySoftProof();
        }
    }

    /// <summary>
    /// 고른 프로파일의 용지 흰색과 잉크 검정을 미리보기에 겁니다.
    /// </summary>
    /// <remarks>
    /// 목적지는 현상 대상이 정합니다 — PRINT 로 현상할 때는 프린터 출력 프로파일이 목적지이며,
    /// 그래야 프루프가 화면이 아니라 인화될 종이를 보여 줍니다. 프로파일을 읽지 못하면 용지·
    /// 잉크를 흉내 내지 않습니다: 없는 값을 지어내느니 프로파일만 보는 쪽이 정직합니다.
    /// </remarks>
    private void ApplySoftProof()
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

    private void SynchronizeWidths(ShellPreferences preferences)
    {
        resizeController.Synchronize(
            preferences.SidebarWidth,
            preferences.InspectorWidth,
            Root.ActualWidth);
        LeftPanel.Width = resizeController.LeftWidth;
        RightPanel.Width = resizeController.RightWidth;
        UpdateCompactRail();
    }

    private void UpdateCompactRail() => LeftPanel.UpdateCompactRail();

    private void LocalizeControls()
    {
        LeftPanel.Localize();
        string noFrame = AppResources.Get("noFrame", "Text");
        NoFrameLeftText.Text = noFrame;
        NoFrameInspectorText.Text = noFrame;
        DevelopHeaderText.Text = AppResources.Get("menuDevelop", "Text");
        InfoCards.Localize();
        Adjustments.Localize();
        BaseCard.Localize();
        GeometryCard.Localize();
        if (panel is not null)
        {
            GeometryCard.UpdateAspectControls(panel, crop.IsAspectLocked);
        }
        HistogramView.Localize(
            AppResources.Get("developHistogram", "Text"),
            AppResources.Get("developHistogramShadow", "Text"),
            AppResources.Get("developHistogramDensity", "Text"),
            AppResources.Get("developHistogramExposure", "Text"),
            AppResources.Get("developHistogramHighlight", "Text"),
            AppResources.Get("developHistogramRgb", "Text"),
            AppResources.Get("developHistogramClippingFormat", "Value"),
            AppResources.Get("developHistogramRedShort", "Text"),
            AppResources.Get("developHistogramGreenShort", "Text"),
            AppResources.Get("developHistogramBlueShort", "Text"),
            AppResources.Get("developHistogramKeyboardHelp", "Value"));
        string basic = AppResources.Get("developTabBasic", "Value");
        string baseTitle = AppResources.Get("developTabBase", "Value");
        string edit = AppResources.Get("developTabEdit", "Value");
        string defects = AppResources.Get("developTabDefects", "Value");
        string info = AppResources.Get("developTabInfo", "Value");
        string reset = AppResources.Get("developTabReset", "Value");
        SetLocalizedNameAndTooltip(BasicTabButton, basic);
        SetLocalizedNameAndTooltip(BaseTabButton, baseTitle);
        SetLocalizedNameAndTooltip(EditTabButton, edit);
        SetLocalizedNameAndTooltip(DefectsTabButton, defects);
        SetLocalizedNameAndTooltip(InfoTabButton, info);
        SetLocalizedNameAndTooltip(ResetTabButton, reset);
        PreviewCanvas.Localize();
    }

    private static void SetNameAndTooltip(ButtonBase button, string resourceKey)
    {
        string text = AppResources.Get(resourceKey, "Value");
        AutomationProperties.SetName(button, text);
        ToolTipService.SetToolTip(button, text);
    }

    private static void SetLocalizedNameAndTooltip(ButtonBase button, string text)
    {
        AutomationProperties.SetName(button, text);
        ToolTipService.SetToolTip(button, text);
    }

    private void OnUnloaded(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        CancelCrop();
        if (workspaceState is not null)
        {
            workspaceState.Changed -= OnStateChanged;
        }
    }
}
