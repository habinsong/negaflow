using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Develop.Canvas;

namespace Negaflow.Shell.Views.Develop.GrainMend;

/// <summary>
/// 결함 탭의 GrainMend 카드와 레이어 목록입니다. 검출·획·목록은 협력 타입이 맡습니다.
/// </summary>
public sealed partial class DevelopGrainMendPanel : UserControl
{
    internal WorkspacePresentationState? workspaceState;
    internal DevelopPanelState? panel;
    internal GrainMendDetectCoordinator? detectCoordinator;
    internal DevelopPreviewCanvas? canvas;
    internal CropWorkspaceState? crop;
    internal Action? endCropSession;
    internal Action<string>? setStatus;
    internal Action? requestPreview;
    internal Action? replacePreview;
    internal readonly GrainMendWorkspaceState grainMend = new();

    internal GrainMendAcceptance? removingAcceptance;
    internal readonly DevelopGrainMendChrome chrome;
    internal readonly DevelopGrainMendDetector detector;
    internal readonly DevelopGrainMendReview review;
    internal readonly DevelopGrainMendCanvasInput input;
    internal readonly DevelopGrainMendLayers layers;
    internal readonly DevelopGrainMendOptions options;

    public DevelopGrainMendPanel()
    {
        InitializeComponent();
        chrome = new DevelopGrainMendChrome(this);
        detector = new DevelopGrainMendDetector(this);
        review = new DevelopGrainMendReview(this);
        input = new DevelopGrainMendCanvasInput(this);
        layers = new DevelopGrainMendLayers(this);
        options = new DevelopGrainMendOptions(this);
        DefectLayers.Command += layers.OnCommand;
    }

    public void Attach(
        WorkspacePresentationState workspace,
        CropWorkspaceState cropState,
        DevelopPreviewCanvas previewCanvas,
        Action endCrop,
        Action exitCompetingTools,
        Action<string> status,
        Action preview,
        Action replace)
    {
        ArgumentNullException.ThrowIfNull(workspace);
        ArgumentNullException.ThrowIfNull(cropState);
        ArgumentNullException.ThrowIfNull(previewCanvas);
        ArgumentNullException.ThrowIfNull(endCrop);
        ArgumentNullException.ThrowIfNull(exitCompetingTools);
        ArgumentNullException.ThrowIfNull(status);
        ArgumentNullException.ThrowIfNull(preview);
        ArgumentNullException.ThrowIfNull(replace);
        workspaceState = workspace;
        crop = cropState;
        canvas = previewCanvas;
        endCropSession = endCrop;
        exitCompetingCanvasTools = exitCompetingTools;
        setStatus = status;
        requestPreview = preview;
        replacePreview = replace;
        AttachHud(previewCanvas.GrainMendHud);
    }

    /// <summary>
    /// 캔버스 위 캡슐을 잇습니다. 캡슐은 무엇을 눌렀는지만 알리고, 무엇을 할지는 여기서
    /// 정합니다 — 카드에 있던 검토 줄과 같은 경로로 들어갑니다.
    /// </summary>
    private void AttachHud(DevelopGrainMendHud hud)
    {
        hud.SensitivityChanged += OnHudSensitivityChanged;
        hud.SensitivityCommitted += OnHudSensitivityCommitted;
        hud.MicroSpecksToggled += OnHudMicroSpecksToggled;
        hud.CancelRequested += () => review.CancelPending();
        hud.RemoveRequested += OnHudRemoveRequested;
        hud.ClassToggled += OnHudClassToggled;
        hud.BrushThicknessChanged += OnHudBrushThicknessChanged;
        hud.BrushUndoRequested += OnHudBrushUndoRequested;
        hud.BrushClearRequested += OnHudBrushClearRequested;
        hud.AppliedDefectsResetRequested += () => review.RemoveAppliedDefects();
        hud.BrushApplyRequested += ApplyBrushDraft;
        hud.CloneDiameterChanged += OnHudCloneDiameterChanged;
        hud.CloneHardnessChanged += OnHudCloneHardnessChanged;
        hud.CloneUndoRequested += OnHudUndoRequested;
        hud.RegionUndoRequested += OnHudUndoRequested;
    }

    /// <summary>
    /// macOS <c>CloneStampOverlay</c> · <c>RegionDefectOverlay</c> 의 되돌리기 단추는
    /// <c>model.performUndo()</c> 입니다 — <b>한 획</b>만 되돌립니다. 도구별 편집을 통째로
    /// 지우는 것은 카드의 초기화 단추(<c>reset</c>)가 하는 다른 일입니다.
    /// </summary>
    private void OnHudUndoRequested()
    {
        if (panel is null)
        {
            return;
        }
        if (!panel.UndoDefectEdit())
        {
            if (panel.HistoryStoreError != CatalogStoreError.None ||
                panel.HistorySidecarError != DefectSidecarError.None)
            {
                SetStatus(AppResources.Get(
                    panel.HistoryStoreError != CatalogStoreError.None
                        ? "developExportSaveFailed"
                        : "libraryProcessApplyFailed",
                    "Text"));
            }
            return;
        }
        chrome.Update();
        RequestDefectPreview();
    }

