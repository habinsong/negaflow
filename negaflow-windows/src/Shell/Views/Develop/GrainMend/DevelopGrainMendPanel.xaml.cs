using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
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
    internal bool updatingGrainMendSensitivity;
    internal bool updatingGrainMendMicroSpecks;
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

    private async void OnGrainMendAutoClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        SetTool(GrainMendTool.None);
        await detector.DetectAsync(new DefectRect(0.0, 0.0, 1.0, 1.0));
    }

    private void OnGrainMendGuidedClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        review.ClearPending();
        SetTool(grainMend.Strokes.Tool == GrainMendTool.Guided
            ? GrainMendTool.None
            : GrainMendTool.Guided);
        if (grainMend.Strokes.Tool == GrainMendTool.Guided)
        {
            canvas?.FocusHost();
        }
    }

    private void OnGrainMendBrushClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        SetTool(grainMend.Strokes.Tool == GrainMendTool.Brush
            ? GrainMendTool.None
            : GrainMendTool.Brush);
    }

    private void OnGrainMendCloneClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        SetTool(grainMend.Strokes.Tool == GrainMendTool.Clone
            ? GrainMendTool.None
            : GrainMendTool.Clone);
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

    private void OnGrainMendRemoveClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        review.AcceptPending();
    }

    private void OnGrainMendCancelClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        review.CancelPending();
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
        options.SetSensitivity(
            grainMend.PendingEdit.Label.Kind == DefectEditLabelKind.Automatic,
            args.NewValue);
    }

    private async void OnGrainMendSensitivityPointerReleased(
        object sender,
        PointerRoutedEventArgs args)
    {
        _ = sender;
        args.Handled = true;
        await detector.RedetectForSensitivityAsync();
    }

    private async void OnGrainMendSensitivityKeyUp(object sender, KeyRoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        await detector.RedetectForSensitivityAsync();
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
        options.SetMicroSpecks(automatic, GrainMendMicroSpecksToggle.IsOn);
        await detector.DetectAsync(rawRoi);
    }
}
