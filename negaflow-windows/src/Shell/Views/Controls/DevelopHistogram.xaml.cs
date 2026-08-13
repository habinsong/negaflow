using System.Globalization;
using System.Threading;
using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Negaflow.Shell;
using Windows.Foundation;
using Windows.System;
using Windows.UI.Core;

namespace Negaflow.Shell.Views.Controls;

public enum DevelopHistogramRegion
{
    Shadow,
    Density,
    Exposure,
    Highlight,
}

public sealed class DevelopHistogramValueChangedEventArgs(
    DevelopHistogramRegion region,
    double value) : EventArgs
{
    public DevelopHistogramRegion Region { get; } = region;

    public double Value { get; } = value;
}

public sealed partial class DevelopHistogram : UserControl
{
    private readonly double[] values = new double[4];
    private DevelopHistogramBins? bins;
    private DevelopHistogramRegion selectedRegion = DevelopHistogramRegion.Exposure;
    private DevelopHistogramRegion activeRegion = DevelopHistogramRegion.Exposure;
    private bool isDragging;
    private double dragStartX;
    private double dragStartValue;
    private double maximumExposure = 4;
    private double maximumToneControl = 1;
    private int generation;
    private string clippingFormat = "Clip %@";
    private string redChannelShort = "R";
    private string greenChannelShort = "G";
    private string blueChannelShort = "B";

    public DevelopHistogram()
    {
        InitializeComponent();
    }

    public event EventHandler<DevelopHistogramValueChangedEventArgs>? ValueChanged;

    public void ConfigureRanges(double exposure, double toneControl)
    {
        if (double.IsFinite(exposure) && exposure > 0)
        {
            maximumExposure = exposure;
        }
        if (double.IsFinite(toneControl) && toneControl > 0)
        {
            maximumToneControl = toneControl;
        }
    }

    public void Localize(
        string title,
        string shadow,
        string density,
        string exposure,
        string highlight,
        string rgb,
        string clipping,
        string red,
        string green,
        string blue,
        string keyboardHelp)
    {
        TitleText.Text = title;
        ShadowText.Text = shadow;
        DensityText.Text = density;
        ExposureText.Text = exposure;
        HighlightText.Text = highlight;
        RgbText.Text = rgb;
        clippingFormat = clipping;
        redChannelShort = red;
        greenChannelShort = green;
        blueChannelShort = blue;
        AutomationProperties.SetName(this, title);
        AutomationProperties.SetName(Surface, title);
        AutomationProperties.SetHelpText(this, keyboardHelp);
        UpdateClippingText();
        UpdateActiveRegion(activeRegion, ActiveValueText.Visibility == Visibility.Visible);
    }

    public void SynchronizeValues(double shadow, double density, double exposure, double highlight)
    {
        values[(int)DevelopHistogramRegion.Shadow] = Clamp(shadow, maximumToneControl);
        values[(int)DevelopHistogramRegion.Density] = Clamp(density, maximumToneControl);
        values[(int)DevelopHistogramRegion.Exposure] = Clamp(exposure, maximumExposure);
        values[(int)DevelopHistogramRegion.Highlight] = Clamp(highlight, maximumToneControl);
        UpdateActiveRegion(activeRegion, ActiveValueText.Visibility == Visibility.Visible);
    }

    public void UpdatePixels(byte[] pixels, int width, int height)
    {
        ArgumentNullException.ThrowIfNull(pixels);
        int request = Interlocked.Increment(ref generation);
        _ = CalculateAndDisplayAsync(request, pixels, width, height);
    }

    public void Clear()
    {
        Interlocked.Increment(ref generation);
        bins = null;
        LumaArea.Points.Clear();
        LumaLine.Points.Clear();
        RedLine.Points.Clear();
        GreenLine.Points.Clear();
        BlueLine.Points.Clear();
        ClippingText.Visibility = Visibility.Collapsed;
    }

