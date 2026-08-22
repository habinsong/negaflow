using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;

namespace Negaflow.Shell.Views.Print.Settings;

/// <summary>
/// 인화 검사기의 레이아웃 탭 카드입니다. 판·칸·커스텀 배치·템플릿이 여기 모입니다.
/// </summary>
/// <remarks>
/// XAML 은 <c>PrintWorkspaceView.xaml</c> 에서 그대로 옮겨 왔고, 이벤트는 옮기기 전과 같은
/// <see cref="PrintWorkspaceView"/> 메서드로 그대로 넘깁니다.
/// </remarks>
public sealed partial class PrintLayoutTab : UserControl
{
    internal PrintWorkspaceView? Owner;

    public PrintLayoutTab() => InitializeComponent();

    private void OnPrintSettingChanged(object sender, SelectionChangedEventArgs args) =>
        Owner?.OnPrintSettingChanged(sender, args);

    /// <summary>
    /// 팝업 단추(<c>NegaflowPopupPicker</c>)는 <c>EventHandler</c> 를 냅니다 — ComboBox 의
    /// <c>SelectionChanged</c> 와 서명이 다르므로 따로 받습니다.
    /// </summary>
    private void OnPrintPickerChanged(object? sender, System.EventArgs args) =>
        Owner?.OnPrintInspectorChanged();

    private void OnPrintSliderChanged(object sender, RangeBaseValueChangedEventArgs args) =>
        Owner?.OnPrintSliderChanged(sender, args);

    private void OnPrintNumberChanged(NumberBox sender, NumberBoxValueChangedEventArgs args) =>
        Owner?.OnPrintNumberChanged(sender, args);

    private void OnPrintToggled(object sender, RoutedEventArgs args) =>
        Owner?.OnPrintToggled(sender, args);

    private void OnCustomAddClicked(object sender, RoutedEventArgs args) =>
        Owner?.OnCustomAddClicked(sender, args);

    private void OnLayoutTemplateNameChanged(object sender, TextChangedEventArgs args) =>
        Owner?.OnLayoutTemplateNameChanged(sender, args);

    private void OnLayoutTemplateSaveClicked(object sender, RoutedEventArgs args) =>
        Owner?.OnLayoutTemplateSaveClicked(sender, args);

    private void OnLayoutTemplateApplyClicked(object sender, RoutedEventArgs args) =>
        Owner?.OnLayoutTemplateApplyClicked(sender, args);

    private void OnLayoutTemplateDeleteClicked(object sender, RoutedEventArgs args) =>
        Owner?.OnLayoutTemplateDeleteClicked(sender, args);
}
