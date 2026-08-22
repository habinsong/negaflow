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

    private readonly Grid frame;

    public SettingsRow()
    {
        MinHeight = SettingsLayout.RowHeight;
        HorizontalAlignment = HorizontalAlignment.Stretch;
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
        frame = BuildFrame();
        // ContentControl 의 Content 는 오른쪽 컨트롤이므로, 골격은 Template 대신 여기서 답니다.
        base.Content = frame;
        RegisterPropertyChangedCallback(ContentProperty, (_, _) => MoveContentIntoPresenter());
    }

    public static readonly DependencyProperty LabelProperty = DependencyProperty.Register(
        nameof(Label),
        typeof(string),
        typeof(SettingsRow),
        new PropertyMetadata(string.Empty, OnLabelChanged));

    /// <summary>
    /// 행 높이입니다. 설정창은 실측 41 이지만 현상 좌측탭의 내보내기 카드는 38 입니다
    /// (<c>현상뷰_좌측탭_세로탭_내보내기.png</c> 의 분리선 간격). 자리마다 다르므로 받습니다.
    /// </summary>
    public static readonly DependencyProperty RowHeightProperty = DependencyProperty.Register(
        nameof(RowHeight),
        typeof(double),
        typeof(SettingsRow),
        new PropertyMetadata(SettingsLayout.RowHeight, OnRowHeightChanged));

    public double RowHeight
    {
        get => (double)GetValue(RowHeightProperty);
        set => SetValue(RowHeightProperty, value);
    }

    /// <summary>라벨 글자 크기입니다. 좌측탭은 설정창보다 한 단 작습니다.</summary>
    public static readonly DependencyProperty LabelFontSizeProperty = DependencyProperty.Register(
        nameof(LabelFontSize),
        typeof(double),
        typeof(SettingsRow),
        new PropertyMetadata(SettingsLayout.RowFontSize, (sender, args) =>
            ((SettingsRow)sender).label.FontSize = (double)args.NewValue));

    public double LabelFontSize
    {
        get => (double)GetValue(LabelFontSizeProperty);
        set => SetValue(LabelFontSizeProperty, value);
    }

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

    private static void OnRowHeightChanged(
        DependencyObject sender,
        DependencyPropertyChangedEventArgs args)
    {
        var row = (SettingsRow)sender;
        double height = (double)args.NewValue;
        row.MinHeight = height;
        row.frame.MinHeight = height;
    }

    private Grid BuildFrame()
    {
        Grid grid = new()
        {
            ColumnSpacing = 12,
            Padding = new Thickness(SettingsLayout.RowHorizontalPadding, 0, SettingsLayout.RowHorizontalPadding, 0),
            MinHeight = RowHeight,
        };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(label);
        Grid.SetColumn(presenter, 1);
        grid.Children.Add(presenter);
        return grid;
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
        // 골격은 처음 만든 것을 그대로 다시 답니다. 다시 만들면 라벨·자리표가 옛 Grid 의
        // 자식으로 남아 있어 부모가 둘이 됩니다.
        base.Content = frame;
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

    private readonly Grid frame;

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
        frame = new Grid
        {
            ColumnSpacing = 12,
            Padding = new Thickness(
                SettingsLayout.RowHorizontalPadding, 6, SettingsLayout.RowHorizontalPadding, 6),
            MinHeight = SettingsLayout.CompactRowHeight,
        };
        frame.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        frame.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        frame.Children.Add(label);
        Grid.SetColumn(right, 1);
        frame.Children.Add(right);
        Content = frame;
    }

    /// <summary>행 높이입니다. <see cref="SettingsRow.RowHeight"/> 와 같은 이유로 받습니다.</summary>
    public static readonly DependencyProperty RowHeightProperty = DependencyProperty.Register(
        nameof(RowHeight),
        typeof(double),
        typeof(SettingsValueRow),
        new PropertyMetadata(SettingsLayout.CompactRowHeight, (sender, args) =>
        {
            var row = (SettingsValueRow)sender;
            row.MinHeight = (double)args.NewValue;
            row.frame.MinHeight = (double)args.NewValue;
        }));

    public double RowHeight
    {
        get => (double)GetValue(RowHeightProperty);
        set => SetValue(RowHeightProperty, value);
    }

    /// <summary>라벨 글자 크기입니다.</summary>
    public static readonly DependencyProperty LabelFontSizeProperty = DependencyProperty.Register(
        nameof(LabelFontSize),
        typeof(double),
        typeof(SettingsValueRow),
        new PropertyMetadata(SettingsLayout.RowFontSize, (sender, args) =>
            ((SettingsValueRow)sender).label.FontSize = (double)args.NewValue));

    public double LabelFontSize
    {
        get => (double)GetValue(LabelFontSizeProperty);
        set => SetValue(LabelFontSizeProperty, value);
    }

    /// <summary>값 글자 크기입니다. 좌측탭의 값은 라벨보다 한 단 작습니다.</summary>
    public static readonly DependencyProperty ValueFontSizeProperty = DependencyProperty.Register(
        nameof(ValueFontSize),
        typeof(double),
        typeof(SettingsValueRow),
        new PropertyMetadata(SettingsLayout.RowFontSize, (sender, args) =>
            ((SettingsValueRow)sender).value.FontSize = (double)args.NewValue));

    public double ValueFontSize
    {
        get => (double)GetValue(ValueFontSizeProperty);
        set => SetValue(ValueFontSizeProperty, value);
    }

    /// <summary>값 글자를 다른 색으로 덮습니다 — 잘못된 파일명 패턴을 빨갛게 낼 때입니다.</summary>
    public void OverrideValueForeground(Brush? brush) =>
        value.Foreground = brush ?? Foreground;

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
        value.Foreground = Kind switch
        {
            SettingsRowValueKind.Primary => Foreground,
            // 잘못된 값은 빨갛게 냅니다 — macOS 도 파일명 패턴이 깨지면 미리보기를
            // `Color.red` 로 칠합니다(ExportNamingControls.swift).
            SettingsRowValueKind.Danger =>
                SettingsBrushes.GetDangerBrush(this) ?? secondary,
            _ => secondary,
        };
        reason.Foreground = secondary;
    }
}

public enum SettingsRowValueKind
{
    Primary,
    Secondary,
    Danger,
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
