using System.IO;
using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Develop.Canvas;

/// <summary>
/// 현상 미리보기 캔버스입니다. 사진·크롭 오버레이·픽셀 샘플러·결함 덮개를 그립니다.
/// GrainMend 도구 판정은 뷰가 콜백으로 먼저 받습니다.
/// </summary>
public sealed partial class DevelopPreviewCanvas : UserControl
{
    private CropWorkspaceState? crop;
    private CanvasViewportState? viewport;
    private CanvasCompareState? compare;
    private WriteableBitmap? previewBitmap;
    private WriteableBitmap? compareBeforeBitmap;
    private bool draggingCompareDivider;
    private readonly CanvasHudInteractionState hudInteraction = new();
    private CanvasHudKind? hudPressKind;
    private double hudPressX;
    private double hudPressY;
    private double hudPressOriginX;
    private double hudPressOriginY;
    private bool hudDragging;

    /// <summary>직전 치수의 비트맵입니다. 인터랙티브↔정착이 번갈아 올 때 다시 씁니다.</summary>
    private WriteableBitmap? spareBitmap;
    private readonly DevelopCanvasSampler sampler;
    private readonly DevelopCropOverlayPresenter cropOverlay;
    private readonly DevelopCanvasGuidedOverlay guided;
    private readonly DevelopCanvasDefectOverlay defects;
    private readonly DevelopCanvasCropInteraction cropInteraction;

    public DevelopPreviewCanvas()
    {
        InitializeComponent();
        sampler = new DevelopCanvasSampler(this);
        cropOverlay = new DevelopCropOverlayPresenter(this);
        guided = new DevelopCanvasGuidedOverlay(this);
        defects = new DevelopCanvasDefectOverlay(this);
        cropInteraction = new DevelopCanvasCropInteraction(this);
    }

    /// <summary>적용 단추입니다. 카탈로그 쓰기는 뷰가 맡습니다.</summary>
    public event EventHandler? CropApplyRequested;

    /// <summary>취소 단추와 Esc 입니다. 세션 종료는 뷰가 맡습니다.</summary>
    public event EventHandler? CropCancelRequested;

    /// <summary>전체 프레임 단추입니다. 세션 갱신은 뷰가 맡습니다.</summary>
    public event EventHandler? CropFullRequested;

    /// <summary>호스트 크기가 바뀌면 올립니다. 가이드 선택 사각형을 다시 놓습니다.</summary>
    public event EventHandler<SizeChangedEventArgs>? HostSizeChanged;

    /// <summary>GrainMend 가 포인터를 먼저 받을 때 씁니다. true 면 크롭은 건너뜁니다.</summary>
    public Func<PointerRoutedEventArgs, bool>? TryHandlePointerPressed { get; set; }

    public Func<PointerRoutedEventArgs, bool>? TryHandlePointerMoved { get; set; }

    public Func<PointerRoutedEventArgs, bool>? TryHandlePointerReleased { get; set; }

    public Action<PointerRoutedEventArgs>? HandlePointerCancelled { get; set; }

    public Func<KeyRoutedEventArgs, bool>? TryHandleKeyDown { get; set; }

    public WriteableBitmap? PreviewBitmap => previewBitmap;

    /// <summary>
    /// 화면에 그린 미리보기 화소(BGRA8)입니다. macOS <c>CanvasView</c> 가 복제 도장에
    /// <c>referenceImage: image</c> 로 넘기는 것과 같은 것입니다.
    /// </summary>
    public byte[]? PreviewPixels => sampler.PreviewPixels;

    public bool HasPreview => PreviewImage.Visibility == Visibility.Visible;

    public bool HasCompareBefore => compareBeforeBitmap is not null;

    public void Attach(CropWorkspaceState cropState)
    {
        ArgumentNullException.ThrowIfNull(cropState);
        crop = cropState;
    }

    /// <summary>macOS <c>CanvasView.viewport</c> + <c>movableZoomHUD</c>.</summary>
    public void AttachViewport(CanvasViewportState viewportState)
    {
        ArgumentNullException.ThrowIfNull(viewportState);
        viewport = viewportState;
        ZoomHud.Bind(
            viewportState,
            () => (CanvasHost.ActualWidth, CanvasHost.ActualHeight),
            () => previewBitmap is null
                ? null
                : (previewBitmap.PixelWidth, previewBitmap.PixelHeight),
            ApplyImageFrame);
    }

