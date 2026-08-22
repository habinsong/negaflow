using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views.Print.Settings;

/// <summary>
/// 인화 인스펙터 한 줄의 치수입니다. macOS <c>PrintInspectorMetrics</c> 와 같은 값입니다.
/// </summary>
public static class PrintInspectorMetrics
{
    /// <summary>
    /// 오른쪽 컨트롤 열의 고정 폭입니다. 모든 줄이 같은 오른쪽 경계를 나눠 가져야 오와열이
    /// 맞습니다 — 남는 폭 전체로 늘리면 패널이 넓어질수록 라벨과 컨트롤이 좌우로 갈라집니다.
    /// </summary>
    public const double ControlWidth = 148;

    public const double LabelMinimumWidth = 84;

    public const double HorizontalSpacing = 10;

    public const double VerticalSpacing = 10;

    public const double RowMinimumHeight = 30;

    /// <summary>줄 사이 분리선의 진하기입니다. macOS `.opacity(0.4)`.</summary>
    public const double DividerOpacity = 0.4;
}

/// <summary>
/// 라벨(왼쪽) + 컨트롤(오른쪽 고정 폭) 한 줄입니다. macOS <c>PrintInspectorRow</c>.
/// </summary>
public sealed class PrintInspectorRow : ContentControl
{
    private readonly TextBlock label = new()
    {
        FontSize = 12,
        VerticalAlignment = VerticalAlignment.Center,
        TextTrimming = TextTrimming.CharacterEllipsis,
        MinWidth = PrintInspectorMetrics.LabelMinimumWidth,
    };

    private readonly Grid host = new()
    {
        ColumnSpacing = PrintInspectorMetrics.HorizontalSpacing,
        MinHeight = PrintInspectorMetrics.RowMinimumHeight,
    };

    private readonly ContentPresenter control = new()
    {
        Width = PrintInspectorMetrics.ControlWidth,
        HorizontalAlignment = HorizontalAlignment.Right,
        VerticalAlignment = VerticalAlignment.Center,
    };

    public PrintInspectorRow()
    {
        host.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        host.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        host.Children.Add(label);
        Grid.SetColumn(control, 1);
        host.Children.Add(control);
        base.Content = host;
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
    }

    public static readonly DependencyProperty LabelProperty = DependencyProperty.Register(
        nameof(Label),
        typeof(string),
        typeof(PrintInspectorRow),
        new PropertyMetadata(string.Empty, (sender, args) =>
        {
            if (sender is PrintInspectorRow row)
            {
                row.label.Text = (string)args.NewValue ?? string.Empty;
            }
        }));

    public string Label
    {
        get => (string)GetValue(LabelProperty);
        set => SetValue(LabelProperty, value);
    }

    /// <summary>오른쪽 칸에 놓을 컨트롤입니다.</summary>
    public new object? Content
    {
        get => control.Content;
        set => control.Content = value;
    }
}

/// <summary>
/// 라벨 아래에 풀폭 컨트롤을 놓는 줄입니다. macOS <c>PrintInspectorStackedField</c> —
/// 선택지가 여럿인 컨트롤을 오른쪽 고정 열에 밀어 넣지 않아 좌우 균형이 남습니다.
/// </summary>
public sealed class PrintInspectorStackedField : ContentControl
{
    private readonly TextBlock label = new()
    {
        FontSize = 12,
        TextTrimming = TextTrimming.CharacterEllipsis,
    };

    private readonly StackPanel host = new() { Spacing = 6 };

    private readonly ContentPresenter control = new()
    {
        HorizontalAlignment = HorizontalAlignment.Stretch,
        HorizontalContentAlignment = HorizontalAlignment.Stretch,
    };

    public PrintInspectorStackedField()
    {
        host.Children.Add(label);
        host.Children.Add(control);
        base.Content = host;
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
    }

    public static readonly DependencyProperty LabelProperty = DependencyProperty.Register(
        nameof(Label),
        typeof(string),
        typeof(PrintInspectorStackedField),
        new PropertyMetadata(string.Empty, (sender, args) =>
        {
            if (sender is PrintInspectorStackedField field)
            {
                field.label.Text = (string)args.NewValue ?? string.Empty;
            }
        }));

    public string Label
    {
        get => (string)GetValue(LabelProperty);
        set => SetValue(LabelProperty, value);
    }

    public new object? Content
    {
        get => control.Content;
        set => control.Content = value;
    }
}

/// <summary>
/// 라벨과 컨트롤을 같은 줄에 두는 인화 인스펙터 행입니다. macOS
/// <c>PrintInspectorInlineField</c> — 간격 7, 최소 높이 30.
/// </summary>
public sealed class PrintInspectorInlineField : ContentControl
{
    private readonly TextBlock label = new()
    {
        FontSize = 12,
        VerticalAlignment = VerticalAlignment.Center,
        TextTrimming = TextTrimming.CharacterEllipsis,
    };

    private readonly Grid host = new()
    {
        ColumnSpacing = 7,
        MinHeight = PrintInspectorMetrics.RowMinimumHeight,
    };

    private readonly ContentPresenter control = new()
    {
        HorizontalAlignment = HorizontalAlignment.Stretch,
        HorizontalContentAlignment = HorizontalAlignment.Right,
        VerticalAlignment = VerticalAlignment.Center,
    };

    public PrintInspectorInlineField()
    {
        host.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        host.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        host.Children.Add(label);
        Grid.SetColumn(control, 1);
        host.Children.Add(control);
        base.Content = host;
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
    }

    public static readonly DependencyProperty LabelProperty = DependencyProperty.Register(
        nameof(Label),
        typeof(string),
        typeof(PrintInspectorInlineField),
        new PropertyMetadata(string.Empty, (sender, args) =>
        {
            if (sender is PrintInspectorInlineField field)
            {
                field.label.Text = (string)args.NewValue ?? string.Empty;
            }
        }));

    public string Label
    {
        get => (string)GetValue(LabelProperty);
        set => SetValue(LabelProperty, value);
    }

    public new object? Content
    {
        get => control.Content;
        set => control.Content = value;
    }
}

/// <summary>
/// 줄 사이 분리선입니다. macOS 는 <c>Divider().opacity(0.4)</c> 로 섹션 안 무리를 가릅니다.
/// </summary>
public sealed class PrintInspectorDivider : ContentControl, IThemedSettingsControl
{
    private readonly Border line = new() { Height = 1 };

    public PrintInspectorDivider()
    {
        Opacity = PrintInspectorMetrics.DividerOpacity;
        Margin = new Thickness(0, 2, 0, 2);
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
        Content = line;
        IsTabStop = false;
        // Style 이 붙는 시점이 화면마다 달라 색이 null 인 채로 남을 수 있습니다 — 그러면
        // 선이 통째로 안 보입니다(사용자 신고). 붙고 나서 한 번 더 칠합니다.
        Loaded += (_, _) => ApplyBrushes();
    }

    public void ApplyBrushes() =>
        line.Background = SettingsBrushes.GetDividerBrush(this) ?? line.Background;
}