    /// <summary>크기가 바뀌면 커서 원도 곧바로 그 크기가 됩니다(macOS <c>screenDiameter</c>).</summary>
    private void OnHudCloneDiameterChanged(double value)
    {
        grainMend.Strokes.CloneDiameterPixels = value;
        review.RenderCloneCursor();
        chrome.Update();
    }

    private void OnHudCloneHardnessChanged(double value)
    {
        grainMend.Strokes.CloneHardness = value;
        chrome.Update();
    }

    /// <summary>
    /// macOS 굵기 슬라이더는 진행 중인 획에도 곧바로 반영됩니다 — 값만 저장하고 오버레이를
    /// 다시 그립니다.
    /// </summary>
    private void OnHudBrushThicknessChanged(double value)
    {
        grainMend.Strokes.BrushThickness = value;
        review.RenderPaintOverlay();
        chrome.Update();
    }

    private void OnHudBrushUndoRequested()
    {
        if (!grainMend.Strokes.UndoLastPaintedStroke())
        {
            OnHudUndoRequested();
            return;
        }
        review.RenderPaintOverlay();
        chrome.Update();
    }

    private void OnHudBrushClearRequested()
    {
        if (!grainMend.Strokes.ClearPaintedStrokes())
        {
            return;
        }
        review.RenderPaintOverlay();
        chrome.Update();
    }

    /// <summary>
    /// macOS <c>onApply</c>: 모아 둔 칠을 recipe 로 보냅니다. 그때에만 현상이 다시 돕니다.
    /// </summary>
    internal void ApplyBrushDraft()
    {
        GrainMendPresentationSample presentation =
            BeginManualPresentation(GrainMendTool.Brush);
        if (panel is null ||
            !grainMend.Strokes.ApplyPaintedStrokes(panel, out LibraryFrameError error))
        {
            return;
        }
        review.RenderPaintOverlay();
        chrome.Update();
        if (error == LibraryFrameError.None)
        {
            SetStatus(string.Empty);
            TrackDevelopedPresentation(presentation);
            RequestDefectPreview();
        }
        else
        {
            ShowDefectWriteError();
        }
    }

    private void OnHudSensitivityChanged(double value)
    {
        if (isRemovingDefects || grainMend.PendingRawRoi is null ||
            grainMend.ActiveRegionKind is not { } activeKind)
        {
            return;
        }
        options.SetSensitivity(
            activeKind == DefectEditLabelKind.Automatic,
            value);
    }

    private async void OnHudSensitivityCommitted()
    {
        if (!isRemovingDefects)
        {
            await detector.RedetectForSensitivityAsync();
        }
    }

    private async void OnHudMicroSpecksToggled(bool enabled)
    {
        if (isRemovingDefects)
        {
            return;
        }
        if (grainMend.ActiveRegionKind is not { } activeKind)
        {
            return;
        }
        // 검토 중이 아니면(가이드를 켜 두고 기다리는 중) 값만 담아 둡니다. macOS 도 이때는
        // 재검출하지 않습니다 — 아직 검출한 것이 없습니다.
        bool automatic = activeKind == DefectEditLabelKind.Automatic;
        options.SetMicroSpecks(automatic, enabled);
        if (grainMend.PendingRawRoi is not { } rawRoi || grainMend.IsDetecting)
        {
            return;
        }
        await detector.DetectAsync(rawRoi, automatic);
    }

    private async void OnHudRemoveRequested()
    {
        await review.AcceptPendingAsync();
    }

    /// <summary>
    /// 종류별 칩 한 번입니다. 그 종류 전체를 제외↔포함하고 덮개를 다시 칠합니다 — macOS
    /// <c>toggleRegionClass</c> 와 같이 재검출은 없습니다.
    /// </summary>
    private void OnHudClassToggled(DefectClassification classification)
    {
        if (isRemovingDefects ||
            grainMend.PendingReview?.ToggleClass(classification) != true ||
            grainMend.PendingEdit is not { } edit)
        {
            return;
        }
        SetStatus(AppResources.FormatIntegers(
            "developGrainMendFoundFormat",
            "Value",
            grainMend.IncludedCount));
        review.ShowOverlay(edit);
        chrome.Update();
    }

    public void Bind(DevelopPanelState hostPanel)
    {
        ArgumentNullException.ThrowIfNull(hostPanel);
        if (panel is not null)
        {
            panel.SelectedFrameChanged -= OnSelectedFrameChanged;
        }
        panel = hostPanel;
        panel.SelectedFrameChanged += OnSelectedFrameChanged;
        grainMend.ChangeFrame(panel.SelectedFrame?.Id);
    }

