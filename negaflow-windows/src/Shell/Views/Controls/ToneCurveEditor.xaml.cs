using System.Globalization;
using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Negaflow.Shell.Localization;
using Negaflow.Catalog;
using Windows.Foundation;
using Windows.System;
using Windows.UI.Core;

namespace Negaflow.Shell.Views.Controls;

public sealed partial class ToneCurveEditor : UserControl
{
    private const double HandleRadius = 4.0;
    private const double PointerHitRadius = 18.0;

    private readonly ToneCurveEditing editing = new();
    private bool dragging;
    private bool isSynchronizing;
    private bool isPublishing;

    public ToneCurveEditor()
    {
        InitializeComponent();
        SetAutomationProperties();
        Render();
    }

    public static readonly DependencyProperty CurvesProperty = DependencyProperty.Register(
        nameof(Curves),
        typeof(PointCurveRecipe),
        typeof(ToneCurveEditor),
        new PropertyMetadata(PointCurveRecipe.Identity, OnCurvesChanged));

    public PointCurveRecipe Curves
    {
        get => (PointCurveRecipe)GetValue(CurvesProperty);
        set => SetValue(CurvesProperty, value);
    }

    public event EventHandler<ToneCurveChangedEventArgs>? CurvesChanged;

    private static void OnCurvesChanged(DependencyObject sender, DependencyPropertyChangedEventArgs args)
    {
        if (args.NewValue is PointCurveRecipe curves)
        {
            ToneCurveEditor editor = (ToneCurveEditor)sender;
            if (editor.isPublishing)
            {
                return;
            }
            editor.editing.SetCurves(curves);
            editor.Render();
        }
    }

    private void SetAutomationProperties()
    {
        AutomationProperties.SetAutomationId(CurveCanvas, "negaflow.develop.point-curve.canvas");
        AutomationProperties.SetName(CurveCanvas, AppResources.Get("developPointCurveCanvas", "Value"));
        AutomationProperties.SetHelpText(
            CurveCanvas,
            AppResources.Get("developPointCurveCanvasHelp", "Value"));
        // 채널 이름은 리소스에서 옵니다.
        //
        // 합성 채널의 이름은 **DR** 입니다 — macOS `ToneCurveEditor.Channel.rgb` 가
        // `dynamicRangeChannel` 을 쓰고, 영어·한국어 표 모두 "DR" 입니다. 여기에 "RGB" 를
        // 박아 두면 화면에 없는 이름을 지어내는 것입니다.
        SetChannelText(RedChannelButton, AppResources.Get("developRed", "Text"));
        SetChannelText(GreenChannelButton, AppResources.Get("developGreen", "Text"));
        SetChannelText(BlueChannelButton, AppResources.Get("developBlue", "Text"));
        SetChannelText(RgbChannelButton, AppResources.Get("developDynamicRangeChannel", "Text"));
        SetChannelText(ResetChannelButton, AppResources.Get("developResetChannel", "Content"));
        CurveHelpText.Text = AppResources.Get("developToneCurveHelp", "Text");
        CurveInputLabel.Text = AppResources.Get("developCurveInput", "Text");
        CurveOutputLabel.Text = AppResources.Get("developCurveOutput", "Text");
        AutomationProperties.SetAutomationId(RgbChannelButton, "negaflow.develop.point-curve.rgb");
        AutomationProperties.SetAutomationId(RedChannelButton, "negaflow.develop.point-curve.red");
        AutomationProperties.SetAutomationId(GreenChannelButton, "negaflow.develop.point-curve.green");
        AutomationProperties.SetAutomationId(BlueChannelButton, "negaflow.develop.point-curve.blue");
        AutomationProperties.SetAutomationId(ResetChannelButton, "negaflow.develop.point-curve.reset");
    }

    private static void SetChannelText(Button button, string text)
    {
        button.Content = text;
        AutomationProperties.SetName(button, text);
    }