    /// <summary>macOS <c>beforeAfterToggle</c> + <c>compareLabels</c>.</summary>
    public void AttachCompare(
        CanvasCompareState state,
        Action<CanvasCompareMode> onSelectMode,
        Action<string> onSelectBefore)
    {
        ArgumentNullException.ThrowIfNull(state);
        ArgumentNullException.ThrowIfNull(onSelectMode);
        ArgumentNullException.ThrowIfNull(onSelectBefore);
        compare = state;
        CompareHud.Bind(state, onSelectMode);
        CompareLabels.Bind(state, onSelectBefore, () => onSelectMode(CanvasCompareMode.Developed));
    }

    public void SetCompareFrameOptions(IReadOnlyList<CanvasCompareBeforeOption> options) =>
        CompareLabels.SetFrameOptions(options);

    public void BindSampler(
        Func<bool> isEnabled,
        Func<string?> selectedSourcePath,
        Func<bool> displayedIsProof)
    {
        sampler.Bind(isEnabled, selectedSourcePath, displayedIsProof);
    }

    public void KeepPreviewPixels(byte[]? pixels, uint width, uint height) =>
        sampler.KeepPreviewPixels(pixels, width, height);

    public void FocusHost() => _ = CanvasHost.Focus(FocusState.Programmatic);

    public void CaptureHost(Microsoft.UI.Xaml.Input.Pointer pointer) =>
        CanvasHost.CapturePointer(pointer);

    public void ReleaseHost(Microsoft.UI.Xaml.Input.Pointer pointer) =>
        CanvasHost.ReleasePointerCapture(pointer);

    public bool TryMapPointer(PointerRoutedEventArgs args, out CropDisplayPoint point)
    {
        Windows.Foundation.Point position = args.GetCurrentPoint(CanvasHost).Position;
        if (!TryGetPreviewFrame(out PreviewFrame frame))
        {
            point = default;
            return false;
        }
        return frame.TryMapPoint(position.X, position.Y, out point);
    }

    public bool TryGetPreviewFrame(out PreviewFrame frame)
    {
        if (previewBitmap is null)
        {
            frame = default;
            return false;
        }
        if (viewport is not null)
        {
            return PreviewFrame.TryFromViewport(
                CanvasHost.ActualWidth,
                CanvasHost.ActualHeight,
                previewBitmap.PixelWidth,
                previewBitmap.PixelHeight,
                viewport.Scale,
                viewport.OffsetX,
                viewport.OffsetY,
                out frame);
        }

        return PreviewFrame.TryFrom(
            CanvasHost.ActualWidth,
            CanvasHost.ActualHeight,
            previewBitmap.PixelWidth,
            previewBitmap.PixelHeight,
            out frame);
    }

    public void ShowEmpty()
    {
        PreviewImage.Visibility = Visibility.Collapsed;
        HideCompareBefore();
        CompareHud.Visibility = Visibility.Collapsed;
        EmptyCanvasPanel.Visibility = Visibility.Visible;
    }

    public void Present(byte[] pixels, int width, int height)
    {
        // 크기가 바뀔 때만 새로 만듭니다. 슬라이더를 끄는 동안 매 프레임 할당하지 않기 위해서입니다.
        //
        // ☠️ 두 벌을 들고 있는 이유: 한 번의 편집이 **인터랙티브 패스와 정착 패스** 두 그림을
        //    보내고 둘의 치수가 다릅니다(예 2304 상자 → 2304×1540, 정착 3600 → 3600×2406).
        //    한 벌만 들면 두 패스가 서로를 밀어내 **슬라이더 한 칸마다 두 번** 새 비트맵을
        //    할당했습니다 — 정착본 하나가 34.6MB 라 UI 스레드에 그대로 얹혔습니다.
        if (previewBitmap is null ||
            previewBitmap.PixelWidth != width ||
            previewBitmap.PixelHeight != height)
        {
            if (spareBitmap is { } spare &&
                spare.PixelWidth == width &&
                spare.PixelHeight == height)
            {
                spareBitmap = previewBitmap;
                previewBitmap = spare;
            }
            else
            {
                spareBitmap = previewBitmap;
                previewBitmap = new WriteableBitmap(width, height);
            }
            PreviewImage.Source = previewBitmap;
        }

        int written = width * height * 4;
        using (Stream buffer = previewBitmap.PixelBuffer.AsStream())
        {
            buffer.Write(pixels, 0, written);
        }
        previewBitmap.Invalidate();
        // 자리표시자(사진을 막 바꿨을 때의 썸네일)가 걸려 있으면 여기서 되돌립니다.
        // `Present` 는 크기가 같으면 비트맵을 다시 만들지 않으므로 Source 를 확인해야 합니다.
        if (!ReferenceEquals(PreviewImage.Source, previewBitmap))
        {
            PreviewImage.Source = previewBitmap;
        }
        PreviewImage.Visibility = Visibility.Visible;
        EmptyCanvasPanel.Visibility = Visibility.Collapsed;
        ApplyImageFrame();
        ZoomHud.RefreshZoomText();
        CompareHud.Visibility = Visibility.Visible;
        CompareHud.Refresh();
        ApplyHudLayout();
    }

