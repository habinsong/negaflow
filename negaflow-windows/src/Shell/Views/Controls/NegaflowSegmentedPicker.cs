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
/// 이 자리에 <c>ComboBox</c> 나 라디오 동그라미를 두면 macOS 와 모양이 다릅니다.
/// 같은 컨트롤이 인화 방향·눈금자·시트 색상, 스캔 프레임 찾기, 출력 방식 등 여러 곳에
/// 나오므로 한 벌만 두고 씁니다.
/// </summary>
public sealed class NegaflowSegmentedPicker : ContentControl, IThemedSettingsControl
{
    private readonly Grid track = new() { ColumnSpacing = 3 };
    private readonly List<Button> buttons = [];
    private IReadOnlyList<SegmentOption> options = [];

    /// <summary>
    /// 트랙을 칠하는 자리입니다. <b>ContentControl 의 기본 판형은 <c>Background</c> 도
    /// <c>CornerRadius</c> 도 그리지 않습니다</b> — 자리표(ContentPresenter) 하나뿐입니다.
    /// 그래서 컨트롤에 색을 걸어 두어도 트랙 캡슐이 아예 나오지 않았고, 화면에는 글자 셋만
    /// 벌어져 보였습니다(사용자 신고). 색을 실제로 그리는 Border 를 여기서 답니다.
    /// </summary>
    private readonly Border surface = new()
    {
        Padding = new Thickness(3),
        CornerRadius = new CornerRadius(11),
        HorizontalAlignment = HorizontalAlignment.Stretch,
    };

    public NegaflowSegmentedPicker()
    {
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
        HorizontalAlignment = HorizontalAlignment.Stretch;
        surface.Child = track;
        Content = surface;
        // 붙는 순서가 화면마다 다릅니다 — 어떤 화면은 Style 이 붙기 **전에** SetOptions 를
        // 부릅니다. 그때 브러시는 아직 null 이므로 여기서 한 번 더 칠합니다.
        Loaded += (_, _) => ApplyBrushes();
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
                // 판형은 바탕을 덮지 않습니다 — 고른 칸의 음영은 아래 `Select` 가 칠합니다.
                Style = (Style)Application.Current.Resources["NegaflowSegmentButtonStyle"],
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

    /// <summary>Style 세터가 색을 넣어 주면 트랙과 칸을 다시 칠합니다.</summary>
    public void ApplyBrushes() => Select(SelectedValue, raise: false);

    private void Select(object? value, bool raise)
    {
        bool changed = !Equals(SelectedValue, value);
        SelectedValue = value;
        surface.Background = SettingsBrushes.GetTrackBrush(this);
        Brush thumb = SettingsBrushes.GetThumbBrush(this) ??
            new SolidColorBrush(Microsoft.UI.Colors.Transparent);
        Brush clear = new SolidColorBrush(Microsoft.UI.Colors.Transparent);
        Brush primary = Foreground;
        Brush secondary = SettingsBrushes.GetSecondaryForeground(this) ?? Foreground;
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

}
