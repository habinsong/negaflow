using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Negaflow.Catalog;
using Windows.Foundation;

namespace Negaflow.Shell.Views.Controls;

/// <summary>세 tonal range의 hue/saturation wheel과 공통 Color Grading controls입니다.</summary>
public sealed partial class ColorGradingEditor : UserControl
{
    private const double WheelSize = 150.0;
    private const int HueSegments = 72;
    private const int SaturationRings = 12;
    private ColorGradingRange range = ColorGradingRange.Midtones;
    private bool isSynchronizing;
    private uint? capturedPointerId;

    public ColorGradingEditor()
    {
        InitializeComponent();
        MidtonesButton.IsChecked = true;
        RenderEditor();
    }

    public static readonly DependencyProperty GradingProperty = DependencyProperty.Register(
        nameof(Grading), typeof(ColorGradingRecipe), typeof(ColorGradingEditor),
        new PropertyMetadata(ColorGradingRecipe.Identity, OnGradingChanged));

    public ColorGradingRecipe Grading
    {
        get => (ColorGradingRecipe)GetValue(GradingProperty);
        set => SetValue(GradingProperty, value);
    }

    public event EventHandler<ColorGradingChangedEventArgs>? GradingChanged;

    private static void OnGradingChanged(DependencyObject sender, DependencyPropertyChangedEventArgs args)
    {
        _ = args;
        ((ColorGradingEditor)sender).RenderEditor();
    }

