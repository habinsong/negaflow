using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;

namespace Negaflow.Shell.Views.Controls;

/// <summary>
/// macOS <c>CropAngleDial</c> 과 같은 수평 보정 다이얼입니다. crop 모드에서만 나옵니다.
/// </summary>
/// <remarks>
/// 치수와 눈금은 macOS 를 그대로 씁니다 — 지름 108, 반지름 42, −45…45 를 15도마다 나눈 일곱
/// 눈금이고 0도만 강조합니다. 끌면 각도가 바뀌고 두 번 누르면 0 으로 돌아갑니다.
/// </remarks>
public sealed class CropAngleDial : UserControl
{
    private const double DialSize = 108.0;
    private const double DialRadius = 42.0;
    private static readonly int[] Ticks = [-45, -30, -15, 0, 15, 30, 45];

    public static readonly DependencyProperty AngleProperty = DependencyProperty.Register(
        nameof(Angle),
        typeof(double),
        typeof(CropAngleDial),
        new PropertyMetadata(0.0, OnAngleChanged));

    private readonly Canvas surface = new()
    {
        Width = DialSize,
        Height = DialSize,
        Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent),
    };

    private readonly Line arm = new() { StrokeThickness = 2.0, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round };
    private readonly Ellipse knob = new() { Width = 12.0, Height = 12.0, StrokeThickness = 1.0 };
    private readonly TextBlock valueText = new() { FontSize = 11.0, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, TextAlignment = TextAlignment.Center, Width = DialSize };

    public CropAngleDial()
    {
        Width = DialSize;
        Height = DialSize;
        IsTabStop = true;
        Content = surface;
        BuildFace();
        surface.Children.Add(arm);
        surface.Children.Add(knob);
        Canvas.SetTop(valueText, (DialSize / 2.0) + 18.0);
        surface.Children.Add(valueText);

        surface.PointerPressed += OnPointerPressed;
        surface.PointerMoved += OnPointerMoved;
        surface.PointerReleased += OnPointerReleased;
        surface.PointerCaptureLost += OnPointerReleased;
        surface.DoubleTapped += OnDoubleTapped;
        Render();
    }

    /// <summary>사용자가 다이얼로 정한 각도입니다. 저장은 호스트가 합니다.</summary>
    public event EventHandler<double>? AngleCommitted;

    public double Angle
    {
        get => (double)GetValue(AngleProperty);
        set => SetValue(AngleProperty, value);
    }

    private static void OnAngleChanged(DependencyObject sender, DependencyPropertyChangedEventArgs args)
    {
        _ = args;
        (sender as CropAngleDial)?.Render();
    }

    private void BuildFace()
    {
        var face = new Ellipse
        {
            Width = DialSize,
            Height = DialSize,
            Fill = Fill(0.045),
            Stroke = Fill(0.16),
            StrokeThickness = 1.0,
        };
        surface.Children.Add(face);

        // 가운데 수평선 — 기울기를 눈으로 견줄 기준입니다.
        var horizon = new Line
        {
            X1 = 10.0,
            X2 = DialSize - 10.0,
            Y1 = DialSize / 2.0,
            Y2 = DialSize / 2.0,
            Stroke = Fill(0.18),
            StrokeThickness = 1.0,
        };
        surface.Children.Add(horizon);

        foreach (int tick in Ticks)
        {
            double length = tick == 0 ? 10.0 : 6.0;
            var mark = new Rectangle
            {
                Width = 1.0,
                Height = length,
                Fill = tick == 0 ? AccentFill(0.75) : Fill(0.28),
                RenderTransformOrigin = new Windows.Foundation.Point(0.5, 0.5),
            };
            double radians = tick * Math.PI / 180.0;
            double centreX = (DialSize / 2.0) + (Math.Sin(radians) * DialRadius);
            double centreY = (DialSize / 2.0) - (Math.Cos(radians) * DialRadius);
            Canvas.SetLeft(mark, centreX - 0.5);
            Canvas.SetTop(mark, centreY - (length / 2.0));
            mark.RenderTransform = new RotateTransform { Angle = tick };
            surface.Children.Add(mark);
        }
    }

    private void OnPointerPressed(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        _ = surface.CapturePointer(args.Pointer);
        Commit(args);
    }

    private void OnPointerMoved(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        if (surface.PointerCaptures?.Count > 0)
        {
            Commit(args);
        }
    }

    private void OnPointerReleased(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        surface.ReleasePointerCapture(args.Pointer);
        args.Handled = true;
    }

    private void OnDoubleTapped(object sender, DoubleTappedRoutedEventArgs args)
    {
        _ = sender;
        args.Handled = true;
        Angle = 0.0;
        AngleCommitted?.Invoke(this, 0.0);
    }

    private void Commit(PointerRoutedEventArgs args)
    {
        Windows.Foundation.Point position = args.GetCurrentPoint(surface).Position;
        double dx = position.X - (DialSize / 2.0);
        double dy = position.Y - (DialSize / 2.0);
        // 한가운데를 누르면 방향이 없습니다. 그 자리에서는 각도를 바꾸지 않습니다.
        if (Math.Abs(dx) + Math.Abs(dy) <= 1.0)
        {
            return;
        }
        double degrees = Math.Clamp(Math.Atan2(dx, -dy) * 180.0 / Math.PI, -45.0, 45.0);
        Angle = degrees;
        AngleCommitted?.Invoke(this, degrees);
        args.Handled = true;
    }

    private void Render()
    {
        double clamped = Math.Clamp(Angle, -45.0, 45.0);
        double radians = clamped * Math.PI / 180.0;
        double knobX = (DialSize / 2.0) + (Math.Sin(radians) * DialRadius);
        double knobY = (DialSize / 2.0) - (Math.Cos(radians) * DialRadius);

        arm.X1 = DialSize / 2.0;
        arm.Y1 = DialSize / 2.0;
        arm.X2 = knobX;
        arm.Y2 = knobY;
        arm.Stroke = AccentFill(0.55);

        knob.Fill = AccentFill(1.0);
        knob.Stroke = new SolidColorBrush(Microsoft.UI.Colors.White) { Opacity = 0.85 };
        Canvas.SetLeft(knob, knobX - 6.0);
        Canvas.SetTop(knob, knobY - 6.0);

        valueText.Text = Math.Abs(Angle) < 0.05
            ? "0.0°"
            : string.Create(CultureInfo.CurrentCulture, $"{Angle:+0.0;-0.0}°");
        valueText.Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"];
        AutomationProperties.SetHelpText(this, valueText.Text);
    }

    private static Brush Fill(double opacity) =>
        new SolidColorBrush(((SolidColorBrush)Application.Current.Resources["TextFillColorPrimaryBrush"]).Color)
        {
            Opacity = opacity,
        };

    private static Brush AccentFill(double opacity) =>
        new SolidColorBrush(((SolidColorBrush)Application.Current.Resources["AccentFillColorDefaultBrush"]).Color)
        {
            Opacity = opacity,
        };
}
