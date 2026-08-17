using Microsoft.UI.Xaml;
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

    public bool AutoColorIsOn => AutoColorToggle.IsChecked == true;

    public bool AutoLevelsIsOn => AutoLevelsToggle.IsChecked == true;

    public void Localize()
    {
        DevelopInspectorSectionChrome.SetToggleText(
            AutoColorToggle, AppResources.Get("developAutoColor", "Content"));
        DevelopInspectorSectionChrome.SetToggleText(
            AutoLevelsToggle, AppResources.Get("developAutoLevels", "Content"));
        DevelopInspectorSectionChrome.SetButtonText(
            AutoToneButton, AppResources.Get("developAutoTone", "Content"));
        DevelopInspectorSectionChrome.SetButtonText(
            AutoWhiteBalanceButton, AppResources.Get("developAutoWhiteBalance", "Content"));
    }

    public void Show(DevelopPanelState panel)
    {
        Visibility autoCorrections = panel.ShowsAutoCorrections
            ? Visibility.Visible
            : Visibility.Collapsed;
        AutoColorToggle.Visibility = autoCorrections;
        AutoLevelsToggle.Visibility = autoCorrections;
        AutoColorToggle.IsChecked = panel.AutoNeutralBalance;
        AutoLevelsToggle.IsChecked = panel.AutoLevels;
    }

    public void SetAutoAdjustEnabled(bool enabled)
    {
        AutoToneButton.IsEnabled = enabled;
        AutoWhiteBalanceButton.IsEnabled = enabled;
    }

    public void SetStatus(string text) => AutoAdjustStatusText.Text = text;

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
}