    /// <summary>macOS unedited / raw <c>beforeImage</c>.</summary>
    public void PresentCompareBefore(byte[] pixels, int width, int height)
    {
        if (compareBeforeBitmap is null ||
            compareBeforeBitmap.PixelWidth != width ||
            compareBeforeBitmap.PixelHeight != height)
        {
            compareBeforeBitmap = new WriteableBitmap(width, height);
            CompareBeforeImage.Source = compareBeforeBitmap;
        }

        int written = width * height * 4;
        using (Stream buffer = compareBeforeBitmap.PixelBuffer.AsStream())
        {
            buffer.Write(pixels, 0, written);
        }

        compareBeforeBitmap.Invalidate();
        if (compare is not null)
        {
            compare.CanCompare = true;
        }

        ApplyImageFrame();
        CompareHud.Refresh();
    }

    public void HideCompareBefore()
    {
        compareBeforeBitmap = null;
        CompareBeforeImage.Source = null;
        CompareBeforeImage.Visibility = Visibility.Collapsed;
        CompareDividerLayer.Visibility = Visibility.Collapsed;
        if (compare is not null)
        {
            compare.CanCompare = false;
        }

        CompareHud.Refresh();
    }

    public void RefreshCompare()
    {
        ApplyImageFrame();
        CompareHud.Refresh();
    }

    public void RenderCropOverlay()
    {
        if (crop is null || !TryGetPreviewFrame(out PreviewFrame frame))
        {
            cropOverlay.Hide();
            return;
        }
        cropOverlay.Render(crop, frame);
    }

    public void HideCropOverlay() => cropOverlay.Hide();

    public void ShowGuidedSelection(CropDisplayPoint start, CropDisplayPoint current)
    {
        if (!TryGetPreviewFrame(out PreviewFrame frame))
        {
            guided.Hide();
            return;
        }
        guided.Render(start, current, frame);
    }

    public void HideGuidedSelection() => guided.Hide();

    public void ShowDefectPixels(byte[] bgra, int width, int height) =>
        defects.Show(bgra, width, height);

    public void HideDefectOverlay() => defects.Hide();

    /// <summary>
    /// macOS <c>basePickerOverlay</c> — 스포이드 모드일 때만 안내 캡슐이 뜹니다.
    /// </summary>
    public void ShowBasePickerPrompt(bool visible)
    {
        BasePickerPrompt.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;
    }

    public void Localize()
    {
        EmptyCanvasTitleLocalized.Text = AppResources.Get("emptyCanvasTitle", "Text");
        EmptyCanvasDescriptionLocalized.Text =
            AppResources.Get("emptyCanvasDescription", "Text");
        BasePickerPromptText.Text = AppResources.Get("developBasePickerPrompt", "Text");
        ZoomHud.Localize();
        CompareHud.Localize();
        CompareLabels.Localize();
        SetButtonText(CropApplyButton, AppResources.Get("developCropApply", "Text"));
        SetButtonText(CropFullButton, AppResources.Get("developCropFull", "Text"));
        SetButtonText(CropCancelButton, AppResources.Get("developCropCancel", "Text"));
        AutomationProperties.SetName(CropSelection, AppResources.Get("developCropArea", "Text"));
    }

    internal void RaiseCropApply() => CropApplyRequested?.Invoke(this, EventArgs.Empty);

    internal void RaiseCropCancel() => CropCancelRequested?.Invoke(this, EventArgs.Empty);

    internal void RaiseCropFull() => CropFullRequested?.Invoke(this, EventArgs.Empty);

