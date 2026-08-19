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
    internal readonly GrainMendWorkspaceState grainMend = new();

    /// <summary>
    /// "결함 제거"가 도는 중입니다. macOS 는 이 동안 단추 안을 프로그래스로 바꿉니다.
    /// Windows 의 수락은 아직 동기라 눈에 보일 틈이 없지만, 상태는 어긋나지 않게 둡니다.
    /// </summary>
    internal bool isRemovingDefects;
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
        Action<string> status,
        Action preview)
    {
        ArgumentNullException.ThrowIfNull(workspace);
        ArgumentNullException.ThrowIfNull(cropState);
        ArgumentNullException.ThrowIfNull(previewCanvas);
        ArgumentNullException.ThrowIfNull(endCrop);
        ArgumentNullException.ThrowIfNull(status);
        ArgumentNullException.ThrowIfNull(preview);
        workspaceState = workspace;
        crop = cropState;
        canvas = previewCanvas;
        endCropSession = endCrop;
        setStatus = status;
        requestPreview = preview;
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
        hud.BrushResetRequested += () => review.RemoveEdits(DefectEditKind.Brush);
        hud.BrushApplyRequested += OnHudBrushApplyRequested;
        hud.CloneDiameterChanged += OnHudCloneDiameterChanged;
        hud.CloneHardnessChanged += OnHudCloneHardnessChanged;
        hud.CloneUndoRequested += () => review.RemoveEdits(DefectEditKind.Clone);
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
    private void OnHudBrushApplyRequested()
    {
        if (panel is null ||
            !grainMend.Strokes.ApplyPaintedStrokes(panel, out LibraryFrameError error))
        {
            return;
        }
        review.RenderPaintOverlay();
        chrome.Update();
        if (error == LibraryFrameError.None)
        {
            RequestPreview();
        }
    }

    private void OnHudSensitivityChanged(double value)
    {
        if (grainMend.PendingEdit is null)
        {
            return;
        }
        options.SetSensitivity(
            grainMend.PendingEdit.Label.Kind == DefectEditLabelKind.Automatic,
            value);
    }

    private async void OnHudSensitivityCommitted() =>
        await detector.RedetectForSensitivityAsync();

    private async void OnHudMicroSpecksToggled(bool enabled)
    {
        // 검토 중이 아니면(가이드를 켜 두고 기다리는 중) 값만 담아 둡니다. macOS 도 이때는
        // 재검출하지 않습니다 — 아직 검출한 것이 없습니다.
        bool automatic = grainMend.PendingEdit?.Label.Kind == DefectEditLabelKind.Automatic;
        options.SetMicroSpecks(automatic, enabled);
        if (grainMend.PendingEdit is null || grainMend.PendingRawRoi is not { } rawRoi ||
            grainMend.IsDetecting)
        {
            return;
        }
        await detector.DetectAsync(rawRoi);
    }

    private void OnHudRemoveRequested()
    {
        isRemovingDefects = true;
        try
        {
            review.AcceptPending();
        }
        finally
        {
            isRemovingDefects = false;
        }
        chrome.Update();
    }

    /// <summary>
    /// 종류별 칩 한 번입니다. 그 종류 전체를 제외↔포함하고 덮개를 다시 칠합니다 — macOS
    /// <c>toggleRegionClass</c> 와 같이 재검출은 없습니다.
    /// </summary>
    private void OnHudClassToggled(DefectClassification classification)
    {
        if (grainMend.PendingReview?.ToggleClass(classification) != true ||
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
        panel = hostPanel;
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
        input.EndGuidedSelection(args);

    public bool TryHandleKeyDown(KeyRoutedEventArgs args) =>
        input.TryHandleKey(args);

    public void RenderGuidedSelection() => input.RenderGuidedSelection();

    internal void SetTool(GrainMendTool tool)
    {
        if (grainMend.Strokes.Tool == tool)
        {
            return;
        }
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

    /// <summary>
    /// macOS <c>handleDevelopToolShortcutRequest</c> 의 <c>.autoDefectTool</c> — 전체 프레임
    /// 표시 ROI(0,0,1,1)로 검출을 겁니다. 칩을 누른 것과 같은 길입니다.
    /// </summary>
    internal Task RunAutoDefectAsync()
    {
        SetTool(GrainMendTool.None);
        return detector.DetectAsync(new DefectRect(0.0, 0.0, 1.0, 1.0));
    }

    /// <summary>macOS <c>.guidedDefectTool</c> — 켜져 있으면 끕니다.</summary>
    internal void ToggleGuidedDefect()
    {
        review.ClearPending();
        SetTool(grainMend.Strokes.Tool == GrainMendTool.Guided
            ? GrainMendTool.None
            : GrainMendTool.Guided);
        if (grainMend.Strokes.Tool == GrainMendTool.Guided)
        {
            canvas?.FocusHost();
        }
    }

    /// <summary>macOS <c>.brushDefectTool</c> — 켜져 있으면 끕니다.</summary>
    internal void ToggleBrushDefect() =>
        SetTool(grainMend.Strokes.Tool == GrainMendTool.Brush
            ? GrainMendTool.None
            : GrainMendTool.Brush);

    /// <summary>macOS <c>.cloneStampTool</c> — 켜져 있으면 끕니다.</summary>
    internal void ToggleCloneStamp() =>
        SetTool(grainMend.Strokes.Tool == GrainMendTool.Clone
            ? GrainMendTool.None
            : GrainMendTool.Clone);

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
        review.ClearPending();
        review.RemoveEdits(DefectEditLabelKind.Automatic);
    }

    private void OnGrainMendGuidedResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        review.ClearPending();
        review.RemoveEdits(DefectEditLabelKind.Guided);
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
