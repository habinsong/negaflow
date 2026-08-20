using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Develop.Canvas;

/// <summary>macOS <c>CanvasCompareToggle</c>.</summary>
public sealed partial class CanvasCompareHud : UserControl
{
    private CanvasCompareState? compare;
    private Action<CanvasCompareMode>? selected;

    public CanvasCompareHud()
    {
        InitializeComponent();
        ApplyChrome(CanvasHudChrome.For(CanvasBackgroundKind.Black));
    }

    public void Bind(CanvasCompareState state, Action<CanvasCompareMode> onSelect)
    {
        ArgumentNullException.ThrowIfNull(state);
        ArgumentNullException.ThrowIfNull(onSelect);
        compare = state;
        selected = onSelect;
        Refresh();
    }

    public void Localize()
    {
        RawText.Text = AppResources.Get("canvasCompareRaw", "Text");
        DevelopedText.Text = AppResources.Get("canvasCompareDeveloped", "Text");
        AutomationProperties.SetName(RawButton, RawText.Text);
        AutomationProperties.SetName(DevelopedButton, DevelopedText.Text);
        SetHelp(SplitVerticalButton, AppResources.Get("canvasCompareSplitVertical", "Text"));
        SetHelp(SplitHorizontalButton, AppResources.Get("canvasCompareSplitHorizontal", "Text"));
        Refresh();
    }

    public void Refresh()
    {
        if (compare is null)
        {
            return;
        }

        Paint(RawButton, RawText, compare.ActiveMode == CanvasCompareMode.Raw);
        Paint(DevelopedButton, DevelopedText, compare.ActiveMode == CanvasCompareMode.Developed);
        Paint(SplitVerticalButton, null, compare.ActiveMode == CanvasCompareMode.SplitVertical);
        Paint(SplitHorizontalButton, null, compare.ActiveMode == CanvasCompareMode.SplitHorizontal);
    }

    public void ApplyChrome(CanvasHudChrome chrome)
    {
        Windows.UI.Color content = ColorHelper.FromArgb(255, chrome.ContentByte, chrome.ContentByte, chrome.ContentByte);
        Windows.UI.Color surface = ColorHelper.FromArgb(255, chrome.SurfaceByte, chrome.SurfaceByte, chrome.SurfaceByte);
        if (Resources["CompareContentBrush"] is SolidColorBrush brush)
        {
            brush.Color = content;
        }

        Surface.Background = new SolidColorBrush(surface);
        Surface.BorderBrush = new SolidColorBrush(
            ColorHelper.FromArgb(chrome.StrokeAlpha, chrome.ContentByte, chrome.ContentByte, chrome.ContentByte));
        Refresh();
    }

    private void OnRawClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        selected?.Invoke(CanvasCompareMode.Raw);
    }

    private void OnDevelopedClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        selected?.Invoke(CanvasCompareMode.Developed);
    }

    private void OnSplitVerticalClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        selected?.Invoke(CanvasCompareMode.SplitVertical);
    }

    private void OnSplitHorizontalClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        selected?.Invoke(CanvasCompareMode.SplitHorizontal);
    }

    private void Paint(Button button, TextBlock? label, bool active)
    {
        CanvasHudChrome chrome = CanvasHudChrome.For(CanvasBackgroundKind.Black);
        Windows.UI.Color content = ColorHelper.FromArgb(255, chrome.ContentByte, chrome.ContentByte, chrome.ContentByte);
        byte inactive = (byte)Math.Round(255 * CanvasCompareHudPolicy.InactiveContentOpacity, MidpointRounding.AwayFromZero);
        byte fill = (byte)Math.Round(255 * CanvasCompareHudPolicy.ActiveFillOpacity, MidpointRounding.AwayFromZero);
        Windows.UI.Color foreground = active
            ? content
            : ColorHelper.FromArgb(inactive, chrome.ContentByte, chrome.ContentByte, chrome.ContentByte);
        button.Background = active
            ? new SolidColorBrush(ColorHelper.FromArgb(fill, chrome.ContentByte, chrome.ContentByte, chrome.ContentByte))
            : new SolidColorBrush(Colors.Transparent);
        if (label is not null)
        {
            label.Foreground = new SolidColorBrush(foreground);
            label.FontWeight = active
                ? Microsoft.UI.Text.FontWeights.SemiBold
                : Microsoft.UI.Text.FontWeights.Normal;
        }
        else
        {
            button.Opacity = active ? 1 : CanvasCompareHudPolicy.InactiveContentOpacity;
        }
    }

    private static void SetHelp(Button button, string text)
    {
        AutomationProperties.SetName(button, text);
        ToolTipService.SetToolTip(button, text);
    }
}