    private void OnCanvasSizeChanged(object sender, SizeChangedEventArgs args)
    {
        _ = sender;
        ApplyImageFrame();
        ApplyHudLayout();
        RenderCropOverlay();
        HostSizeChanged?.Invoke(this, args);
    }

    private void ApplyImageFrame()
    {
        if (!TryGetPreviewFrame(out PreviewFrame frame))
        {
            return;
        }

        PositionSurface(PreviewImage, frame);
        PositionSurface(DefectOverlayImage, frame);
        ApplyCompareLayout(frame);
        ApplyHudLayout();
    }

    private void ApplyHudLayout()
    {
        if (CanvasHost.ActualWidth <= 0 || CanvasHost.ActualHeight <= 0)
        {
            return;
        }

        if (CompareHud.ActualWidth > 0 && CompareHud.ActualHeight > 0)
        {
            hudInteraction.SetMeasuredSize(
                CanvasHudKind.Compare,
                CompareHud.ActualWidth,
                CompareHud.ActualHeight);
        }

        if (ZoomHud.ActualWidth > 0 && ZoomHud.ActualHeight > 0)
        {
            hudInteraction.SetMeasuredSize(
                CanvasHudKind.Zoom,
                ZoomHud.ActualWidth,
                ZoomHud.ActualHeight);
        }

        CanvasHudOrigins origins = hudInteraction.Resolve(CanvasHost.ActualWidth, CanvasHost.ActualHeight);
        CompareHud.Margin = new Thickness(origins.CompareX, origins.CompareY, 0, 0);
        ZoomHud.Margin = new Thickness(origins.ZoomX, origins.ZoomY, 0, 0);
    }

    private void OnCompareHudSizeChanged(object sender, SizeChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        ApplyHudLayout();
    }

    private void OnZoomHudSizeChanged(object sender, SizeChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        ApplyHudLayout();
    }

    private void OnCompareHudPointerPressed(object sender, PointerRoutedEventArgs args) =>
        BeginHudPress(CanvasHudKind.Compare, args);

    private void OnZoomHudPointerPressed(object sender, PointerRoutedEventArgs args) =>
        BeginHudPress(CanvasHudKind.Zoom, args);

    private void BeginHudPress(CanvasHudKind kind, PointerRoutedEventArgs args)
    {
        if (IsHudInteractiveSource(args.OriginalSource))
        {
            return;
        }

        Windows.Foundation.Point point = args.GetCurrentPoint(CanvasHost).Position;
        CanvasHudOrigins origins = hudInteraction.Resolve(CanvasHost.ActualWidth, CanvasHost.ActualHeight);
        hudPressKind = kind;
        hudPressX = point.X;
        hudPressY = point.Y;
        hudPressOriginX = kind == CanvasHudKind.Compare ? origins.CompareX : origins.ZoomX;
        hudPressOriginY = kind == CanvasHudKind.Compare ? origins.CompareY : origins.ZoomY;
        hudDragging = false;
    }

    private void OnHudPointerMoved(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        if (hudPressKind is not { } kind)
        {
            return;
        }

        Windows.Foundation.Point point = args.GetCurrentPoint(CanvasHost).Position;
        double translationX = point.X - hudPressX;
        double translationY = point.Y - hudPressY;
        if (!hudDragging)
        {
            if ((translationX * translationX) + (translationY * translationY) <
                CanvasHudInteractionState.MinimumDragDistance * CanvasHudInteractionState.MinimumDragDistance)
            {
                return;
            }

            hudDragging = true;
            CaptureHost(args.Pointer);
        }

        hudInteraction.BeginOrUpdateDrag(
            kind,
            translationX,
            translationY,
            hudPressOriginX,
            hudPressOriginY,
            CanvasHost.ActualWidth,
            CanvasHost.ActualHeight);
        ApplyHudLayout();
        args.Handled = true;
    }

    private void OnHudPointerReleased(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        EndHudDrag(args);
    }

    private void OnHudPointerCanceled(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        EndHudDrag(args);
    }

    private void EndHudDrag(PointerRoutedEventArgs args)
    {
        if (hudPressKind is not { } kind)
        {
            return;
        }

        if (hudDragging)
        {
            hudInteraction.EndDrag(kind);
            ReleaseHost(args.Pointer);
            args.Handled = true;
        }

        hudPressKind = null;
        hudDragging = false;
    }

