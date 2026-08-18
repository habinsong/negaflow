using System.IO;
using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
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
    private WriteableBitmap? previewBitmap;
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

    public void Attach(CropWorkspaceState cropState)
    {
        ArgumentNullException.ThrowIfNull(cropState);
        crop = cropState;
    }

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
        EmptyCanvasPanel.Visibility = Visibility.Visible;
    }

    public void Present(byte[] pixels, int width, int height)
    {
        // 크기가 바뀔 때만 새로 만듭니다. 슬라이더를 끄는 동안 매 프레임 할당하지 않기 위해서입니다.
        if (previewBitmap is null ||
            previewBitmap.PixelWidth != width ||
            previewBitmap.PixelHeight != height)
        {
            previewBitmap = new WriteableBitmap(width, height);
            PreviewImage.Source = previewBitmap;
        }

        int written = width * height * 4;
        using (Stream buffer = previewBitmap.PixelBuffer.AsStream())
        {
            buffer.Write(pixels, 0, written);
        }
        previewBitmap.Invalidate();
        PreviewImage.Visibility = Visibility.Visible;
        EmptyCanvasPanel.Visibility = Visibility.Collapsed;
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
        BasePickerPromptText.Text = AppResources.Get("developBasePickerPrompt", "Text");
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
        RenderCropOverlay();
        HostSizeChanged?.Invoke(this, args);
    }

    private void OnCanvasPointerPressed(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
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
        HandlePointerCancelled?.Invoke(args);
        if (crop is not null)
        {
            cropInteraction.EndDrag(args, crop);
        }
    }

    private void OnCanvasPointerCaptureLost(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        HandlePointerCancelled?.Invoke(args);
        if (crop is not null)
        {
            cropInteraction.EndDrag(args, crop);
        }
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