    private void OnRangeChecked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (isSynchronizing)
        {
            return;
        }
        range = ReferenceEquals(sender, ShadowsButton) ? ColorGradingRange.Shadows :
            ReferenceEquals(sender, HighlightsButton) ? ColorGradingRange.Highlights :
            ColorGradingRange.Midtones;
        RenderEditor();
    }

    private void RenderEditor()
    {
        if (WheelCanvas is null)
        {
            return;
        }
        isSynchronizing = true;
        ColorGradeRegionRecipe region = SelectedRegion;
        WheelCanvas.Children.Clear();
        Point center = new(WheelSize / 2.0, WheelSize / 2.0);
        double radius = WheelSize / 2.0;
        for (int ring = 1; ring <= SaturationRings; ring++)
        {
            double inner = radius * (ring - 1) / SaturationRings;
            double outer = radius * ring / SaturationRings;
            for (int segment = 0; segment < HueSegments; segment++)
            {
                double start = segment * 360.0 / HueSegments;
                double end = (segment + 1) * 360.0 / HueSegments;
                Polygon wedge = new()
                {
                    Fill = new SolidColorBrush(HsvToColor(start, (double)ring / SaturationRings)),
                    Points =
                    [
                        Polar(center, inner, start), Polar(center, outer, start),
                        Polar(center, outer, end), Polar(center, inner, end),
                    ],
                };
                WheelCanvas.Children.Add(wedge);
            }
        }
        RadialGradientBrush centerWhite = new()
        {
            Center = new Point(0.5, 0.5),
            GradientOrigin = new Point(0.5, 0.5),
            RadiusX = 0.5,
            RadiusY = 0.5,
        };
        centerWhite.GradientStops.Add(new GradientStop
        {
            Color = Windows.UI.Color.FromArgb(255, 255, 255, 255),
            Offset = 0.0,
        });
        centerWhite.GradientStops.Add(new GradientStop
        {
            Color = Windows.UI.Color.FromArgb(0, 255, 255, 255),
            Offset = 1.0,
        });
        WheelCanvas.Children.Add(new Ellipse
        {
            Width = WheelSize,
            Height = WheelSize,
            Fill = centerWhite,
            IsHitTestVisible = false,
        });
        WheelCanvas.Children.Add(new Ellipse
        {
            Width = WheelSize - 1,
            Height = WheelSize - 1,
            Stroke = new SolidColorBrush(Windows.UI.Color.FromArgb(64, 255, 255, 255)),
            StrokeThickness = 1,
        });
        Point handle = Polar(center, radius * region.Saturation, region.Hue);
        Ellipse marker = new()
        {
            Width = 16,
            Height = 16,
            Stroke = new SolidColorBrush(Microsoft.UI.Colors.White),
            StrokeThickness = 2,
            Fill = new SolidColorBrush(HsvToColor(region.Hue, Math.Max(region.Saturation, 0.05))),
            IsHitTestVisible = false,
        };
        Canvas.SetLeft(marker, handle.X - 8);
        Canvas.SetTop(marker, handle.Y - 8);
        WheelCanvas.Children.Add(marker);
        HueReadout.Text = $"Hue {region.Hue:F0}°";
        SaturationReadout.Text = $"Sat {region.Saturation:P0}";
        LuminanceControl.Value = region.Luminance;
        BlendingControl.Value = Grading.Blending;
        BalanceControl.Value = Grading.Balance;
        isSynchronizing = false;
    }

    private void OnWheelPointerPressed(object sender, PointerRoutedEventArgs args)
    {
        capturedPointerId = args.Pointer.PointerId;
        WheelCanvas.CapturePointer(args.Pointer);
        WheelCanvas.Focus(FocusState.Pointer);
        UpdateWheel(args.GetCurrentPoint(WheelCanvas).Position);
        args.Handled = true;
    }

    private void OnWheelPointerMoved(object sender, PointerRoutedEventArgs args)
    {
        if (capturedPointerId == args.Pointer.PointerId)
        {
            UpdateWheel(args.GetCurrentPoint(WheelCanvas).Position);
            args.Handled = true;
        }
    }

    private void OnWheelPointerReleased(object sender, PointerRoutedEventArgs args) => ReleasePointer(args.Pointer.PointerId);

    private void OnWheelPointerCanceled(object sender, PointerRoutedEventArgs args) => ReleasePointer(args.Pointer.PointerId);

    private void ReleasePointer(uint pointerId)
    {
        if (capturedPointerId == pointerId)
        {
            WheelCanvas.ReleasePointerCaptures();
            capturedPointerId = null;
        }
    }

    private void OnWheelKeyDown(object sender, KeyRoutedEventArgs args)
    {
        _ = sender;
        bool shift = InputKeyboardSource.GetKeyStateForCurrentThread(
            Windows.System.VirtualKey.Shift).HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);
        double multiplier = shift ? 10.0 : 1.0;
        ColorGradeRegionRecipe region = SelectedRegion;
        switch (args.Key)
        {
            case Windows.System.VirtualKey.Left: region = region with { Hue = WrapHue(region.Hue - multiplier) }; break;
            case Windows.System.VirtualKey.Right: region = region with { Hue = WrapHue(region.Hue + multiplier) }; break;
            case Windows.System.VirtualKey.Down: region = region with { Saturation = Math.Max(0, region.Saturation - (0.01 * multiplier)) }; break;
            case Windows.System.VirtualKey.Up: region = region with { Saturation = Math.Min(1, region.Saturation + (0.01 * multiplier)) }; break;
            default: return;
        }
        SetSelectedRegion(region);
        args.Handled = true;
    }

    private void UpdateWheel(Point point)
    {
        double dx = point.X - (WheelSize / 2.0);
        double dy = point.Y - (WheelSize / 2.0);
        double radius = WheelSize / 2.0;
        double saturation = Math.Min(Math.Sqrt((dx * dx) + (dy * dy)) / radius, 1.0);
        double hue = WrapHue(Math.Atan2(-dy, dx) * 180.0 / Math.PI);
        SetSelectedRegion(SelectedRegion with { Hue = hue, Saturation = saturation });
    }

    private void OnLuminanceChanged(object sender, InspectorSliderValueChangedEventArgs args)
    {
        _ = sender;
        if (!isSynchronizing) SetSelectedRegion(SelectedRegion with { Luminance = args.Value });
    }

    private void OnBlendingChanged(object sender, InspectorSliderValueChangedEventArgs args)
    {
        _ = sender;
        if (!isSynchronizing) UpdateGrading(Grading with { Blending = args.Value });
    }

    private void OnBalanceChanged(object sender, InspectorSliderValueChangedEventArgs args)
    {
        _ = sender;
        if (!isSynchronizing) UpdateGrading(Grading with { Balance = args.Value });
    }

    private ColorGradeRegionRecipe SelectedRegion => range switch
    {
        ColorGradingRange.Shadows => Grading.Shadows,
        ColorGradingRange.Highlights => Grading.Highlights,
        _ => Grading.Midtones,
    };

    private void SetSelectedRegion(ColorGradeRegionRecipe region) =>
        UpdateGrading(range switch
        {
            ColorGradingRange.Shadows => Grading with { Shadows = region },
            ColorGradingRange.Highlights => Grading with { Highlights = region },
            _ => Grading with { Midtones = region },
        });

    private void UpdateGrading(ColorGradingRecipe grading)
    {
        Grading = grading;
        GradingChanged?.Invoke(this, new ColorGradingChangedEventArgs(grading));
    }

    private static Point Polar(Point center, double radius, double hue) => new(
        center.X + (radius * Math.Cos(hue * Math.PI / 180.0)),
        center.Y - (radius * Math.Sin(hue * Math.PI / 180.0)));

    private static double WrapHue(double hue) => ((hue % 360.0) + 360.0) % 360.0;

    private static Windows.UI.Color HsvToColor(double hue, double saturation)
    {
        double c = saturation;
        double x = c * (1 - Math.Abs(((hue / 60.0) % 2) - 1));
        (double r, double g, double b) = hue switch
        {
            < 60 => (c, x, 0.0), < 120 => (x, c, 0.0), < 180 => (0.0, c, x),
            < 240 => (0.0, x, c), < 300 => (x, 0.0, c), _ => (c, 0.0, x),
        };
        return Windows.UI.Color.FromArgb(255, (byte)(r * 255), (byte)(g * 255), (byte)(b * 255));
    }

    private enum ColorGradingRange { Shadows, Midtones, Highlights }
}

public sealed class ColorGradingChangedEventArgs(ColorGradingRecipe grading) : EventArgs
{
    public ColorGradingRecipe Grading { get; } = grading;
}