    private static bool IsHudInteractiveSource(object source)
    {
        DependencyObject? current = source as DependencyObject;
        while (current is not null)
        {
            if (current is Button or TextBox)
            {
                return true;
            }

            current = VisualTreeHelper.GetParent(current);
        }

        return false;
    }

    private void ApplyCompareLayout(PreviewFrame frame)
    {
        CanvasCompareOrientation? split = compare is null
            ? null
            : CanvasCompareHudPolicy.SplitOrientation(compare.ActiveMode);
        bool showSplit = split is not null && compareBeforeBitmap is not null;
        CompareBeforeImage.Visibility = showSplit ? Visibility.Visible : Visibility.Collapsed;
        CompareDividerLayer.Visibility = showSplit ? Visibility.Visible : Visibility.Collapsed;
        CompareLabels.Visibility = showSplit ? Visibility.Visible : Visibility.Collapsed;
        if (showSplit && split is { } labelOrientation)
        {
            CompareLabels.Place(frame, labelOrientation);
            CompareLabels.Refresh();
        }
        if (!showSplit || compare is null || split is not { } orientation)
        {
            CompareBeforeImage.Clip = null;
            return;
        }

        PositionSurface(CompareBeforeImage, frame);
        double fraction = compare.Divider.Fraction(orientation);
        (double clipX, double clipY, double clipW, double clipH) = CanvasCompareDividerState.BeforeClip(
            0,
            0,
            frame.Width,
            frame.Height,
            orientation,
            fraction);
        CompareBeforeImage.Clip = new RectangleGeometry
        {
            Rect = new Windows.Foundation.Rect(clipX, clipY, clipW, clipH),
        };

        double line = compare.Divider.LinePosition(
            orientation == CanvasCompareOrientation.Vertical ? frame.Left : frame.Top,
            orientation == CanvasCompareOrientation.Vertical ? frame.Width : frame.Height,
            orientation);
        if (orientation == CanvasCompareOrientation.Vertical)
        {
            CompareDividerLine.Width = 1;
            CompareDividerLine.Height = frame.Height;
            Microsoft.UI.Xaml.Controls.Canvas.SetLeft(CompareDividerLine, line - 0.5);
            Microsoft.UI.Xaml.Controls.Canvas.SetTop(CompareDividerLine, frame.Top);
            CompareDividerHandle.Width = CanvasCompareDividerState.HandleShort;
            CompareDividerHandle.Height = CanvasCompareDividerState.HandleLong;
            Microsoft.UI.Xaml.Controls.Canvas.SetLeft(CompareDividerHandle, line - (CanvasCompareDividerState.HandleShort / 2));
            Microsoft.UI.Xaml.Controls.Canvas.SetTop(CompareDividerHandle, frame.Top + (frame.Height / 2) - (CanvasCompareDividerState.HandleLong / 2));
        }
        else
        {
            CompareDividerLine.Width = frame.Width;
            CompareDividerLine.Height = 1;
            Microsoft.UI.Xaml.Controls.Canvas.SetLeft(CompareDividerLine, frame.Left);
            Microsoft.UI.Xaml.Controls.Canvas.SetTop(CompareDividerLine, line - 0.5);
            CompareDividerHandle.Width = CanvasCompareDividerState.HandleLong;
            CompareDividerHandle.Height = CanvasCompareDividerState.HandleShort;
            Microsoft.UI.Xaml.Controls.Canvas.SetLeft(CompareDividerHandle, frame.Left + (frame.Width / 2) - (CanvasCompareDividerState.HandleLong / 2));
            Microsoft.UI.Xaml.Controls.Canvas.SetTop(CompareDividerHandle, line - (CanvasCompareDividerState.HandleShort / 2));
        }
    }

    private static void PositionSurface(FrameworkElement element, PreviewFrame frame)
    {
        element.HorizontalAlignment = HorizontalAlignment.Left;
        element.VerticalAlignment = VerticalAlignment.Top;
        element.Margin = new Thickness(frame.Left, frame.Top, 0, 0);
        element.Width = frame.Width;
        element.Height = frame.Height;
    }

    private void OnCanvasPointerPressed(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        if (TryBeginCompareDivider(args))
        {
            return;
        }
        if (TryHandlePointerPressed?.Invoke(args) == true)
        {
            return;
        }
        if (crop is not null)
        {
            cropInteraction.TryBeginDrag(args, crop);
        }
    }

