using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Negaflow.Shell.Views.Controls;

/// <summary>고를 수 있는 한 항목입니다. <c>Tag</c> 로 값을 알아봅니다.</summary>
public sealed record PopupPickerOption(string Text, object? Tag);

/// <summary>팝업 단추의 두 가지 겉모습입니다. 둘 다 macOS 에 실제로 있는 자리입니다.</summary>
public enum PopupPickerVariant
{
    /// <summary>
    /// 값 오른쪽에 20 원. macOS <c>ExportSection</c> 의 <c>Picker</c> 자리입니다
    /// (스크린샷 <c>현상뷰_좌측탭_세로탭_내보내기.png</c> 의 형식 · DPI · 크기).
    /// </summary>
    Stepper,

    /// <summary>
    /// 겹화살이 값 <b>왼쪽</b>에 붙고 원이 없습니다. macOS
    /// <c>PrintInspectorPopupPicker</c> 자리입니다(스크린샷 <c>인화뷰_기본.png</c> 의
    /// 레이아웃 · 용지 크기 · 표면).
    /// </summary>
    Inline,
}

/// <summary>
/// macOS <c>Picker</c> 가 <c>Form</c> 안에서 내는 팝업 단추입니다.
/// </summary>
/// <remarks>
/// <para>
/// 실측(<c>현상뷰_좌측탭_세로탭_내보내기.png</c>): <b>값 글자 + 20×20 원</b>이고 원 안에
/// 위·아래 겹화살(<c>chevron.up.chevron.down</c>)이 있습니다. 원 바탕은
/// <c>Color.primary.opacity(0.12)</c>, 오른쪽 여백 3, 글자와 원 사이 6 입니다.
/// </para>
/// <para>
/// WinUI 기본 <c>ComboBox</c> 는 네모 상자에 테두리를 두르고 값을 왼쪽에 붙입니다 —
/// macOS 와 모양·정렬·음영이 모두 다릅니다. 그래서 여기서 팝업 단추를 직접 냅니다.
/// 목록은 <see cref="MenuFlyout"/> 이며 고른 항목에 체크가 붙습니다.
/// </para>
/// </remarks>
public sealed class NegaflowPopupPicker : Button, IThemedSettingsControl
{
    /// <summary>실측: 원 지름 20.</summary>
    private const double StepperDiameter = 20;

    private readonly TextBlock valueText = new()
    {
        FontSize = 12,
        VerticalAlignment = VerticalAlignment.Center,
        TextTrimming = TextTrimming.CharacterEllipsis,
        TextWrapping = TextWrapping.NoWrap,
    };

    private readonly Border stepper = new()
    {
        Width = StepperDiameter,
        Height = StepperDiameter,
        CornerRadius = new CornerRadius(StepperDiameter / 2),
        Margin = new Thickness(6, 0, 3, 0),
        VerticalAlignment = VerticalAlignment.Center,
    };

    private readonly VectorIcon stepperIcon = new()
    {
        Kind = VectorIconKind.ChevronUpChevronDown,
        IconSize = 12,
        // 12px 에서 기본 두께는 0.8 화소라 화면에서 사라집니다. macOS 는 이 표식을
        // `.semibold` 로 냅니다 — 같은 굵기가 되도록 올립니다.
        StrokeScale = 1.8,
        HorizontalAlignment = HorizontalAlignment.Center,
        VerticalAlignment = VerticalAlignment.Center,
    };

    private readonly StackPanel row = new()
    {
        Orientation = Orientation.Horizontal,
        VerticalAlignment = VerticalAlignment.Center,
    };

