using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;

namespace Negaflow.Shell.Views.Controls;

/// <summary>
/// 라벨과 수치는 윗줄, 슬라이더는 아랫줄 전폭입니다. macOS <c>AppSettingsSliderRow</c> 자리입니다.
/// </summary>
/// <remarks>
/// macOS 주석 원문: "라벨 열 오른쪽에 슬라이더를 밀어 넣으면 트랙이 짧아져 조작 정밀도가
/// 떨어진다." 같은 이유로 여기서도 슬라이더를 아랫줄 전폭에 둡니다.
/// </remarks>
public sealed class SettingsSliderRow : ContentControl, IThemedSettingsControl
{
    private readonly TextBlock label = new()
    {
        FontSize = SettingsLayout.RowFontSize,
        VerticalAlignment = VerticalAlignment.Center,
        TextWrapping = TextWrapping.NoWrap,
        TextTrimming = TextTrimming.CharacterEllipsis,
    };

    private readonly TextBlock valueText = new()
    {
        FontSize = SettingsLayout.RowFontSize,
        VerticalAlignment = VerticalAlignment.Center,
        HorizontalAlignment = HorizontalAlignment.Right,
        FontFamily = new FontFamily("Segoe UI Variable Text"),
    };

    private readonly Slider slider = new()
    {
        HorizontalAlignment = HorizontalAlignment.Stretch,
        StepFrequency = 1,
        // 눈금을 그리면 노이즈만 늘어납니다. macOS 도 `step:` 을 슬라이더에 주지 않습니다.
        TickFrequency = 0,
        Margin = new Thickness(0, -4, 0, 0),
    };

    public SettingsSliderRow()
    {
        HorizontalAlignment = HorizontalAlignment.Stretch;
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
        Grid head = new() { ColumnSpacing = 8 };
        head.ColumnDefinitions.Add(
            new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        head.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        head.Children.Add(label);
        Grid.SetColumn(valueText, 1);
        head.Children.Add(valueText);
        StackPanel stack = new() { Spacing = 4 };
        stack.Children.Add(head);
        stack.Children.Add(slider);
        Padding = new Thickness(
            SettingsLayout.RowHorizontalPadding, 8, SettingsLayout.RowHorizontalPadding, 8);
        Content = stack;
        slider.ValueChanged += OnSliderValueChanged;
    }

    public void ApplyBrushes()
    {
        if (SettingsBrushes.GetSecondaryForeground(this) is { } secondary)
        {
            valueText.Foreground = secondary;
        }
    }

    /// <summary>사용자가 슬라이더를 움직였습니다. 코드로 값을 넣을 때는 나지 않습니다.</summary>
    public event EventHandler? ValuePicked;

    public static readonly DependencyProperty LabelProperty = DependencyProperty.Register(
        nameof(Label), typeof(string), typeof(SettingsSliderRow),
        new PropertyMetadata(string.Empty, (sender, args) =>
        {
            var row = (SettingsSliderRow)sender;
            row.label.Text = (string)args.NewValue ?? string.Empty;
            AutomationProperties.SetName(row.slider, row.label.Text);
        }));

    public string Label
    {
        get => (string)GetValue(LabelProperty);
        set => SetValue(LabelProperty, value);
    }

    public string ValueLabel
    {
        get => valueText.Text;
        set
        {
            valueText.Text = value;
            AutomationProperties.SetHelpText(slider, value);
        }
    }

    public int Value => (int)Math.Round(slider.Value);

    /// <summary>범위와 값을 함께 놓습니다. 코드에서 부르므로 <see cref="ValuePicked"/> 는 나지 않습니다.</summary>
    public void Configure(int minimum, int maximum, int value)
    {
        isSynchronizing = true;
        // 최소가 최대보다 크면 WinUI 가 값을 조용히 뒤집습니다. macOS 도 같은 방어를 합니다
        // (`max(range.lowerBound + 1, range.upperBound)`).
        slider.Minimum = minimum;
        slider.Maximum = Math.Max(minimum + 1, maximum);
        slider.Value = Math.Clamp(value, minimum, (int)slider.Maximum);
        isSynchronizing = false;
    }

    private bool isSynchronizing;

    private void OnSliderValueChanged(object sender, RangeBaseValueChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (!isSynchronizing)
        {
            ValuePicked?.Invoke(this, EventArgs.Empty);
        }
    }
}
