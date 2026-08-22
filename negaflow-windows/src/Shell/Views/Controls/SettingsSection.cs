using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Negaflow.Shell.Views.Controls;

/// <summary>
/// 설정창의 섹션 하나입니다 — 굵은 머리글 + 둥근 카드. macOS <c>AppSettingsSection</c>
/// (<c>Form(.grouped)</c> 의 <c>Section</c>) 자리입니다.
/// </summary>
/// <remarks>
/// <para>
/// 자식으로 <see cref="SettingsRow"/> · <see cref="SettingsFootnote"/> 를 넣으면 **행 사이
/// 분리선을 여기서 넣습니다.** 자리마다 <c>Border Height="1"</c> 을 손으로 끼우면 위아래
/// 여백이 제각각이 되고, 지금 설정창이 정확히 그렇게 되어 있습니다.
/// </para>
/// <para>
/// 설명문(<see cref="SettingsFootnote"/>) 앞에도 선이 들어갑니다 — 일반.png 의 메모리 캐시
/// 카드에서 "현상 결과" 아래 y=461 에 분리선이 있습니다.
/// </para>
/// </remarks>
[Microsoft.UI.Xaml.Markup.ContentProperty(Name = nameof(Rows))]
public sealed class SettingsSection : ContentControl, IThemedSettingsControl
{
    private readonly TextBlock header = new()
    {
        FontSize = SettingsLayout.SectionHeaderFontSize,
        FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
        Margin = new Thickness(0, 0, 0, SettingsLayout.SectionHeaderGap),
    };

    private readonly StackPanel rows = new();

    private readonly Border card = new()
    {
        CornerRadius = new CornerRadius(SettingsLayout.CardCornerRadius),
    };

    public SettingsSection()
    {
        HorizontalAlignment = HorizontalAlignment.Stretch;
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
        card.Child = rows;
        StackPanel root = new();
        root.Children.Add(header);
        root.Children.Add(card);
        Content = root;
        Loaded += (_, _) => Apply();
    }

    public static readonly DependencyProperty HeaderTextProperty = DependencyProperty.Register(
        nameof(HeaderText),
        typeof(string),
        typeof(SettingsSection),
        new PropertyMetadata(string.Empty, OnHeaderTextChanged));

    public string HeaderText
    {
        get => (string)GetValue(HeaderTextProperty);
        set => SetValue(HeaderTextProperty, value);
    }

    /// <summary>
    /// 카드 라운딩입니다. 설정창은 실측 10, 현상 좌측탭의 내보내기 카드는 12 입니다
    /// (<c>현상뷰_좌측탭_세로탭_내보내기.png</c> 의 왼쪽 위 모서리). 자리마다 다르므로 받습니다.
    /// </summary>
    public static readonly DependencyProperty CardCornerRadiusProperty =
        DependencyProperty.Register(
            nameof(CardCornerRadius),
            typeof(double),
            typeof(SettingsSection),
            new PropertyMetadata(SettingsLayout.CardCornerRadius, (sender, args) =>
                ((SettingsSection)sender).card.CornerRadius =
                    new CornerRadius((double)args.NewValue)));

    public double CardCornerRadius
    {
        get => (double)GetValue(CardCornerRadiusProperty);
        set => SetValue(CardCornerRadiusProperty, value);
    }

    /// <summary>카드 안에 들어가는 행들입니다. XAML 에서 자식으로 씁니다.</summary>
    public UIElementCollection Rows => rows.Children;

    private static void OnHeaderTextChanged(
        DependencyObject sender,
        DependencyPropertyChangedEventArgs args)
    {
        if (sender is SettingsSection section)
        {
            section.header.Text = (string)args.NewValue ?? string.Empty;
            section.header.Visibility = string.IsNullOrEmpty(section.header.Text)
                ? Visibility.Collapsed
                : Visibility.Visible;
        }
    }

    /// <summary>테마가 바뀌면 Style 세터가 새 색을 넣고 여기가 다시 칠합니다.</summary>
    public void ApplyBrushes() => Apply();

    /// <summary>행을 넣은 뒤 부릅니다. 분리선을 다시 놓습니다.</summary>
    public void Apply()
    {
        if (SettingsBrushes.GetCardBackground(this) is { } cardBrush)
        {
            card.Background = cardBrush;
        }
        Brush divider = SettingsBrushes.GetDividerBrush(this) ?? card.Background;
        // 먼저 예전 분리선을 걷어냅니다 — 다시 부를 때 줄이 겹쳐 쌓이지 않도록.
        for (int index = rows.Children.Count - 1; index >= 0; --index)
        {
            if (rows.Children[index] is Border { Tag: SeparatorTag })
            {
                rows.Children.RemoveAt(index);
            }
        }
        for (int index = rows.Children.Count - 1; index >= 1; --index)
        {
            // 접혀 있는 행 앞에는 선을 넣지 않습니다 — 선만 남아 빈 줄처럼 보입니다.
            if (rows.Children[index] is FrameworkElement { Visibility: Visibility.Collapsed } ||
                PrecedingVisible(index) is null)
            {
                continue;
            }
            rows.Children.Insert(index, new Border
            {
                Tag = SeparatorTag,
                Height = 1,
                Background = divider,
                Margin = new Thickness(
                    SettingsLayout.SeparatorInset, 0, SettingsLayout.SeparatorInset, 0),
            });
        }
    }

    /// <summary>
    /// 이 요소가 <see cref="Apply"/> 가 끼워 넣은 분리선인지입니다. 카드 안의 행을 훑는
    /// 쪽에서 분리선을 <b>행으로 착각하지 않도록</b> 여기서 알려 줍니다 — 밖에서 표식
    /// 문자열을 다시 적으면 이 값이 바뀔 때 조용히 어긋납니다.
    /// </summary>
    public static bool IsSeparator(object element) =>
        element is Border { Tag: SeparatorTag };

    /// <summary>이 자리 앞에 보이는 행이 있는지입니다. 없으면 선을 놓지 않습니다.</summary>
    private UIElement? PrecedingVisible(int index)
    {
        for (int probe = index - 1; probe >= 0; --probe)
        {
            if (rows.Children[probe] is FrameworkElement { Visibility: Visibility.Visible } found)
            {
                return found;
            }
        }
        return null;
    }

    private const string SeparatorTag = "negaflow.settings.separator";
}