    private void OnCanvasPointerMoved(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        // 샘플러는 다른 도구를 막지 않습니다 — 값을 읽기만 하므로 크롭이나 브러시와 함께
        // 돌아도 서로 방해하지 않습니다.
        sampler.Update(args);
        if (TryContinueCompareDivider(args))
        {
            return;
        }
        if (TryHandlePointerMoved?.Invoke(args) == true)
        {
            return;
        }
        if (crop is not null)
        {
            cropInteraction.TryContinueDrag(args, crop);
        }
    }

    private void OnCanvasPointerReleased(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        if (EndCompareDivider(args))
        {
            return;
        }
        if (TryHandlePointerReleased?.Invoke(args) == true)
        {
            return;
        }
        if (crop is not null)
        {
            cropInteraction.EndDrag(args, crop);
        }
    }

    private void OnCanvasPointerCancelled(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        EndCompareDivider(args);
        HandlePointerCancelled?.Invoke(args);
        if (crop is not null)
        {
            cropInteraction.EndDrag(args, crop);
        }
    }

    private void OnCanvasPointerCaptureLost(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        EndCompareDivider(args);
        HandlePointerCancelled?.Invoke(args);
        if (crop is not null)
        {
            cropInteraction.EndDrag(args, crop);
        }
    }

    private bool TryBeginCompareDivider(PointerRoutedEventArgs args)
    {
        if (compare is null ||
            CanvasCompareHudPolicy.SplitOrientation(compare.ActiveMode) is not { } orientation ||
            compareBeforeBitmap is null ||
            !TryGetPreviewFrame(out PreviewFrame frame))
        {
            return false;
        }

        Windows.Foundation.Point point = args.GetCurrentPoint(CanvasHost).Position;
        if (!compare.Divider.HitTest(
                point.X,
                point.Y,
                frame.Left,
                frame.Top,
                frame.Width,
                frame.Height,
                orientation))
        {
            return false;
        }

        draggingCompareDivider = true;
        double pointer = orientation == CanvasCompareOrientation.Vertical ? point.X : point.Y;
        double origin = orientation == CanvasCompareOrientation.Vertical ? frame.Left : frame.Top;
        double length = orientation == CanvasCompareOrientation.Vertical ? frame.Width : frame.Height;
        compare.Divider.BeginOrUpdateDrag(pointer, 0, origin, length, orientation);
        CaptureHost(args.Pointer);
        args.Handled = true;
        ApplyImageFrame();
        return true;
    }

    private bool TryContinueCompareDivider(PointerRoutedEventArgs args)
    {
        if (!draggingCompareDivider ||
            compare is null ||
            CanvasCompareHudPolicy.SplitOrientation(compare.ActiveMode) is not { } orientation ||
            !TryGetPreviewFrame(out PreviewFrame frame))
        {
            return false;
        }

        Windows.Foundation.Point point = args.GetCurrentPoint(CanvasHost).Position;
        double pointer = orientation == CanvasCompareOrientation.Vertical ? point.X : point.Y;
        double origin = orientation == CanvasCompareOrientation.Vertical ? frame.Left : frame.Top;
        double length = orientation == CanvasCompareOrientation.Vertical ? frame.Width : frame.Height;
        compare.Divider.BeginOrUpdateDrag(pointer, 1, origin, length, orientation);
        args.Handled = true;
        ApplyImageFrame();
        return true;
    }

    private bool EndCompareDivider(PointerRoutedEventArgs args)
    {
        if (!draggingCompareDivider)
        {
            return false;
        }

        draggingCompareDivider = false;
        compare?.Divider.EndDrag();
        ReleaseHost(args.Pointer);
        args.Handled = true;
        return true;
    }

    private void OnCanvasKeyDown(object sender, KeyRoutedEventArgs args)
    {
        _ = sender;
        if (TryHandleKeyDown?.Invoke(args) == true)
        {
            return;
        }
        if (crop is not null)
        {
            cropInteraction.TryHandleKey(args, crop);
        }
    }

    private void OnCropApplyClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        RaiseCropApply();
    }

    private void OnCropFullClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        RaiseCropFull();
    }

    private void OnCropCancelClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        RaiseCropCancel();
    }

    private static void SetButtonText(Button button, string text)
    {
        button.Content = text;
        AutomationProperties.SetName(button, text);
        ToolTipService.SetToolTip(button, text);
    }
}
