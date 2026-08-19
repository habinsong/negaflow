using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Develop.Inspector;

/// <summary>
/// macOS 의 자동 색상·자동 레벨 토글과 자동 톤·자동 화이트 밸런스 동작입니다.
/// recipe 쓰기와 엔진 호출은 뷰가 맡습니다.
/// </summary>
public sealed partial class DevelopQuickActionsCard : UserControl
{
    public DevelopQuickActionsCard() => InitializeComponent();

    public event EventHandler? AutoColorToggled;

    public event EventHandler? AutoLevelsToggled;

    public event EventHandler? AutoToneClicked;

    public event EventHandler? AutoWhiteBalanceClicked;

    /// <summary>macOS <c>onResetAutoTone</c> — 알약 오른쪽 원형 단추입니다.</summary>
    public event EventHandler? AutoToneResetClicked;

    /// <summary>macOS <c>onResetAutoWhiteBalance</c>.</summary>
    public event EventHandler? AutoWhiteBalanceResetClicked;

    public bool AutoColorIsOn => AutoColorToggle.IsChecked == true;

    public bool AutoLevelsIsOn => AutoLevelsToggle.IsChecked == true;

    public void Localize()
    {
        AutoColorText.Text = AppResources.Get("developAutoColor", "Content");
        AutomationProperties.SetName(AutoColorToggle, AutoColorText.Text);
        ToolTipService.SetToolTip(AutoColorToggle, AutoColorText.Text);
        AutoLevelsText.Text = AppResources.Get("developAutoLevels", "Content");
        AutomationProperties.SetName(AutoLevelsToggle, AutoLevelsText.Text);
        ToolTipService.SetToolTip(AutoLevelsToggle, AutoLevelsText.Text);
        AutoToneText.Text = AppResources.Get("developAutoTone", "Content");
        AutomationProperties.SetName(AutoToneButton, AutoToneText.Text);
        // macOS 는 알약 전체에 도움말을 답니다(autoToneHelp / autoWhiteBalanceHelp).
        ToolTipService.SetToolTip(AutoTonePill, AppResources.Get("developAutoToneHelp", "Text"));
        AutoWhiteBalanceText.Text = AppResources.Get("developAutoWhiteBalance", "Content");
        AutomationProperties.SetName(AutoWhiteBalanceButton, AutoWhiteBalanceText.Text);
        ToolTipService.SetToolTip(
            AutoWhiteBalancePill,
            AppResources.Get("developAutoWhiteBalanceHelp", "Text"));
        string reset = AppResources.Get("developReset", "Value");
        AutomationProperties.SetName(AutoToneResetButton, reset);
        ToolTipService.SetToolTip(AutoToneResetButton, reset);
        AutomationProperties.SetName(AutoWhiteBalanceResetButton, reset);
        ToolTipService.SetToolTip(AutoWhiteBalanceResetButton, reset);
    }

    public void Show(DevelopPanelState panel)
    {
        // macOS 는 LazyVGrid 라, 자동 색상·자동 레벨이 빠지면 자동 톤·자동 화이트 밸런스가
        // 첫 줄로 올라옵니다. Grid 는 줄이 비어도 RowSpacing 을 넣으므로 줄을 옮깁니다.
        bool autoCorrections = panel.ShowsAutoCorrections;
        Visibility visibility = autoCorrections ? Visibility.Visible : Visibility.Collapsed;
        AutoColorSurface.Visibility = visibility;
        AutoLevelsSurface.Visibility = visibility;
        int actionRow = autoCorrections ? 1 : 0;
        Grid.SetRow(AutoTonePill, actionRow);
        Grid.SetRow(AutoWhiteBalancePill, actionRow);
        AutoColorToggle.IsChecked = panel.AutoNeutralBalance;
        AutoLevelsToggle.IsChecked = panel.AutoLevels;
    }

    /// <summary>
    /// macOS 는 알약 전체(표면 포함)를 흐리게 합니다 — <c>.disabled(!canAutoAdjust)</c>.
    /// </summary>
    public void SetAutoAdjustEnabled(bool enabled)
    {
        AutoToneButton.IsEnabled = enabled;
        AutoWhiteBalanceButton.IsEnabled = enabled;
        AutoToneResetButton.IsEnabled = enabled;
        AutoWhiteBalanceResetButton.IsEnabled = enabled;
        double opacity = enabled ? 1.0 : 0.4;
        AutoTonePill.Opacity = opacity;
        AutoWhiteBalancePill.Opacity = opacity;
    }

    public void SetStatus(string text)
    {
        AutoAdjustStatusText.Text = text;
        AutoAdjustStatusText.Visibility = string.IsNullOrEmpty(text)
            ? Visibility.Collapsed
            : Visibility.Visible;
    }

    private void OnAutoColorToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        AutoColorToggled?.Invoke(this, EventArgs.Empty);
    }

    private void OnAutoLevelsToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        AutoLevelsToggled?.Invoke(this, EventArgs.Empty);
    }

    private void OnAutoToneClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        AutoToneClicked?.Invoke(this, EventArgs.Empty);
    }

    private void OnAutoWhiteBalanceClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        AutoWhiteBalanceClicked?.Invoke(this, EventArgs.Empty);
    }

    private void OnAutoToneResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        AutoToneResetClicked?.Invoke(this, EventArgs.Empty);
    }

    private void OnAutoWhiteBalanceResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        AutoWhiteBalanceResetClicked?.Invoke(this, EventArgs.Empty);
    }
}
