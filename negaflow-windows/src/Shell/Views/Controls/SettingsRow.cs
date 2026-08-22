using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Negaflow.Shell.Views.Controls;

/// <summary>
/// 라벨 + 컨트롤 한 행입니다. macOS <c>AppSettingsRow</c>(<c>LabeledContent</c>) 자리입니다.
/// </summary>
/// <remarks>
/// <para>
/// **라벨은 왼쪽, 컨트롤은 오른쪽 끝**입니다. 컨트롤을 늘려 붙이거나 왼쪽으로 밀지
/// 마십시오 — macOS 는 컨트롤을 제 크기 그대로 오른쪽에 세웁니다. 지금 설정창은 컨트롤에
/// 폭 230 을 하드코딩해 두어 값이 짧아도 상자가 길게 남아 있습니다.
/// </para>
/// <para>
/// **라벨은 줄바꿈하지 않습니다.** 길면 말줄임입니다. 줄바꿈하면 행 높이가 제각각이 되어
/// 카드 안의 오와열이 무너집니다.
/// </para>
/// </remarks>
[Microsoft.UI.Xaml.Markup.ContentProperty(Name = nameof(Control))]
public sealed class SettingsRow : ContentControl
{
    private readonly TextBlock label = new()
    {
        FontSize = SettingsLayout.RowFontSize,
        VerticalAlignment = VerticalAlignment.Center,
        TextWrapping = TextWrapping.NoWrap,
        TextTrimming = TextTrimming.CharacterEllipsis,
    };

    private readonly ContentPresenter presenter = new()
    {
        HorizontalAlignment = HorizontalAlignment.Right,
        VerticalAlignment = VerticalAlignment.Center,
    };

    public SettingsRow()
    {
        MinHeight = SettingsLayout.RowHeight;
        HorizontalAlignment = HorizontalAlignment.Stretch;
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
        Grid grid = new()
        {
            ColumnSpacing = 12,
            Padding = new Thickness(SettingsLayout.RowHorizontalPadding, 0, SettingsLayout.RowHorizontalPadding, 0),
            MinHeight = SettingsLayout.RowHeight,
        };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(label);
        Grid.SetColumn(presenter, 1);
        grid.Children.Add(presenter);
        // ContentControl 의 Content 는 오른쪽 컨트롤이므로, 골격은 Template 대신 여기서 답니다.
        base.Content = grid;
        RegisterPropertyChangedCallback(ContentProperty, (_, _) => MoveContentIntoPresenter());
    }

    public static readonly DependencyProperty LabelProperty = DependencyProperty.Register(
        nameof(Label),
        typeof(string),
        typeof(SettingsRow),
        new PropertyMetadata(string.Empty, OnLabelChanged));

    public string Label
    {
        get => (string)GetValue(LabelProperty);
        set => SetValue(LabelProperty, value);
    }

    /// <summary>오른쪽에 세울 컨트롤입니다.</summary>
    public object? Control
    {
        get => presenter.Content;
        set => presenter.Content = value;
    }

    private static void OnLabelChanged(
        DependencyObject sender,
        DependencyPropertyChangedEventArgs args)
    {
        if (sender is SettingsRow row)
        {
            row.label.Text = (string)args.NewValue ?? string.Empty;
        }
    }

    private void MoveContentIntoPresenter()
    {
        // XAML 에서 <controls:SettingsRow>…</controls:SettingsRow> 로 넣은 자식을 오른쪽
        // 자리로 옮깁니다. 그러지 않으면 골격 Grid 를 덮어써 라벨이 사라집니다.
        if (base.Content is Grid)
        {
            return;
        }
        object? incoming = base.Content;
        base.Content = null;
        Control = incoming;
        Grid grid = new()
        {
            ColumnSpacing = 12,
            Padding = new Thickness(SettingsLayout.RowHorizontalPadding, 0, SettingsLayout.RowHorizontalPadding, 0),
            MinHeight = SettingsLayout.RowHeight,
        };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(label);
        Grid.SetColumn(presenter, 1);
        grid.Children.Add(presenter);
        base.Content = grid;
    }
}

/// <summary>
/// 라벨 + 오른쪽 값 글자입니다. macOS <c>AppSettingsValueRow</c> 자리입니다.
/// </summary>
/// <remarks>
/// <see cref="Reason"/> 을 주면 값 아래에 작은 회색 줄이 **오른쪽 맞춤**으로 붙습니다 —
/// 스캔 탭의 "사용 불가 / 현재 스캔 옵션 조합에서 --brightness 가 비활성입니다." 자리입니다.
/// </remarks>
public sealed class SettingsValueRow : ContentControl, IThemedSettingsControl
{
    private readonly TextBlock label = new()
    {
        FontSize = SettingsLayout.RowFontSize,
        VerticalAlignment = VerticalAlignment.Center,
        TextWrapping = TextWrapping.NoWrap,
        TextTrimming = TextTrimming.CharacterEllipsis,
    };