    private async Task CalculateAndDisplayAsync(int request, byte[] pixels, int width, int height)
    {
        DevelopHistogramBins? computed = await Task.Run(
            () => DevelopHistogramSampler.SampleBgra8(pixels, width, height));
        if (computed is null || request != Volatile.Read(ref generation))
        {
            return;
        }

        _ = DispatcherQueue.TryEnqueue(() =>
        {
            if (request != Volatile.Read(ref generation))
            {
                return;
            }
            bins = computed;
            RenderHistogram();
            UpdateClippingText();
        });
    }

    private void OnHistogramCanvasSizeChanged(object sender, SizeChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        RenderHistogram();
    }

    private void RenderHistogram()
    {
        if (bins is null || HistogramCanvas.ActualWidth <= 0 || HistogramCanvas.ActualHeight <= 0)
        {
            return;
        }

        int peak = Math.Max(
            1,
            new[]
            {
                bins.Luma.Max(),
                bins.Red.Max(),
                bins.Green.Max(),
                bins.Blue.Max(),
            }.Max());
        double width = HistogramCanvas.ActualWidth;
        double height = HistogramCanvas.ActualHeight;

        LumaArea.Points = BuildArea(bins.Luma, peak, width, height);
        LumaLine.Points = BuildLine(bins.Luma, peak, width, height);
        RedLine.Points = BuildLine(bins.Red, peak, width, height);
        GreenLine.Points = BuildLine(bins.Green, peak, width, height);
        BlueLine.Points = BuildLine(bins.Blue, peak, width, height);
    }

    private static PointCollection BuildArea(int[] channel, int peak, double width, double height)
    {
        PointCollection points = new() { new Point(0, height) };
        AppendLine(points, channel, peak, width, height);
        points.Add(new Point(width, height));
        return points;
    }

    private static PointCollection BuildLine(int[] channel, int peak, double width, double height)
    {
        PointCollection points = new();
        AppendLine(points, channel, peak, width, height);
        return points;
    }

    private static void AppendLine(
        PointCollection points,
        int[] channel,
        int peak,
        double width,
        double height)
    {
        for (int index = 0; index < channel.Length; index++)
        {
            double x = index * width / (channel.Length - 1);
            double unit = Math.Sqrt((double)channel[index] / peak);
            points.Add(new Point(x, height - (unit * height)));
        }
    }

