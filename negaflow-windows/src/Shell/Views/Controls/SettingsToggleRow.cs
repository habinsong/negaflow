using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace Negaflow.Shell.Views.Controls;

/// <summary>
/// 라벨 + 스위치 한 줄입니다. macOS <c>AppSettingsToggleRow</c>
/// (<c>Toggle(label, isOn:).toggleStyle(.switch)</c>) 자리입니다.
/// </summary>
/// <remarks>
/// <para>
/// <b>한 줄입니다.</b> macOS 스위치에는 "켬/끔" 글자가 붙지 않습니다. WinUI
/// <see cref="ToggleSwitch"/> 는 기본 <c>MinWidth</c> 가 154 이고 <c>OnContent</c>/
/// <c>OffContent</c> 에 "On"/"Off" 가 들어 있어, 그대로 두면 라벨이 밀려 줄바꿈이 생깁니다.
/// 그래서 여기서 폭을 0 으로 풀고 글자를 비웁니다.
/// </para>
/// <para>
/// 라벨은 말줄임입니다. 줄바꿈하면 행 높이가 제각각이 되어 카드 안 오와열이 무너집니다.
/// </para>
/// </remarks>
public sealed class SettingsToggleRow : ContentControl
{
    private readonly TextBlock label = new()
    {
        FontSize = SettingsLayout.RowFontSize,
        VerticalAlignment = VerticalAlignment.Center,
        TextWrapping = TextWrapping.NoWrap,
        TextTrimming = TextTrimming.CharacterEllipsis,
    };

    private readonly ToggleSwitch toggle = new()
    {
        MinWidth = 0,
        Width = 40,
        OnContent = string.Empty,
        OffContent = string.Empty,
        VerticalAlignment = VerticalAlignment.Center,
        HorizontalAlignment = HorizontalAlignment.Right,
    };

    public SettingsToggleRow()
    {
        MinHeight = SettingsLayout.CompactRowHeight;
        HorizontalAlignment = HorizontalAlignment.Stretch;
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
        Grid grid = new()
        {
            ColumnSpacing = 12,
            Padding = new Thickness(
                SettingsLayout.RowHorizontalPadding, 0, SettingsLayout.RowHorizontalPadding, 0),
            MinHeight = SettingsLayout.CompactRowHeight,
        };
        grid.ColumnDefinitions.Add(
            new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(label);
        Grid.SetColumn(toggle, 1);
        grid.Children.Add(toggle);
        Content = grid;
        toggle.Toggled += OnToggled;
    }

    /// <summary>사용자가 스위치를 움직였습니다. <see cref="IsOn"/> 을 코드로 바꿀 때는 나지 않습니다.</summary>
    public event EventHandler? Switched;

    public static readonly DependencyProperty LabelProperty = DependencyProperty.Register(
        nameof(Label),
        typeof(string),
        typeof(SettingsToggleRow),
        new PropertyMetadata(string.Empty, OnLabelChanged));

    public string Label
    {
        get => (string)GetValue(LabelProperty);
        set => SetValue(LabelProperty, value);
    }

    /// <summary>
    /// 스위치 값입니다. 코드에서 넣을 때는 <see cref="Switched"/> 가 나지 않습니다 — 화면을
    /// 저장값에 맞추는 것과 사용자가 바꾸는 것은 다른 일입니다.
    /// </summary>
    public bool IsOn
    {
        get => toggle.IsOn;
        set
        {
            if (toggle.IsOn == value)
            {
                return;
            }
            isSynchronizing = true;
            toggle.IsOn = value;
            isSynchronizing = false;
        }
    }

    public new bool IsEnabled
    {
        get => toggle.IsEnabled;
        set => toggle.IsEnabled = value;
    }

    /// <summary>테스트와 접근성이 스위치 자체를 짚을 수 있게 이름을 답니다.</summary>
    public string AutomationId
    {
        get => AutomationProperties.GetAutomationId(toggle);
        set => AutomationProperties.SetAutomationId(toggle, value);
    }

    private bool isSynchronizing;

    private static void OnLabelChanged(
        DependencyObject sender,
        DependencyPropertyChangedEventArgs args)
    {
        if (sender is SettingsToggleRow row)
        {
            string text = (string)args.NewValue ?? string.Empty;
            row.label.Text = text;
            AutomationProperties.SetName(row.toggle, text);
        }
    }

    private void OnToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (!isSynchronizing)
        {
            Switched?.Invoke(this, EventArgs.Empty);
        }
    }
}
