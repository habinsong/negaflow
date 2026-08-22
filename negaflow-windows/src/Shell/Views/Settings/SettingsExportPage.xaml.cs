using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Negaflow.Shell.Views.Settings;

/// <summary>
/// 설정 창의 내보내기 탭 화면입니다. 빠른 내보내기·무결성 검사·색상 관리 카드가 여기 모입니다.
/// </summary>
/// <remarks>
/// XAML 은 <c>SettingsRootView.xaml</c> 에서 그대로 옮겨 왔고, 이벤트는 옮기기 전과 같은
/// <see cref="SettingsRootView"/> 메서드로 그대로 넘깁니다 — 탭 로직은
/// <c>SettingsRootView.ExportTab.cs</c> 에 그대로 있습니다.
/// </remarks>
public sealed partial class SettingsExportPage : UserControl
{
    internal SettingsRootView? Owner;

    public SettingsExportPage() => InitializeComponent();

    private void OnQuickExportDpiChanged(object sender, SelectionChangedEventArgs args) =>
        Owner?.OnQuickExportDpiChanged(sender, args);

    private void OnQuickExportSizeChanged(object sender, SelectionChangedEventArgs args) =>
        Owner?.OnQuickExportSizeChanged(sender, args);

    private void OnExportColorSpaceChanged(object sender, SelectionChangedEventArgs args) =>
        Owner?.OnExportColorSpaceChanged(sender, args);

    private void OnChooseSoftProofProfile(object sender, RoutedEventArgs args) =>
        Owner?.OnChooseSoftProofProfile(sender, args);

    private void OnResetSoftProofProfile(object sender, RoutedEventArgs args) =>
        Owner?.OnResetSoftProofProfile(sender, args);

    private void OnSoftProofSimulationChanged(object sender, SelectionChangedEventArgs args) =>
        Owner?.OnSoftProofSimulationChanged(sender, args);

    private void OnChoosePrinterProfile(object sender, RoutedEventArgs args) =>
        Owner?.OnChoosePrinterProfile(sender, args);

    private void OnResetPrinterProfile(object sender, RoutedEventArgs args) =>
        Owner?.OnResetPrinterProfile(sender, args);
}