    /// <summary>
    /// 인화 인스펙터의 줄입니다. macOS 의 <c>Spacer(minLength: 8)</c> 자리를 남는 열 하나로
    /// 냅니다 — 값은 왼쪽 끝에, 겹화살은 오른쪽 끝에 붙습니다.
    /// </summary>
    private readonly Grid inlineRow = new()
    {
        VerticalAlignment = VerticalAlignment.Center,
        ColumnDefinitions =
        {
            new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) },
            new ColumnDefinition { Width = GridLength.Auto },
        },
    };

    private readonly MenuFlyout menu = new();
    private readonly List<PopupPickerOption> options = [];
    private int selectedIndex = -1;

    public NegaflowPopupPicker()
    {
        stepper.Child = stepperIcon;
        row.Children.Add(valueText);
        row.Children.Add(stepper);
        Content = row;
        Flyout = menu;

        // 화면마다 붙는 순서가 다릅니다 — Style 이 붙기 전에 값을 채우는 화면에서는
        // 색이 null 인 채로 칠해집니다. 여기서 한 번 더 칠합니다.
        Loaded += (_, _) => ApplyBrushes();
    }

    /// <summary>겉모습입니다. 자리마다 macOS 가 쓰는 것이 다릅니다.</summary>
    public PopupPickerVariant Variant
    {
        get;
        set
        {
            field = value;
            ApplyVariant();
        }
    }

    /// <summary>
    /// macOS 의 두 팝업 단추를 그대로 냅니다.
    /// </summary>
    /// <remarks>
    /// 인화 인스펙터는 macOS <c>PrintInspectorPopupPicker</c> 그대로입니다 —
    /// <c>HStack { Text ; Spacer(minLength: 8) ; chevron }</c> 에
    /// <c>.frame(maxWidth: .infinity, minHeight: 30)</c>. 즉 <b>값은 왼쪽 끝, 겹화살은
    /// 오른쪽 끝</b>이고 줄 전체가 누르는 자리이며 원 바탕이 없습니다.
    /// </remarks>
    private void ApplyVariant()
    {
        row.Children.Clear();
        inlineRow.Children.Clear();
        if (Variant == PopupPickerVariant.Inline)
        {
            stepper.Background = null;
            stepper.Width = double.NaN;
            stepper.Height = double.NaN;
            stepper.Margin = new Thickness(8, 0, 0, 0);
            valueText.TextAlignment = TextAlignment.Left;
            valueText.HorizontalAlignment = HorizontalAlignment.Left;
            Grid.SetColumn(valueText, 0);
            Grid.SetColumn(stepper, 1);
            inlineRow.Children.Add(valueText);
            inlineRow.Children.Add(stepper);
            Content = inlineRow;
            HorizontalContentAlignment = HorizontalAlignment.Stretch;
            Style = (Style)Application.Current.Resources["NegaflowInlinePopupPickerStyle"];
            return;
        }
        Content = row;
        valueText.HorizontalAlignment = HorizontalAlignment.Stretch;
        stepper.Width = StepperDiameter;
        stepper.Height = StepperDiameter;
        stepper.Margin = new Thickness(6, 0, 3, 0);
        valueText.TextAlignment = TextAlignment.Right;
        row.Children.Add(valueText);
        row.Children.Add(stepper);
        ApplyBrushes();
    }

    /// <summary>고른 항목이 바뀌었을 때입니다. 사람이 골랐을 때만 올립니다.</summary>
    public event EventHandler? SelectionChanged;

    public IReadOnlyList<PopupPickerOption> Options => options;

    public int SelectedIndex => selectedIndex;

    public object? SelectedTag =>
        selectedIndex >= 0 && selectedIndex < options.Count ? options[selectedIndex].Tag : null;

    /// <summary>목록을 갈아 끼웁니다. 고른 자리는 초기화합니다.</summary>
    public void SetOptions(IReadOnlyList<PopupPickerOption> values)
    {
        ArgumentNullException.ThrowIfNull(values);
        options.Clear();
        options.AddRange(values);
        selectedIndex = -1;
        valueText.Text = string.Empty;
        // 목록은 여기서 바로 짓습니다. 여는 순간으로 미루면 WinUI 가 팝업 크기를 먼저 재기
        // 때문에 <b>빈 회색 네모</b>가 뜹니다. 목록이 길어지는 것은 글꼴 가족만 담아 막습니다
        // (`PrintCaptionFonts.Merge`).
        RebuildMenu();
    }

    /// <summary>값으로 고릅니다. 없는 값이면 아무 것도 바꾸지 않습니다.</summary>
    public void SelectByTag(object? tag)
    {
        for (int index = 0; index < options.Count; ++index)
        {
            if (Equals(options[index].Tag, tag))
            {
                SelectSilently(index);
                return;
            }
        }
    }

    /// <summary>자리로 고릅니다. 알림은 올리지 않습니다.</summary>
    public void SelectSilently(int index)
    {
        if (index < 0 || index >= options.Count)
        {
            return;
        }
        selectedIndex = index;
        valueText.Text = options[index].Text;
        // 목록을 다시 만들지 않고 체크만 옮깁니다. 이 메서드는 슬라이더를 끄는 동안에도
        // 매번 불리므로, 여기서 MenuFlyout 을 새로 지으면 그만큼 UI 스레드가 밀립니다.
        SynchronizeChecks();
    }

    /// <summary>Style 세터가 테마 색을 넣어 주면 여기서 칠합니다.</summary>
    public void ApplyBrushes()
    {
        valueText.Foreground = SettingsBrushes.GetPrimaryForeground(this) ?? valueText.Foreground;
        // 인라인은 원이 없습니다 — macOS 도 겹화살만 보조색으로 냅니다.
        stepper.Background = Variant == PopupPickerVariant.Inline
            ? null
            : SettingsBrushes.GetHoverBrush(this);
        stepperIcon.Foreground = Variant == PopupPickerVariant.Inline
            ? SettingsBrushes.GetSecondaryForeground(this) ?? stepperIcon.Foreground
            : SettingsBrushes.GetPrimaryForeground(this) ?? stepperIcon.Foreground;
    }

    private void RebuildMenu()
    {
        menu.Items.Clear();
        for (int index = 0; index < options.Count; ++index)
        {
            PopupPickerOption option = options[index];
            ToggleMenuFlyoutItem item = new()
            {
                Text = option.Text,
                IsChecked = index == selectedIndex,
            };
            int chosen = index;
            item.Click += (_, _) =>
            {
                // 고른 것을 다시 누르면 체크가 꺼집니다 — macOS 팝업은 늘 하나가 켜져
                // 있으므로 되돌려 놓습니다.
                if (chosen == selectedIndex)
                {
                    SynchronizeChecks();
                    return;
                }
                SelectSilently(chosen);
                SelectionChanged?.Invoke(this, EventArgs.Empty);
            };
            menu.Items.Add(item);
        }
    }

    /// <summary>고른 자리에만 체크를 둡니다.</summary>
    private void SynchronizeChecks()
    {
        for (int index = 0; index < menu.Items.Count; ++index)
        {
            if (menu.Items[index] is ToggleMenuFlyoutItem item)
            {
                item.IsChecked = index == selectedIndex;
            }
        }
    }
}