    private readonly TextBlock value = new()
    {
        FontSize = SettingsLayout.RowFontSize,
        TextAlignment = TextAlignment.Right,
        TextWrapping = TextWrapping.Wrap,
    };

    private readonly TextBlock reason = new()
    {
        FontSize = SettingsLayout.FootnoteFontSize,
        TextAlignment = TextAlignment.Right,
        TextWrapping = TextWrapping.Wrap,
        Visibility = Visibility.Collapsed,
    };

    public SettingsRowValueKind Kind { get; set; } = SettingsRowValueKind.Primary;

    public SettingsValueRow()
    {
        MinHeight = SettingsLayout.CompactRowHeight;
        HorizontalAlignment = HorizontalAlignment.Stretch;
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
        StackPanel right = new()
        {
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center,
            Spacing = 2,
        };
        right.Children.Add(value);
        right.Children.Add(reason);
        Grid grid = new()
        {
            ColumnSpacing = 12,
            Padding = new Thickness(
                SettingsLayout.RowHorizontalPadding, 6, SettingsLayout.RowHorizontalPadding, 6),
            MinHeight = SettingsLayout.CompactRowHeight,
        };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.Children.Add(label);
        Grid.SetColumn(right, 1);
        grid.Children.Add(right);
        Content = grid;
    }

    public static readonly DependencyProperty LabelProperty = DependencyProperty.Register(
        nameof(Label), typeof(string), typeof(SettingsValueRow),
        new PropertyMetadata(string.Empty, (s, a) =>
            ((SettingsValueRow)s).label.Text = (string)a.NewValue ?? string.Empty));

    public static readonly DependencyProperty ValueTextProperty = DependencyProperty.Register(
        nameof(ValueText), typeof(string), typeof(SettingsValueRow),
        new PropertyMetadata(string.Empty, (s, a) =>
            ((SettingsValueRow)s).value.Text = (string)a.NewValue ?? string.Empty));

    public static readonly DependencyProperty ReasonProperty = DependencyProperty.Register(
        nameof(Reason), typeof(string), typeof(SettingsValueRow),
        new PropertyMetadata(string.Empty, (s, a) =>
        {
            var row = (SettingsValueRow)s;
            string text = (string)a.NewValue ?? string.Empty;
            row.reason.Text = text;
            row.reason.Visibility = text.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
        }));

    public string Label
    {
        get => (string)GetValue(LabelProperty);
        set => SetValue(LabelProperty, value);
    }

    public string ValueText
    {
        get => (string)GetValue(ValueTextProperty);
        set => SetValue(ValueTextProperty, value);
    }

    public string Reason
    {
        get => (string)GetValue(ReasonProperty);
        set => SetValue(ReasonProperty, value);
    }

    /// <summary>Style 세터가 색을 넣어 주면 안쪽 글자에 바릅니다.</summary>
    public void ApplyBrushes()
    {
        if (SettingsBrushes.GetSecondaryForeground(this) is not { } secondary)
        {
            return;
        }
        value.Foreground = Kind == SettingsRowValueKind.Primary ? Foreground : secondary;
        reason.Foreground = secondary;
    }
}

public enum SettingsRowValueKind
{
    Primary,
    Secondary,
}

/// <summary>
/// 카드 안 마지막에 붙는 설명문입니다. macOS <c>AppSettingsHelpText</c> 자리 —
/// 작은 글자, 보조색, <b>왼쪽 맞춤 전폭</b>, 줄바꿈 허용.
/// </summary>
public sealed class SettingsFootnote : ContentControl, IThemedSettingsControl
{
    private readonly TextBlock text = new()
    {
        FontSize = SettingsLayout.FootnoteFontSize,
        LineHeight = SettingsLayout.FootnoteLineHeight,
        LineStackingStrategy = LineStackingStrategy.BlockLineHeight,
        TextWrapping = TextWrapping.Wrap,
        HorizontalAlignment = HorizontalAlignment.Left,
    };

    public SettingsFootnote()
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

    /// <summary>경고문처럼 색을 따로 줄 때 씁니다.</summary>
    public void OverrideForeground(Brush brush) => text.Foreground = brush;

    public static readonly DependencyProperty TextProperty = DependencyProperty.Register(
        nameof(Text), typeof(string), typeof(SettingsFootnote),
        new PropertyMetadata(string.Empty, (s, a) =>
            ((SettingsFootnote)s).text.Text = (string)a.NewValue ?? string.Empty));

    public string Text
    {
        get => (string)GetValue(TextProperty);
        set => SetValue(TextProperty, value);
    }
}
