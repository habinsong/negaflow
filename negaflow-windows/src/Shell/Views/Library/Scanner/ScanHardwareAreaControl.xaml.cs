using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Library.Scanner;

/// <summary>
/// 위치 지정이 안 되는 장치(필름 스캐너)의 스캔 영역입니다. macOS
/// <c>hardwareScanAreaControls</c> · <c>scanAreaDimensionRow</c> · <c>ScanAreaDimensionValue</c> 를
/// 옮겼습니다. 영역은 규격·수동 비율 크기로 가운데에 맞춰지고(<see cref="ScanHardwareArea"/>),
/// 여기서 너비·높이를 고치거나 "전체" 로 되돌립니다.
/// </summary>
public sealed partial class ScanHardwareAreaControl : UserControl
{
    private bool expanded;
    private bool synchronizing;
    private string unit = "millimeter";

    public ScanHardwareAreaControl()
    {
        InitializeComponent();
        LocalizedElement.Track(this, Localize);
    }

    internal ScanSessionController? Session { get; set; }

    /// <summary>
    /// macOS 와 같은 조건일 때만 섭니다: 평판 영역 워크플로가 아니고, 최대 영역과 고른 영역이
    /// 있을 때입니다.
    /// </summary>
    internal void Render()
    {
        if (Session is not { Capabilities: { } capabilities } session ||
            session.UsesFlatbedRegionWorkflow ||
            capabilities.PhysicalScanAreaBounds is not { } bounds ||
            session.Options.HardwareScanArea is not { } area)
        {
            Visibility = Visibility.Collapsed;
            return;
        }
        Visibility = Visibility.Visible;
        unit = string.Equals(capabilities.ScanAreaUnit, "inch", StringComparison.Ordinal)
            ? "inch"
            : "millimeter";
        synchronizing = true;
        try
        {
            Sync(WidthSlider, WidthValueText, bounds.Minimum.WidthMm, bounds.Maximum.WidthMm, area.WidthMm);
            Sync(HeightSlider, HeightValueText, bounds.Minimum.HeightMm, bounds.Maximum.HeightMm, area.HeightMm);
        }
        finally
        {
            synchronizing = false;
        }
        DimensionRows.Visibility = expanded ? Visibility.Visible : Visibility.Collapsed;
        ChevronIcon.Glyph = expanded ? "" : "";
    }

    private void Localize()
    {
        string title = AppResources.Get("hardwareScanArea", "Text");
        HeaderText.Text = title;
        AutomationProperties.SetName(ChevronButton, title);
        FullButton.Content = AppResources.Get("scanAreaFull", "Text");
        WidthLabel.Text = AppResources.Get("scanAreaWidth", "Text");
        HeightLabel.Text = AppResources.Get("scanAreaHeight", "Text");
        AutomationProperties.SetName(WidthSlider, WidthLabel.Text);
        AutomationProperties.SetName(HeightSlider, HeightLabel.Text);
    }

    private void Sync(Slider slider, TextBlock value, double minimumMm, double maximumMm, double valueMm)
    {
        double minimum = Display(minimumMm);
        double maximum = Display(maximumMm);
        slider.StepFrequency = IsInch ? 0.01 : 0.1;
        slider.Maximum = Math.Max(maximum, minimum);
        slider.Minimum = minimum;
        slider.Value = Math.Clamp(Display(valueMm), minimum, slider.Maximum);
        value.Text = DisplayText(Display(valueMm));
    }

    private bool IsInch => string.Equals(unit, "inch", StringComparison.Ordinal);

    /// <summary>macOS <c>ScanAreaUnit.displayValue(fromMillimeters:)</c>.</summary>
    private double Display(double millimeters) => IsInch ? millimeters / 25.4 : millimeters;

    /// <summary>macOS <c>ScanAreaUnit.millimeters(fromDisplayValue:)</c>.</summary>
    private double Millimeters(double display) => IsInch ? display * 25.4 : display;

    /// <summary>macOS <c>scanAreaDisplayText</c> — 인치는 소수 둘째, mm 는 첫째 자리입니다.</summary>
    private string DisplayText(double display) =>
        display.ToString(IsInch ? "F2" : "F1", CultureInfo.CurrentCulture) + " " +
        (IsInch ? "in" : "mm");

