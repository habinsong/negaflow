using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Negaflow.Shell.Views.Controls;

/// <summary>
/// 라벨 + 경로 + 단추들 한 줄입니다. macOS <c>DiskStorageSettingsSection.pathRow</c> 자리입니다.
/// </summary>
/// <remarks>
/// <para>
/// <b>경로는 줄이지 않습니다.</b> "…" 로 가운데를 접으면 어느 자리인지 알 수 없고,
/// 사용자가 그 폴더를 찾아갈 수도 없습니다. 길면 <b>접어서 두 줄</b>로 냅니다 — 줄 높이가
/// 늘어나는 편이 경로를 감추는 것보다 낫습니다.
/// </para>
/// <para>
/// 단추는 macOS 와 같은 차례입니다 — 커스텀일 때만 나오는 "변경", 그리고 늘 있는 "열기".
/// </para>
/// </remarks>
public sealed class SettingsPathRow : ContentControl, IThemedSettingsControl
{
    /// <summary>단추 폭입니다. 디스크_윗부분.png 실측 735..777.</summary>
    private const double ButtonWidth = 42;

    private readonly TextBlock label = new()
    {
        FontSize = SettingsLayout.RowFontSize,
        VerticalAlignment = VerticalAlignment.Center,
        TextWrapping = TextWrapping.NoWrap,
    };

    private readonly TextBlock path = new()
    {
        FontSize = SettingsLayout.RowFontSize,
        VerticalAlignment = VerticalAlignment.Center,
        TextAlignment = TextAlignment.Right,
        // 경로는 통째로 보여야 합니다. 좁으면 접습니다 — 자르지 않습니다.
        TextWrapping = TextWrapping.Wrap,
    };

    private readonly Button changeButton = new()
    {
        Width = ButtonWidth,
        Height = 24,
        Padding = new Thickness(0),
        Visibility = Visibility.Collapsed,
        // macOS "folder.badge.gearshape" 과 같은 뜻입니다 — 폴더를 **고르는** 자리.
        Content = new FontIcon { FontSize = 14, Glyph = "" },
    };

    private readonly Button revealButton = new()
    {
        Width = ButtonWidth,
        Height = 24,
        Padding = new Thickness(0),
        // macOS "folder" — 그 폴더를 **여는** 자리.
        Content = new FontIcon { FontSize = 14, Glyph = "" },
    };

    private string fullPath = string.Empty;

    public SettingsPathRow()
    {
        MinHeight = SettingsLayout.PathRowHeight;
        HorizontalAlignment = HorizontalAlignment.Stretch;
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
        StackPanel right = new()
        {
            Orientation = Orientation.Horizontal,
            Spacing = 6,
            VerticalAlignment = VerticalAlignment.Center,
        };
        right.Children.Add(changeButton);
        right.Children.Add(revealButton);
        Grid grid = new()
        {
            ColumnSpacing = 12,
            Padding = new Thickness(
                SettingsLayout.RowHorizontalPadding, 0, SettingsLayout.RowHorizontalPadding, 0),
            MinHeight = SettingsLayout.PathRowHeight,
        };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(
            new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(label);
        Grid.SetColumn(path, 1);
        grid.Children.Add(path);
        Grid.SetColumn(right, 2);
        grid.Children.Add(right);
        Content = grid;
        changeButton.Click += (_, _) => ChangeRequested?.Invoke(this, EventArgs.Empty);
        revealButton.Click += (_, _) => RevealRequested?.Invoke(this, EventArgs.Empty);
    }

    public void ApplyBrushes()
    {
        if (SettingsBrushes.GetSecondaryForeground(this) is { } secondary)
        {
            path.Foreground = secondary;
        }
    }

    public event EventHandler? ChangeRequested;

    public event EventHandler? RevealRequested;

    public static readonly DependencyProperty LabelProperty = DependencyProperty.Register(
        nameof(Label), typeof(string), typeof(SettingsPathRow),
        new PropertyMetadata(string.Empty, (sender, args) =>
        {
            var row = (SettingsPathRow)sender;
            row.label.Text = (string)args.NewValue ?? string.Empty;
            AutomationProperties.SetName(row.changeButton, row.label.Text);
            AutomationProperties.SetName(row.revealButton, row.label.Text);
        }));

    public string Label
    {
        get => (string)GetValue(LabelProperty);
        set => SetValue(LabelProperty, value);
    }

    /// <summary>보여 줄 경로입니다. 이미 <c>~</c> 로 줄인 것을 넣습니다.</summary>
    public string PathText
    {
        get => fullPath;
        set
        {
            fullPath = value ?? string.Empty;
            ToolTipService.SetToolTip(path, fullPath);
            path.Text = fullPath;
        }
    }

    /// <summary>"변경" 단추는 커스텀 방식에서만 나옵니다. macOS 와 같은 조건입니다.</summary>
    public bool CanChange
    {
        get => changeButton.Visibility == Visibility.Visible;
        set => changeButton.Visibility = value ? Visibility.Visible : Visibility.Collapsed;
    }

    public void SetButtonTooltips(string change, string reveal)
    {
        ToolTipService.SetToolTip(changeButton, change);
        ToolTipService.SetToolTip(revealButton, reveal);
    }

}