    public void SetDetectCoordinator(GrainMendDetectCoordinator coordinator)
    {
        ArgumentNullException.ThrowIfNull(coordinator);
        detectCoordinator = coordinator;
    }

    public void Apply(bool visible)
    {
        Visibility = visible ? Visibility.Visible : Visibility.Collapsed;
        if (!visible)
        {
            // 탭을 떠나면 도구도 놓습니다. 보이지 않는 도구가 캔버스를 잡고 있으면
            // 크롭이나 확대가 먹지 않는 것처럼 보입니다.
            CancelRegionDefectSession();
            SetTool(GrainMendTool.None);
        }
        chrome.Update();
    }

    public void Localize() => chrome.Update();

    public bool TryHandlePointerPressed(PointerRoutedEventArgs args) =>
        input.TryHandlePressed(args);

    public bool TryHandlePointerMoved(PointerRoutedEventArgs args) =>
        input.TryHandleMoved(args);

    public bool TryHandlePointerReleased(PointerRoutedEventArgs args) =>
        input.TryHandleReleased(args);

    public void HandlePointerCancelled(PointerRoutedEventArgs args) =>
        input.CancelActivePointer(args);

    public bool TryHandleKeyDown(KeyRoutedEventArgs args) =>
        input.TryHandleKey(args);

    public void RenderGuidedSelection() => input.RenderGuidedSelection();

    internal void SetTool(GrainMendTool tool)
    {
        grainMend.Strokes.Select(tool);
        if (tool != GrainMendTool.Guided)
        {
            input.CancelGuidedDrag();
        }
        if (tool != GrainMendTool.None && crop?.IsActive == true)
        {
            // 크롭과 결함 도구는 같은 포인터를 두고 다툽니다. macOS 도 서로를 끕니다.
            endCropSession?.Invoke();
        }
        chrome.Update();
    }

    internal void SetStatus(string text) => setStatus?.Invoke(text);

    internal void RequestPreview() => requestPreview?.Invoke();

    internal void RequestPreviewReplacingCurrent() => replacePreview?.Invoke();

    private void OnSelectedFrameChanged(string? frameId)
    {
        // Select는 같은 사진의 recipe/preview snapshot을 다시 붙일 때도 발생합니다. 실제 ID가
        // 그대로면 활성 검출·검토·제거 작업을 사진 전환으로 오인해 폐기하지 않습니다.
        if (grainMend.OwnsFrame(frameId))
        {
            chrome.Update();
            return;
        }
        removingAcceptance = null;
        CancelDevelopedPresentation();
        ResetDefectPreviewBuild();
        grainMend.ChangeFrame(frameId);
        if (grainMend.Strokes.Tool == GrainMendTool.Guided)
        {
            SetTool(GrainMendTool.None);
        }
        input.CancelGuidedDrag();
        review.HideOverlay();
        SetStatus(string.Empty);
        chrome.Update();
    }

    /// <summary>macOS <c>exitActiveDevelopInteraction</c>의 region mode 종료입니다.</summary>
    internal bool TryExitRegionDefectInteraction()
    {
        if (grainMend.ActiveRegionKind is null &&
            grainMend.Strokes.Tool == GrainMendTool.None &&
            !isRemovingDefects)
        {
            return false;
        }
        CancelRegionDefectSession();
        SetTool(GrainMendTool.None);
        return true;
    }

    internal Task PrepareForTerminationAsync()
    {
        removingAcceptance = null;
        CancelDevelopedPresentation();
        ResetDefectPreviewBuild();
        grainMend.ChangeFrame(panel?.SelectedFrame?.Id);
        SetTool(GrainMendTool.None);
        input.CancelGuidedDrag();
        review.HideOverlay();
        chrome.Update();
        return detector.DrainAsync();
    }

    private void CancelRegionDefectSession()
    {
        removingAcceptance = null;
        grainMend.ExitRegionMode();
        review.HideOverlay();
        SetStatus(string.Empty);
        chrome.Update();
    }

    private async void OnGrainMendAutoClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        await RunAutoDefectAsync();
    }

    private void OnGrainMendGuidedClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ToggleGuidedDefect();
    }

    private void OnGrainMendBrushClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ToggleBrushDefect();
    }

    private void OnGrainMendCloneClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ToggleCloneStamp();
    }

    private void OnGrainMendAutoResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        CancelRegionDefectSession();
        SetTool(GrainMendTool.None);
        review.RemoveEdits(DefectEditKind.Region);
    }

    private void OnGrainMendGuidedResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        CancelRegionDefectSession();
        SetTool(GrainMendTool.None);
        review.RemoveEdits(DefectEditKind.Region);
    }

    private void OnGrainMendBrushResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        review.RemoveEdits(DefectEditKind.Brush);
    }

    private void OnGrainMendCloneResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        review.RemoveEdits(DefectEditKind.Clone);
    }

}
