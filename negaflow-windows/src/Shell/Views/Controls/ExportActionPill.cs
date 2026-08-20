using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Negaflow.Shell.Views.Controls;

/// <summary>
/// macOS <c>ExportActionPill</c>(Features/Export/ExportActionPill.swift) 그대로입니다.
/// </summary>
/// <remarks>
/// <para>
/// <c>HStack(spacing: 2) { 동작 단추; 폴더 열기 단추 }</c> 를 라운딩 15 의 한 덩어리에 담습니다.
/// 동작 단추는 높이 32 · 왼쪽 여백 8 · 라운딩 12 이고, 강조(내보내기)이면 <b>강조색 20%</b>
/// 바탕에 강조색 글자입니다 — 강조색으로 꽉 채운 단추가 아닙니다. 오른쪽 폴더 단추는 24×24
/// 원이며 오른쪽 여백이 3 입니다.
/// </para>
/// <para>
/// 아이콘은 도구막대가 이미 쓰는 것과 같은 글리프입니다 — 내보내기 <c>E72D</c>, 빠른
/// 내보내기 <c>E945</c>. 같은 명령에 다른 그림을 쓰지 않습니다.
/// </para>
/// </remarks>
public sealed class ExportActionPill : UserControl
{
    private readonly Button action = new();
    private readonly Button reveal = new();
    private readonly FontIcon actionIcon = new() { FontSize = 13 };
    private readonly TextBlock actionText = new()
    {
        FontSize = 12,
        FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
        VerticalAlignment = VerticalAlignment.Center,
        TextTrimming = TextTrimming.CharacterEllipsis,
    };

    private bool isProminent;
    private bool isActionEnabled = true;

    public ExportActionPill()
    {
        HorizontalAlignment = HorizontalAlignment.Stretch;

        StackPanel label = new()
        {
            Orientation = Orientation.Horizontal,
            Spacing = 6,
            VerticalAlignment = VerticalAlignment.Center,
        };
        label.Children.Add(actionIcon);
        label.Children.Add(actionText);

        action.Content = label;
        action.MinHeight = 32;
        action.Padding = new Thickness(8, 0, 8, 0);
        action.HorizontalAlignment = HorizontalAlignment.Stretch;
        action.HorizontalContentAlignment = HorizontalAlignment.Center;
        action.CornerRadius = new CornerRadius(12);
        action.BorderThickness = new Thickness(0);
        action.Click += (_, _) => Invoked?.Invoke(this, EventArgs.Empty);

        reveal.Content = new FontIcon { FontSize = 12, Glyph = "" };
        reveal.Width = 24;
        reveal.Height = 24;
        reveal.MinWidth = 24;
        reveal.MinHeight = 24;
        reveal.Padding = new Thickness(0);
        reveal.CornerRadius = new CornerRadius(12);
        reveal.BorderThickness = new Thickness(0);
        reveal.Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent);
        reveal.Click += (_, _) => RevealRequested?.Invoke(this, EventArgs.Empty);

        Grid row = new() { ColumnSpacing = 2, Padding = new Thickness(0, 0, 3, 0) };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.Children.Add(action);
        Grid.SetColumn(reveal, 1);
        row.Children.Add(reveal);

        Content = new Border
        {
            CornerRadius = new CornerRadius(15),
            Background = (Brush)Application.Current.Resources["NegaflowSubtleFillBrush"],
            Child = row,
        };
        ApplyAppearance();
    }

    /// <summary>macOS <c>action</c> — 내보내기·빠른 내보내기 자체입니다.</summary>
    public event EventHandler? Invoked;

    /// <summary>macOS <c>reveal</c> — 산출물이 놓인 폴더를 엽니다.</summary>
    public event EventHandler? RevealRequested;

    /// <summary>참이면 macOS <c>isProminent</c> — 강조색 20% 바탕에 강조색 글자입니다.</summary>
    public bool IsProminent
    {
        get => isProminent;
        set
        {
            isProminent = value;
            ApplyAppearance();
        }
    }

    /// <summary>macOS <c>isActionEnabled</c>. 폴더 열기는 이것과 무관하게 살아 있습니다.</summary>
    public bool IsActionEnabled
    {
        get => isActionEnabled;
        set
        {
            isActionEnabled = value;
            action.IsEnabled = value;
            ApplyAppearance();
        }
    }

    public string Glyph
    {
        get => actionIcon.Glyph;
        set => actionIcon.Glyph = value;
    }

    public string Title
    {
        get => actionText.Text;
        set
        {
            actionText.Text = value;
            AutomationProperties.SetName(action, value);
            ToolTipService.SetToolTip(action, value);
        }
    }

    /// <summary>폴더 열기 단추의 이름입니다. macOS <c>revealHelp</c>.</summary>
    public string RevealHelp
    {
        set
        {
            AutomationProperties.SetName(reveal, value);
            ToolTipService.SetToolTip(reveal, value);
        }
    }

    public string ActionAutomationId
    {
        set => AutomationProperties.SetAutomationId(action, value);
    }

    public string RevealAutomationId
    {
        set => AutomationProperties.SetAutomationId(reveal, value);
    }

    private void ApplyAppearance()
    {
        if (!isActionEnabled)
        {
            action.Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent);
            actionText.Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"];
            actionIcon.Foreground = actionText.Foreground;
            return;
        }
        if (isProminent)
        {
            action.Background = (Brush)Application.Current.Resources["NegaflowAccentSoftBrush"];
            actionText.Foreground = (Brush)Application.Current.Resources["NegaflowAccentBrush"];
            actionIcon.Foreground = actionText.Foreground;
            return;
        }
        action.Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent);
        actionText.Foreground = (Brush)Application.Current.Resources["TextFillColorPrimaryBrush"];
        actionIcon.Foreground = actionText.Foreground;
    }
}
