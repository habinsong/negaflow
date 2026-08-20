using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Windows.System;

namespace Negaflow.Shell.Views.Develop.Canvas;

/// <summary>macOS <c>CanvasToolHUD</c>.</summary>
public sealed partial class CanvasToolHud : UserControl
{
    private CanvasViewportState? viewport;
    private Func<(double Width, double Height)>? canvasSize;
    private Func<(double Width, double Height)?>? imageSize;
    private Action? applied;

    public CanvasToolHud()
    {
        InitializeComponent();
        ApplyChrome(CanvasHudChrome.For(CanvasBackgroundKind.Black));
    }

    public void Bind(
        CanvasViewportState viewportState,
        Func<(double Width, double Height)> canvasSizeSource,
        Func<(double Width, double Height)?> imageSizeSource,
        Action onApplied)
    {
        ArgumentNullException.ThrowIfNull(viewportState);
        ArgumentNullException.ThrowIfNull(canvasSizeSource);
        ArgumentNullException.ThrowIfNull(imageSizeSource);
        ArgumentNullException.ThrowIfNull(onApplied);
        viewport = viewportState;
        canvasSize = canvasSizeSource;
        imageSize = imageSizeSource;
        applied = onApplied;
        RefreshZoomText();
    }

    public void Localize()
    {
        SetHelp(ZoomOutButton, AppResources.Get("canvasZoomOut", "Text"));
        SetHelp(ZoomInButton, AppResources.Get("canvasZoomIn", "Text"));
        SetHelp(ZoomPercentButton, AppResources.Get("canvasZoomPercentHelp", "Text"));
        SetHelp(FitButton, AppResources.Get("canvasFitToScreen", "Text"));
        SetHelp(ActualSizeButton, AppResources.Get("canvasActualSize", "Text"));
        ZoomApplyButton.Content = AppResources.Get("canvasZoomApply", "Text");
        RefreshZoomText();
    }

    public void RefreshZoomText()
    {
        ZoomPercentText.Text = viewport?.ZoomText ?? "100%";
    }

    public void ApplyChrome(CanvasHudChrome chrome)
    {
        Windows.UI.Color content = ColorHelper.FromArgb(255, chrome.ContentByte, chrome.ContentByte, chrome.ContentByte);
        Windows.UI.Color surface = ColorHelper.FromArgb(255, chrome.SurfaceByte, chrome.SurfaceByte, chrome.SurfaceByte);
        if (Resources["HudContentBrush"] is SolidColorBrush brush)
        {
            brush.Color = content;
        }

        Surface.Background = new SolidColorBrush(surface);
        Surface.BorderBrush = new SolidColorBrush(
            ColorHelper.FromArgb(chrome.StrokeAlpha, chrome.ContentByte, chrome.ContentByte, chrome.ContentByte));
        ZoomPercentText.Foreground = new SolidColorBrush(content);
        ZoomPercentSuffix.Foreground = new SolidColorBrush(content);
    }

    private void OnZoomOutClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ZoomBy(1 / CanvasToolHudPolicy.ZoomStep);
    }

    private void OnZoomInClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ZoomBy(CanvasToolHudPolicy.ZoomStep);
    }

    private void OnFitClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (viewport is null)
        {
            return;
        }

        viewport.Reset();
        RefreshZoomText();
        applied?.Invoke();
    }

    private void OnActualSizeClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (viewport is null || !TrySizes(out double imageWidth, out double imageHeight, out double canvasWidth, out double canvasHeight))
        {
            return;
        }

        double actual = viewport.ActualSizeScale(imageWidth, imageHeight, canvasWidth, canvasHeight);
        viewport.SetScale(actual, imageWidth, imageHeight, canvasWidth, canvasHeight);
        RefreshZoomText();
        applied?.Invoke();
    }

    private void OnZoomPercentClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ZoomPercentField.Text = (viewport?.ZoomText ?? "100%").Replace("%", string.Empty, StringComparison.Ordinal);
        ZoomPercentField.SelectAll();
    }

    private void OnZoomApplyClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ApplyZoomPercent();
    }

    private void OnZoomPercentKeyDown(object sender, KeyRoutedEventArgs args)
    {
        _ = sender;
        if (args.Key != VirtualKey.Enter)
        {
            return;
        }

        ApplyZoomPercent();
        args.Handled = true;
    }

    private void ApplyZoomPercent()
    {
        if (viewport is null ||
            !TrySizes(out double imageWidth, out double imageHeight, out double canvasWidth, out double canvasHeight))
        {
            return;
        }

        if (!viewport.TryApplyZoomPercentText(
                ZoomPercentField.Text,
                imageWidth,
                imageHeight,
                canvasWidth,
                canvasHeight))
        {
            return;
        }

        ZoomEditorFlyout.Hide();
        RefreshZoomText();
        applied?.Invoke();
    }

    private void ZoomBy(double multiplier)
    {
        if (viewport is null ||
            !TrySizes(out double imageWidth, out double imageHeight, out double canvasWidth, out double canvasHeight))
        {
            return;
        }

        viewport.ZoomBy(multiplier, imageWidth, imageHeight, canvasWidth, canvasHeight);
        RefreshZoomText();
        applied?.Invoke();
    }

    private bool TrySizes(
        out double imageWidth,
        out double imageHeight,
        out double canvasWidth,
        out double canvasHeight)
    {
        imageWidth = 0;
        imageHeight = 0;
        canvasWidth = 0;
        canvasHeight = 0;
        if (canvasSize is null || imageSize is null)
        {
            return false;
        }

        (canvasWidth, canvasHeight) = canvasSize();
        if (imageSize() is not { } image)
        {
            return false;
        }

        imageWidth = image.Width;
        imageHeight = image.Height;
        return imageWidth > 0 && imageHeight > 0 && canvasWidth > 0 && canvasHeight > 0;
    }

    private static void SetHelp(Button button, string text)
    {
        AutomationProperties.SetName(button, text);
        ToolTipService.SetToolTip(button, text);
    }
}
