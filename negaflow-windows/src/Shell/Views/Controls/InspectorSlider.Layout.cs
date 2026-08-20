using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Negaflow.Shell.Views.Controls;

/// <summary>
/// macOS 인스펙터 슬라이더의 두 모양을 담습니다.
/// </summary>
/// <remarks>
/// <para>
/// ① 기본 — <c>VStack(alignment: .leading, spacing: 3) { HStack(spacing: 6) { 점, 이름, Spacer,
/// EditableSliderValueText(width: 44) }; ResettableSlider }</c>. 이름 줄이 위, 슬라이더가 아래입니다.
/// </para>
/// <para>
/// ② 촘촘 — <c>HStack(spacing: 6) { Text(태그).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
/// .frame(width: 12); ResettableSlider; EditableSliderValueText(width: 38) }</c>. 컬러 믹서의
/// "모두" 가 밴드마다 H·S·L 세 줄을 이 모양으로 냅니다.
/// </para>
/// <para>
/// 값 편집·되돌리기·키보드 조작이 똑같으므로 요소를 두 벌 두지 않고 <see cref="Grid"/> 의
/// 행·열만 옮깁니다.
/// </para>
/// </remarks>
public sealed partial class InspectorSlider
{
    /// <summary>macOS `EditableSliderValueText` 의 기본 폭입니다.</summary>
    private const double DefaultValueWidth = 54;

    /// <summary>macOS `swatch(i)` — 이름 앞에 붙는 12pt 색 동그라미입니다.</summary>
    public static readonly DependencyProperty SwatchProperty = DependencyProperty.Register(
        nameof(Swatch),
        typeof(Brush),
        typeof(InspectorSlider),
        new PropertyMetadata(null, OnLayoutPropertyChanged));

    /// <summary>참이면 한 줄짜리 촘촘한 모양으로 바꿉니다.</summary>
    public static readonly DependencyProperty CompactProperty = DependencyProperty.Register(
        nameof(Compact),
        typeof(bool),
        typeof(InspectorSlider),
        new PropertyMetadata(false, OnLayoutPropertyChanged));

    /// <summary>macOS 가 자리마다 다르게 주는 값 칸 폭입니다. 촘촘 모양은 항상 38 입니다.</summary>
    public static readonly DependencyProperty ValueWidthProperty = DependencyProperty.Register(
        nameof(ValueWidth),
        typeof(double),
        typeof(InspectorSlider),
        new PropertyMetadata(DefaultValueWidth, OnLayoutPropertyChanged));

    /// <summary>
    /// 이름 줄과 슬라이더 사이입니다. 일반 `InspectorSlider` 는 `VStack(spacing: 4)`,
    /// 컬러 믹서 `swatchSlider` 와 컬러 그레이딩 `labeledSlider` 는 3 입니다.
    /// </summary>
    public static readonly DependencyProperty LabelSpacingProperty = DependencyProperty.Register(
        nameof(LabelSpacing),
        typeof(double),
        typeof(InspectorSlider),
        new PropertyMetadata(4d, OnLayoutPropertyChanged));

    public Brush? Swatch
    {
        get => (Brush?)GetValue(SwatchProperty);
        set => SetValue(SwatchProperty, value);
    }

    public bool Compact
    {
        get => (bool)GetValue(CompactProperty);
        set => SetValue(CompactProperty, value);
    }

    public double ValueWidth
    {
        get => (double)GetValue(ValueWidthProperty);
        set => SetValue(ValueWidthProperty, value);
    }

    public double LabelSpacing
    {
        get => (double)GetValue(LabelSpacingProperty);
        set => SetValue(LabelSpacingProperty, value);
    }

    private static void OnLayoutPropertyChanged(DependencyObject sender, DependencyPropertyChangedEventArgs args)
    {
        _ = args;
        ((InspectorSlider)sender).ApplyLayout();
    }

    private void ApplyLayout()
    {
        if (Root is null)
        {
            return;
        }

        SwatchDot.Background = Swatch;
        SwatchDot.Visibility = Swatch is null ? Visibility.Collapsed : Visibility.Visible;

        if (Compact)
        {
            // macOS `miniSlider` — 태그 12 · 사이 6 · 값 38, 전부 한 줄입니다.
            LeadColumn.Width = new GridLength(12);
            ValueColumn.Width = new GridLength(38);
            Root.ColumnSpacing = 6;
            Root.RowSpacing = 0;
            Grid.SetColumnSpan(LabelPanel, 1);
            Grid.SetRow(SliderHost, 0);
            Grid.SetColumn(SliderHost, 1);
            Grid.SetColumnSpan(SliderHost, 1);
            SliderHost.Margin = new Thickness(0, -8, 0, -8);
            SliderHost.Padding = new Thickness(0, 8, 0, 8);
            LabelText.FontFamily = new FontFamily("Consolas");
            LabelText.FontSize = 11;
            LabelText.Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"];
            return;
        }

        // 이름 줄 아래에 슬라이더가 폭을 다 씁니다.
        LeadColumn.Width = GridLength.Auto;
        ValueColumn.Width = new GridLength(ValueWidth);
        Root.ColumnSpacing = 0;
        Root.RowSpacing = LabelSpacing;
        Grid.SetColumnSpan(LabelPanel, 2);
        Grid.SetRow(SliderHost, 1);
        Grid.SetColumn(SliderHost, 0);
        Grid.SetColumnSpan(SliderHost, 3);
        SliderHost.Margin = new Thickness(-8);
        SliderHost.Padding = new Thickness(8);
        LabelText.ClearValue(TextBlock.FontFamilyProperty);
        LabelText.FontSize = 12;
        LabelText.ClearValue(TextBlock.ForegroundProperty);
    }
}
