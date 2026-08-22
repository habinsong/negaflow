using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.Views.Controls;

/// <summary>
/// macOS <c>ExportActionPill</c>(Features/Export/ExportActionPill.swift) 그대로입니다.
/// </summary>
/// <remarks>
/// <para>
/// <c>HStack(spacing: 2) { 동작 단추; 폴더 열기 }</c> 를 <c>liquidSurface(cornerRadius: 15)</c>
/// 한 덩어리에 담습니다. 실측(<c>현상뷰_좌측탭_세로탭_내보내기.png</c>): 덩어리 높이 32 ·
/// 라운딩 15 · 안쪽 동작 단추 라운딩 12 · 폴더 단추 24 원 · 오른쪽 여백 3. 강조(내보내기)는
/// <b>강조색 20% 바탕에 강조색 글자</b>이지 강조색으로 꽉 채운 단추가 아닙니다.
/// </para>
/// <para>
/// <b>색을 <c>Application.Current.Resources["..."]</c> 로 읽지 않습니다.</b> 그 조회는
/// <c>ThemeDictionaries</c> 를 요소의 테마로 풀지 않아, 창이 어두운데 밝은 사전의 값이
/// 나옵니다 — 빠른 내보내기 단추가 <b>어두운 카드 위 검은 글자·투명 바탕</b>이 되어 통째로
/// 없는 것처럼 보이던 원인이 이것입니다. 색은 <see cref="SettingsBrushes"/> 붙임 속성으로
/// 받습니다(App.xaml 의 암시적 Style 이 <c>{ThemeResource}</c> 로 채웁니다).
/// </para>
/// </remarks>
public sealed class ExportActionPill : UserControl, IThemedSettingsControl
{
    private readonly Border surface = new() { CornerRadius = new CornerRadius(15) };
    private readonly Border actionFill = new() { CornerRadius = new CornerRadius(12) };
    private readonly Button action = new();
    private readonly Button reveal = new();
    private readonly FontIcon actionIcon = new() { FontSize = 13 };
    private readonly FontIcon revealIcon = new() { FontSize = 12, Glyph = "" };
    private readonly TextBlock actionText = new()
    {
        FontSize = 12,
        FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
        VerticalAlignment = VerticalAlignment.Center,
        TextTrimming = TextTrimming.CharacterEllipsis,
    };

    /// <summary>도는 동안 채워지는 막대입니다. 동작 단추 안쪽에 왼쪽부터 찹니다.</summary>
    private readonly Border progressFill = new()
    {
        CornerRadius = new CornerRadius(12),
        HorizontalAlignment = HorizontalAlignment.Left,
        IsHitTestVisible = false,
        Visibility = Visibility.Collapsed,
    };

    /// <summary>"3/8 · 38%" 입니다. 도는 동안에만 나옵니다.</summary>
    private readonly TextBlock progressText = new()
    {
        FontSize = 11,
        VerticalAlignment = VerticalAlignment.Center,
        Margin = new Thickness(6, 0, 8, 0),
        Visibility = Visibility.Collapsed,
        IsHitTestVisible = false,
    };

    private readonly Grid actionCell = new();

    private bool isProminent;
    private bool isActionEnabled = true;
    private ExportProgress progress = ExportProgress.Idle;

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
        // macOS `.frame(maxWidth: .infinity, minHeight: 32).padding(.leading, 8)`.
        action.MinHeight = 32;
        action.Padding = new Thickness(8, 0, 0, 0);
        action.Style = (Style)Application.Current.Resources["NegaflowPillButtonStyle"];
        action.Click += (_, _) => Invoked?.Invoke(this, EventArgs.Empty);

        reveal.Content = revealIcon;
        reveal.Style = (Style)Application.Current.Resources["NegaflowPillResetButtonStyle"];
        reveal.Click += (_, _) => RevealRequested?.Invoke(this, EventArgs.Empty);

        label.Children.Add(progressText);

        actionCell.Children.Add(actionFill);
        actionCell.Children.Add(progressFill);
        actionCell.Children.Add(action);
        actionCell.SizeChanged += (_, _) => LayoutProgress();

        Grid row = new() { ColumnSpacing = 2, Padding = new Thickness(0, 0, 3, 0) };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.Children.Add(actionCell);
        Grid.SetColumn(reveal, 1);
        row.Children.Add(reveal);

        surface.Child = row;
        Content = surface;
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
            ApplyBrushes();
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
            ApplyBrushes();
        }
    }

    /// <summary>
    /// 몇 장 중 몇 장까지 갔는지입니다. <see cref="ExportProgress.Idle"/> 이면 표시가
    /// 사라지고 단추가 평소 모습으로 돌아갑니다.
    /// </summary>
    public ExportProgress Progress
    {
        get => progress;
        set
        {
            progress = value;
            progressText.Text = value.DisplayText;
            Visibility shown = value.IsRunning ? Visibility.Visible : Visibility.Collapsed;
            progressText.Visibility = shown;
            progressFill.Visibility = shown;
            LayoutProgress();
            ApplyBrushes();
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

    /// <summary>채움 너비를 지금 진행에 맞춥니다. 크기가 바뀔 때도 다시 잽니다.</summary>
    private void LayoutProgress()
    {
        if (!progress.IsRunning || actionCell.ActualWidth <= 0)
        {
            progressFill.Width = 0;
            return;
        }
        progressFill.Height = actionCell.ActualHeight;
        progressFill.Width = actionCell.ActualWidth * progress.Fraction;
    }

    /// <summary>Style 세터가 테마 색을 넣어 주면 여기서 칠합니다.</summary>
    public void ApplyBrushes()
    {
        surface.Background = SettingsBrushes.GetSurfaceBrush(this);
        surface.BorderBrush = SettingsBrushes.GetStrokeBrush(this);
        surface.BorderThickness = surface.BorderBrush is null
            ? new Thickness(0)
            : new Thickness(1);
        revealIcon.Foreground = SettingsBrushes.GetPrimaryForeground(this);
        // 채움은 강조색 살짝, 글자는 옅게 — 단추 이름을 덮지 않아야 합니다.
        progressFill.Background = SettingsBrushes.GetAccentSoftBrush(this);
        progressText.Foreground = SettingsBrushes.GetSecondaryForeground(this);
        if (!isActionEnabled)
        {
            actionFill.Background = null;
            actionText.Foreground = SettingsBrushes.GetSecondaryForeground(this);
            actionIcon.Foreground = actionText.Foreground;
            return;
        }
        if (isProminent)
        {
            actionFill.Background = SettingsBrushes.GetAccentSoftBrush(this);
            actionText.Foreground = SettingsBrushes.GetAccentBrush(this);
            actionIcon.Foreground = actionText.Foreground;
            return;
        }
        actionFill.Background = null;
        actionText.Foreground = SettingsBrushes.GetPrimaryForeground(this);
        actionIcon.Foreground = actionText.Foreground;
    }
}