    private void Render()
    {
        if (CurveCanvas is null)
        {
            return;
        }

        CurveCanvas.Children.Clear();
        double width = CurveCanvas.ActualWidth;
        double height = CurveCanvas.ActualHeight;
        if (width <= 0.0 || height <= 0.0)
        {
            return;
        }

        SolidColorBrush gridBrush = new(Windows.UI.Color.FromArgb(70, 160, 160, 160));
        for (int index = 1; index < 4; index++)
        {
            double fraction = index / 4.0;
            AddLine(fraction * width, 0.0, fraction * width, height, gridBrush, 1.0);
            AddLine(0.0, fraction * height, width, fraction * height, gridBrush, 1.0);
        }
        AddLine(0.0, height, width, 0.0, gridBrush, 1.0);

        IReadOnlyList<PointCurvePoint> stored = editing.Points;
        IReadOnlyList<PointCurvePoint> display = stored.Count == 0
            ? [new PointCurvePoint(0.0, 0.0), new PointCurvePoint(1.0, 1.0)]
            : stored;
        Polyline curve = new()
        {
            Stroke = new SolidColorBrush(ChannelColor(editing.Channel)),
            StrokeThickness = 2.0,
        };
        foreach (PointCurvePoint point in display)
        {
            curve.Points.Add(ToCanvasPoint(point, width, height));
        }
        CurveCanvas.Children.Add(curve);

        for (int index = 0; index < stored.Count; index++)
        {
            Point point = ToCanvasPoint(stored[index], width, height);
            bool selected = index == editing.SelectedIndex;
            Ellipse handle = new()
            {
                Width = HandleRadius * 2.0,
                Height = HandleRadius * 2.0,
                Fill = new SolidColorBrush(ChannelColor(editing.Channel)),
                Stroke = new SolidColorBrush(selected
                    ? Windows.UI.Color.FromArgb(255, 255, 255, 255)
                    : Windows.UI.Color.FromArgb(255, 35, 35, 35)),
                StrokeThickness = selected ? 2.0 : 1.0,
            };
            Canvas.SetLeft(handle, point.X - HandleRadius);
            Canvas.SetTop(handle, point.Y - HandleRadius);
            CurveCanvas.Children.Add(handle);
        }

        RgbChannelButton.FontWeight = editing.Channel == ToneCurveChannel.Rgb
            ? Microsoft.UI.Text.FontWeights.SemiBold : Microsoft.UI.Text.FontWeights.Normal;
        RedChannelButton.FontWeight = editing.Channel == ToneCurveChannel.Red
            ? Microsoft.UI.Text.FontWeights.SemiBold : Microsoft.UI.Text.FontWeights.Normal;
        GreenChannelButton.FontWeight = editing.Channel == ToneCurveChannel.Green
            ? Microsoft.UI.Text.FontWeights.SemiBold : Microsoft.UI.Text.FontWeights.Normal;
        BlueChannelButton.FontWeight = editing.Channel == ToneCurveChannel.Blue
            ? Microsoft.UI.Text.FontWeights.SemiBold : Microsoft.UI.Text.FontWeights.Normal;
        SynchronizePointFields();
    }

    private void AddLine(double x1, double y1, double x2, double y2, Brush brush, double thickness)
    {
        CurveCanvas.Children.Add(new Line
        {
            X1 = x1,
            Y1 = y1,
            X2 = x2,
            Y2 = y2,
            Stroke = brush,
            StrokeThickness = thickness,
        });
    }

    private void SynchronizePointFields()
    {
        isSynchronizing = true;
        bool hasSelection = editing.SelectedIndex >= 0 && editing.SelectedIndex < editing.Points.Count;
        PointFields.Opacity = hasSelection ? 1.0 : 0.55;
        OutputEditor.IsEnabled = hasSelection;
        if (hasSelection)
        {
            PointCurvePoint selected = editing.Points[editing.SelectedIndex];
            InputEditor.Text = (selected.X * 100.0).ToString("0.##", CultureInfo.CurrentCulture);
            OutputEditor.Text = (selected.Y * 100.0).ToString("0.##", CultureInfo.CurrentCulture);
            InputEditor.IsEnabled = selected.X is > 1.0e-9 and < 1.0 - 1.0e-9;
        }
        else
        {
            InputEditor.Text = string.Empty;
            OutputEditor.Text = string.Empty;
            InputEditor.IsEnabled = false;
        }
        isSynchronizing = false;
    }

    private void OnCanvasSizeChanged(object sender, SizeChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        Render();
    }

    private void OnCanvasPointerPressed(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        if (!IsEnabled || !TryNormalize(args.GetCurrentPoint(CurveCanvas).Position, out double x, out double y))
        {
            return;
        }

        double normalizedHitRadius = PointerHitRadius / Math.Max(CurveCanvas.ActualWidth, CurveCanvas.ActualHeight);
        if (!editing.TrySelectNearest(x, y, normalizedHitRadius))
        {
            if (!editing.Add(x, y))
            {
                return;
            }
        }
        dragging = true;
        CurveCanvas.CapturePointer(args.Pointer);
        CurveCanvas.Focus(FocusState.Pointer);
        PublishChange();
    }

    private void OnCanvasPointerMoved(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        if (!dragging || !IsEnabled || !TryNormalize(args.GetCurrentPoint(CurveCanvas).Position, out double x, out double y))
        {
            return;
        }
        if (editing.UpdateSelected(x, y))
        {
            PublishChange();
        }
    }

    private void OnCanvasPointerReleased(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        dragging = false;
        CurveCanvas.ReleasePointerCapture(args.Pointer);
    }

    private void OnCanvasDoubleTapped(object sender, DoubleTappedRoutedEventArgs args)
    {
        _ = sender;
        if (!IsEnabled || !TryNormalize(args.GetPosition(CurveCanvas), out double x, out double y))
        {
            return;
        }
        double normalizedHitRadius = PointerHitRadius / Math.Max(CurveCanvas.ActualWidth, CurveCanvas.ActualHeight);
        if (editing.TrySelectNearest(x, y, normalizedHitRadius) && editing.DeleteSelected())
        {
            PublishChange();
        }
        else
        {
            Render();
        }
    }

