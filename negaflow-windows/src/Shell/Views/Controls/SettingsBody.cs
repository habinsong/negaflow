using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Negaflow.Shell.Views.Controls;

/// <summary>
/// 카드 하나를 통째로 채우는 본문입니다. macOS 법적 고지 화면의 각 구역이 이 모양입니다 —
/// 머리글 + 카드, 카드 안에는 문단 하나.
/// </summary>
/// <remarks>
/// 실측(법적고지.png): 글자 13px · 줄 간격 16 · 좌우 안쪽 여백 10 · 위아래 10 ·
/// 보조색 · 왼쪽 맞춤 전폭. 설명문(<see cref="SettingsFootnote"/>)보다 한 단 큽니다.
/// </remarks>
public sealed class SettingsBody : ContentControl, IThemedSettingsControl
{
    private readonly TextBlock text = new()
    {
        FontSize = SettingsLayout.RowFontSize,
        LineHeight = SettingsLayout.BodyLineHeight,
        LineStackingStrategy = LineStackingStrategy.BlockLineHeight,
        TextWrapping = TextWrapping.Wrap,
        HorizontalAlignment = HorizontalAlignment.Left,
        // 라이선스 문구는 사용자가 복사해 갈 수 있어야 합니다.
        IsTextSelectionEnabled = true,
    };

    public SettingsBody()
    {
        HorizontalAlignment = HorizontalAlignment.Stretch;
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
        Padding = new Thickness(
            SettingsLayout.RowHorizontalPadding,
            SettingsLayout.FootnoteVerticalPadding,
            SettingsLayout.RowHorizontalPadding,
            SettingsLayout.FootnoteVerticalPadding);
        Content = text;
    }

    public void ApplyBrushes()
    {
        if (SettingsBrushes.GetSecondaryForeground(this) is { } secondary)
        {
            text.Foreground = secondary;
        }
    }

    public static readonly DependencyProperty TextProperty = DependencyProperty.Register(
        nameof(Text), typeof(string), typeof(SettingsBody),
        new PropertyMetadata(string.Empty, (sender, args) =>
            ((SettingsBody)sender).text.Text = (string)args.NewValue ?? string.Empty));

    public string Text
    {
        get => (string)GetValue(TextProperty);
        set => SetValue(TextProperty, value);
    }
}
