using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Develop.Inspector;

/// <summary>
/// macOS <c>ResetControlsSection</c> — 모든 보정 초기화와 사진 각도 초기화 두 단추입니다.
/// 초기화 탭에서만 보입니다.
/// </summary>
public sealed partial class DevelopResetCard : UserControl
{
    public DevelopResetCard()
    {
        InitializeComponent();
        Localize();
    }

    /// <summary>모든 보정 초기화입니다. macOS 는 <c>resetAllDevelopAdjustments</c> 를 부릅니다.</summary>
    public event EventHandler? ResetAllAdjustmentsRequested;

    /// <summary>사진 각도 초기화입니다. macOS 는 <c>resetPhotoAngle</c> 을 부릅니다.</summary>
    public event EventHandler? ResetPhotoAngleRequested;

    public void Localize()
    {
        string reset = AppResources.Get("developReset", "Value");
        ResetSectionTitleText.Text = reset;
        AutomationProperties.SetName(ResetControlCard, reset);
        ResetAllAdjustmentsText.Text = AppResources.Get("shortcutResetAdjustments", "Text");
        AutomationProperties.SetName(ResetAllAdjustmentsButton, ResetAllAdjustmentsText.Text);
        // macOS 는 이 단추에만 도움말 문구를 답니다.
        ToolTipService.SetToolTip(
            ResetAllAdjustmentsButton,
            AppResources.Get("developResetAdjustmentsHelp", "Text"));
        ResetPhotoAngleText.Text = AppResources.Get("developResetPhotoAngle", "Text");
        AutomationProperties.SetName(ResetPhotoAngleButton, ResetPhotoAngleText.Text);
        ToolTipService.SetToolTip(ResetPhotoAngleButton, ResetPhotoAngleText.Text);
        // role: .destructive 자리입니다 — 되돌릴 수 없어 보이는 단추를 눈에 띄게 둡니다.
        ResetAllAdjustmentsText.Foreground =
            (Brush)Application.Current.Resources["SystemFillColorCriticalBrush"];
    }

    /// <summary>macOS <c>canResetPhotoAngle</c> 을 그대로 씁니다.</summary>
    public void Show(DevelopPanelState? panel)
    {
        bool hasFrame = panel?.SelectedFrame is not null;
        ResetAllAdjustmentsButton.IsEnabled = hasFrame;
        ResetPhotoAngleButton.IsEnabled = panel?.CanResetPhotoAngle == true;
    }

    private void OnResetAllAdjustmentsClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ResetAllAdjustmentsRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnResetPhotoAngleClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ResetPhotoAngleRequested?.Invoke(this, EventArgs.Empty);
    }
}
