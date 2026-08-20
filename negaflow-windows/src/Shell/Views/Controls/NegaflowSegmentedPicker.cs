using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Controls;

/// <summary>한 칸입니다. 값과 화면에 보일 이름을 같이 듭니다.</summary>
public sealed record SegmentOption(object Value, string Label);

/// <summary>
/// macOS <c>SegmentedPicker</c> 를 그대로 옮긴 것입니다
/// (<c>Sources/negaflowApp/Shared/UI/SegmentedPicker.swift</c>).
///
/// 수치도 그대로입니다 — 트랙 라운딩 11 · 안쪽 여백 3 · 칸 사이 3 · 칸 높이 28 ·
/// 선택 칸 라운딩 8 · 칸은 폭을 **똑같이 나눠 가짐** · 선택 글자만 SemiBold.
///
/// ☠️ 이 자리에 <c>ComboBox</c> 나 라디오 동그라미를 두면 macOS 와 모양이 다릅니다.
///    같은 컨트롤이 인화 방향·눈금자·시트 색상, 스캔 프레임 찾기, 출력 방식 등 여러 곳에
///    나오므로 한 벌만 두고 씁니다.
/// </summary>
public sealed class NegaflowSegmentedPicker : ContentControl
{
    private readonly Grid track = new() { ColumnSpacing = 3 };
    private readonly List<Button> buttons = [];
    private IReadOnlyList<SegmentOption> options = [];

    public NegaflowSegmentedPicker()
    {
        Padding = new Thickness(3);
        CornerRadius = new CornerRadius(11);
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
        HorizontalAlignment = HorizontalAlignment.Stretch;
        Background = TrackBrush();
        Content = track;
    }

    /// <summary>고른 값이 바뀌면 올립니다. 같은 값을 다시 눌러도 올리지 않습니다.</summary>
    public event EventHandler? SelectionChanged;

    public object? SelectedValue { get; private set; }

    /// <summary>칸을 다시 놓습니다. 고른 값이 목록에 없으면 첫 칸을 고릅니다.</summary>
    public void SetOptions(IReadOnlyList<SegmentOption> values, object? selected)
    {
        ArgumentNullException.ThrowIfNull(values);
        options = values;
        track.Children.Clear();
        track.ColumnDefinitions.Clear();
        buttons.Clear();
        for (int index = 0; index < values.Count; ++index)
        {
            track.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            SegmentOption option = values[index];
            Button button = new()
            {
                Content = option.Label,
                Tag = option.Value,
                Height = 28,
                Padding = new Thickness(4, 0, 4, 0),
                HorizontalAlignment = HorizontalAlignment.Stretch,
                BorderThickness = new Thickness(0),
                CornerRadius = new CornerRadius(8),
                FontSize = 12,
            };
            AutomationProperties.SetName(button, option.Label);
            button.Click += OnSegmentClicked;
            Grid.SetColumn(button, index);
            track.Children.Add(button);
            buttons.Add(button);
        }
        Select(selected ?? (values.Count > 0 ? values[0].Value : null), raise: false);
    }

    /// <summary>값만 바꿉니다. 목록은 그대로입니다.</summary>
    public void SetSelected(object? value) => Select(value, raise: false);

    private void OnSegmentClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (sender is Button { Tag: { } value })
        {
            Select(value, raise: true);
        }
    }

    private void Select(object? value, bool raise)
    {
        bool changed = !Equals(SelectedValue, value);
        SelectedValue = value;
        Brush thumb = (Brush)Application.Current.Resources["NegaflowCardBrush"];
        Brush clear = new SolidColorBrush(Microsoft.UI.Colors.Transparent);
        Brush primary = (Brush)Application.Current.Resources["TextFillColorPrimaryBrush"];
        Brush secondary = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"];
        for (int index = 0; index < buttons.Count; ++index)
        {
            bool selected = index < options.Count && Equals(options[index].Value, value);
            Button button = buttons[index];
            button.Background = selected ? thumb : clear;
            button.Foreground = selected ? primary : secondary;
            button.FontWeight = selected
                ? Microsoft.UI.Text.FontWeights.SemiBold
                : Microsoft.UI.Text.FontWeights.Normal;
            AutomationProperties.SetItemStatus(
                button,
                AppResources.Get(selected ? "selected" : "notSelected", "Value"));
        }
        if (changed && raise)
        {
            SelectionChanged?.Invoke(this, EventArgs.Empty);
        }
    }

    /// <summary>macOS 트랙은 primary 7% 입니다. 테마 자원 중 같은 뜻의 것을 씁니다.</summary>
    private static Brush TrackBrush() =>
        (Brush)Application.Current.Resources["NegaflowSubtleFillBrush"];
}