    private void OnCanvasKeyDown(object sender, KeyRoutedEventArgs args)
    {
        _ = sender;
        bool horizontal = args.Key is VirtualKey.Left or VirtualKey.Right;
        bool vertical = args.Key is VirtualKey.Up or VirtualKey.Down;
        if (args.Key == VirtualKey.Delete || args.Key == VirtualKey.Back)
        {
            if (editing.DeleteSelected())
            {
                PublishChange();
            }
            args.Handled = true;
            return;
        }
        if (!horizontal && !vertical)
        {
            return;
        }

        bool coarse = InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Shift)
            .HasFlag(CoreVirtualKeyStates.Down);
        bool changed = editing.NudgeSelected(
            horizontal,
            args.Key is VirtualKey.Right or VirtualKey.Up,
            coarse);
        if (changed)
        {
            PublishChange();
        }
        args.Handled = true;
    }

    private void OnRgbChannelClicked(object sender, RoutedEventArgs args) => SetChannel(ToneCurveChannel.Rgb);

    private void OnRedChannelClicked(object sender, RoutedEventArgs args) => SetChannel(ToneCurveChannel.Red);

    private void OnGreenChannelClicked(object sender, RoutedEventArgs args) => SetChannel(ToneCurveChannel.Green);

    private void OnBlueChannelClicked(object sender, RoutedEventArgs args) => SetChannel(ToneCurveChannel.Blue);

    private void SetChannel(ToneCurveChannel channel)
    {
        editing.SetChannel(channel);
        Render();
    }

    private void OnResetChannelClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (IsEnabled)
        {
            editing.ResetChannel();
            PublishChange();
        }
    }

    private void OnPointEditorKeyDown(object sender, KeyRoutedEventArgs args)
    {
        _ = sender;
        if (args.Key == VirtualKey.Enter)
        {
            CommitPointEditors();
            args.Handled = true;
        }
    }

    private void OnPointEditorLostFocus(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        CommitPointEditors();
    }

    private void CommitPointEditors()
    {
        if (isSynchronizing || editing.SelectedIndex < 0 || editing.SelectedIndex >= editing.Points.Count ||
            !double.TryParse(OutputEditor.Text, NumberStyles.Float, CultureInfo.CurrentCulture, out double output))
        {
            return;
        }

        PointCurvePoint selected = editing.Points[editing.SelectedIndex];
        double input = selected.X;
        if (InputEditor.IsEnabled &&
            (!double.TryParse(InputEditor.Text, NumberStyles.Float, CultureInfo.CurrentCulture, out double parsedInput) ||
             parsedInput is < 0.0 or > 100.0))
        {
            InputEditor.Focus(FocusState.Programmatic);
            return;
        }
        else if (InputEditor.IsEnabled)
        {
            input = double.Parse(InputEditor.Text, NumberStyles.Float, CultureInfo.CurrentCulture) / 100.0;
        }
        if (output is < 0.0 or > 100.0 || !editing.UpdateSelected(input, output / 100.0))
        {
            OutputEditor.Focus(FocusState.Programmatic);
            return;
        }
        PublishChange();
    }

    private bool TryNormalize(Point point, out double x, out double y)
    {
        if (CurveCanvas.ActualWidth <= 0.0 || CurveCanvas.ActualHeight <= 0.0)
        {
            x = 0.0;
            y = 0.0;
            return false;
        }
        x = Math.Clamp(point.X / CurveCanvas.ActualWidth, 0.0, 1.0);
        y = Math.Clamp(1.0 - (point.Y / CurveCanvas.ActualHeight), 0.0, 1.0);
        return true;
    }

    private static Point ToCanvasPoint(PointCurvePoint point, double width, double height) =>
        new(point.X * width, (1.0 - point.Y) * height);

    private static Windows.UI.Color ChannelColor(ToneCurveChannel channel) => channel switch
    {
        ToneCurveChannel.Rgb => Windows.UI.Color.FromArgb(255, 220, 220, 220),
        ToneCurveChannel.Red => Windows.UI.Color.FromArgb(255, 230, 86, 86),
        ToneCurveChannel.Green => Windows.UI.Color.FromArgb(255, 95, 200, 118),
        ToneCurveChannel.Blue => Windows.UI.Color.FromArgb(255, 92, 145, 235),
        _ => Windows.UI.Color.FromArgb(255, 220, 220, 220),
    };

    private void PublishChange()
    {
        isPublishing = true;
        SetValue(CurvesProperty, editing.Curves);
        isPublishing = false;
        Render();
        CurvesChanged?.Invoke(this, new ToneCurveChangedEventArgs(editing.Curves));
    }
}

public sealed class ToneCurveChangedEventArgs(PointCurveRecipe curves) : EventArgs
{
    public PointCurveRecipe Curves { get; } = curves;
}