    /// <summary>macOS <c>updateHardwareScanArea(_:)</c> — 한 치수만 바꾸고 장치 격자에 맞춥니다.</summary>
    private void Apply(bool width, double displayValue)
    {
        if (Session is not { Capabilities.PhysicalScanAreaBounds: { } bounds } session)
        {
            return;
        }
        double millimeters = Millimeters(displayValue);
        session.UpdateOptions(options =>
        {
            ScannerPluginScanArea current = options.HardwareScanArea ?? bounds.Maximum;
            return options with
            {
                HardwareScanArea = width
                    ? current with { WidthMm = millimeters }
                    : current with { HeightMm = millimeters },
            };
        });
    }

    private void OnToggleClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        expanded = !expanded;
        Render();
    }

    /// <summary>macOS <c>resetHardwareScanArea()</c> — 최대 영역으로 되돌립니다.</summary>
    private void OnFullClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (Session is { Capabilities.PhysicalScanAreaBounds: { } bounds } session)
        {
            session.UpdateOptions(options => options with { HardwareScanArea = bounds.Maximum });
        }
    }

    private void OnWidthChanged(object sender, RangeBaseValueChangedEventArgs args)
    {
        if (!synchronizing)
        {
            Apply(width: true, Snapped((Slider)sender, args.NewValue));
        }
    }

    private void OnHeightChanged(object sender, RangeBaseValueChangedEventArgs args)
    {
        if (!synchronizing)
        {
            Apply(width: false, Snapped((Slider)sender, args.NewValue));
        }
    }

    /// <summary>
    /// macOS <c>Slider(step:)</c> 은 늘 눈금 값만 냅니다. WinUI <c>StepFrequency</c> 는 손잡이를
    /// 끌 때만 걸리고 트랙을 누르면 포인터 자리를 그대로 넣으므로 여기서 눈금에 맞춥니다.
    /// </summary>
    private double Snapped(Slider slider, double value)
    {
        double step = IsInch ? 0.01 : 0.1;
        double snapped = slider.Minimum + (Math.Round((value - slider.Minimum) / step) * step);
        return Math.Clamp(snapped, slider.Minimum, slider.Maximum);
    }

    /// <summary>값을 누르면 입력칸이 됩니다(macOS <c>beginEditing</c>).</summary>
    private void OnValueClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        bool width = ReferenceEquals(sender, WidthValueButton);
        Slider slider = width ? WidthSlider : HeightSlider;
        TextBox box = width ? WidthValueBox : HeightValueBox;
        ((Button)sender).Visibility = Visibility.Collapsed;
        box.Text = slider.Value.ToString(IsInch ? "F2" : "F1", CultureInfo.InvariantCulture);
        box.Visibility = Visibility.Visible;
        _ = box.Focus(FocusState.Programmatic);
        box.SelectAll();
    }

    /// <summary>Enter 는 적용하고, Esc 는 최대값으로 되돌립니다(macOS <c>cancelToFullValue</c>).</summary>
    private void OnValueKeyDown(object sender, KeyRoutedEventArgs args)
    {
        TextBox box = (TextBox)sender;
        switch (args.Key)
        {
            case Windows.System.VirtualKey.Enter:
                args.Handled = true;
                Commit(box);
                return;
            case Windows.System.VirtualKey.Escape:
                args.Handled = true;
                bool width = ReferenceEquals(box, WidthValueBox);
                Slider slider = width ? WidthSlider : HeightSlider;
                EndEditing(box);
                Apply(width, slider.Maximum);
                return;
            default:
                return;
        }
    }

    private void OnValueLostFocus(object sender, RoutedEventArgs args)
    {
        _ = args;
        TextBox box = (TextBox)sender;
        if (box.Visibility == Visibility.Visible)
        {
            Commit(box);
        }
    }

    /// <summary>
    /// macOS <c>commitDraft</c> — 쉼표 소수점도 받고 범위로 자릅니다. 못 쓰는 값은 경고음을
    /// 내고 입력을 버립니다.
    /// </summary>
    private void Commit(TextBox box)
    {
        bool width = ReferenceEquals(box, WidthValueBox);
        Slider slider = width ? WidthSlider : HeightSlider;
        string normalized = box.Text.Trim().Replace(',', '.');
        EndEditing(box);
        if (!double.TryParse(normalized, NumberStyles.Float, CultureInfo.InvariantCulture,
                out double parsed) || !double.IsFinite(parsed))
        {
            _ = MessageBeep(0);
            return;
        }
        Apply(width, Math.Clamp(parsed, slider.Minimum, slider.Maximum));
    }

    private void EndEditing(TextBox box)
    {
        box.Visibility = Visibility.Collapsed;
        (ReferenceEquals(box, WidthValueBox) ? WidthValueButton : HeightValueButton).Visibility =
            Visibility.Visible;
    }

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern bool MessageBeep(uint type);
}