    private void UpdateClippingText()
    {
        if (bins is null || bins.TotalPixels == 0)
        {
            ClippingText.Visibility = Visibility.Collapsed;
            return;
        }

        // 문턱과 판정은 DevelopHistogramBins 가 소유합니다. 여기 한 벌 더 두면 언젠가 갈라집니다.
        IReadOnlyList<string> clipped = bins.ClippedChannels;
        string[] localized = new string[clipped.Count];
        for (int index = 0; index < clipped.Count; ++index)
        {
            localized[index] = clipped[index] switch
            {
                "R" => redChannelShort,
                "G" => greenChannelShort,
                _ => blueChannelShort,
            };
        }
        ClippingText.Text = clippingFormat.Replace("%@", string.Join("/", localized), StringComparison.Ordinal);
        ClippingText.Visibility = clipped.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private void OnPointerPressed(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        if (!IsEnabled)
        {
            return;
        }

        Point position = args.GetCurrentPoint(PlotHost).Position;
        activeRegion = RegionAt(position.X, PlotHost.ActualWidth);
        selectedRegion = activeRegion;
        dragStartX = position.X;
        dragStartValue = values[(int)activeRegion];
        isDragging = PlotHost.CapturePointer(args.Pointer);
        UpdateActiveRegion(activeRegion, true);
        Focus(FocusState.Pointer);
        args.Handled = true;
    }

    private void OnPointerMoved(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        Point position = args.GetCurrentPoint(PlotHost).Position;
        if (!isDragging)
        {
            activeRegion = RegionAt(position.X, PlotHost.ActualWidth);
            UpdateActiveRegion(activeRegion, true);
            return;
        }

        double sensitivity = activeRegion == DevelopHistogramRegion.Exposure ? 4 : 2;
        double delta = (position.X - dragStartX) / Math.Max(PlotHost.ActualWidth, 1) * sensitivity;
        SetRegionValue(activeRegion, dragStartValue + delta);
        args.Handled = true;
    }

    private void OnPointerReleased(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        if (!isDragging)
        {
            return;
        }

        PlotHost.ReleasePointerCapture(args.Pointer);
        isDragging = false;
        args.Handled = true;
    }

    private void OnPointerCaptureLost(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        isDragging = false;
    }

    private void OnPointerExited(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (!isDragging)
        {
            ActiveBand.Visibility = Visibility.Collapsed;
            ActiveValueText.Visibility = Visibility.Collapsed;
        }
    }

    private void OnKeyDown(object sender, KeyRoutedEventArgs args)
    {
        _ = sender;
        if (args.Key is VirtualKey.Left or VirtualKey.Right)
        {
            int offset = args.Key == VirtualKey.Right ? 1 : -1;
            selectedRegion = (DevelopHistogramRegion)Math.Clamp((int)selectedRegion + offset, 0, 3);
            activeRegion = selectedRegion;
            UpdateActiveRegion(activeRegion, true);
            args.Handled = true;
            return;
        }
        if (args.Key is not (VirtualKey.Up or VirtualKey.Down))
        {
            return;
        }

        bool coarse = InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Shift)
            .HasFlag(CoreVirtualKeyStates.Down);
        double step = selectedRegion == DevelopHistogramRegion.Exposure ? 0.05 : 0.02;
        if (coarse)
        {
            step *= 5;
        }
        SetRegionValue(selectedRegion, values[(int)selectedRegion] +
            (args.Key == VirtualKey.Up ? step : -step));
        args.Handled = true;
    }

    private void SetRegionValue(DevelopHistogramRegion region, double value)
    {
        double limit = region == DevelopHistogramRegion.Exposure
            ? maximumExposure
            : maximumToneControl;
        double clamped = Clamp(value, limit);
        if (Math.Abs(values[(int)region] - clamped) < 0.000001)
        {
            return;
        }

        values[(int)region] = clamped;
        UpdateActiveRegion(region, true);
        ValueChanged?.Invoke(this, new DevelopHistogramValueChangedEventArgs(region, clamped));
    }

    private void UpdateActiveRegion(DevelopHistogramRegion region, bool visible)
    {
        Grid.SetColumn(ActiveBand, (int)region);
        ActiveBand.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;
        ActiveValueText.Text = string.Create(
            CultureInfo.InvariantCulture,
            $"{RegionName(region)} {values[(int)region]:+0.00;-0.00;0.00}");
        ActiveValueText.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;
        AutomationProperties.SetItemStatus(this, ActiveValueText.Text);
    }

    private string RegionName(DevelopHistogramRegion region) => region switch
    {
        DevelopHistogramRegion.Shadow => ShadowText.Text,
        DevelopHistogramRegion.Density => DensityText.Text,
        DevelopHistogramRegion.Exposure => ExposureText.Text,
        DevelopHistogramRegion.Highlight => HighlightText.Text,
        _ => string.Empty,
    };

    private static DevelopHistogramRegion RegionAt(double x, double width)
    {
        double unit = Math.Clamp(x / Math.Max(width, 1), 0, 0.999);
        if (unit < 0.26) return DevelopHistogramRegion.Shadow;
        if (unit < 0.50) return DevelopHistogramRegion.Density;
        if (unit < 0.74) return DevelopHistogramRegion.Exposure;
        return DevelopHistogramRegion.Highlight;
    }

    private static double Clamp(double value, double limit) =>
        double.IsFinite(value) ? Math.Clamp(value, -limit, limit) : 0;

}
