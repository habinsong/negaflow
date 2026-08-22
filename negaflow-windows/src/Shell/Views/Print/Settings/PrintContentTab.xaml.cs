using Microsoft.UI.Xaml.Controls;

namespace Negaflow.Shell.Views.Print.Settings;

/// <summary>
/// 인화 검사기의 콘텐츠 탭입니다. macOS <c>PrintPackageInspectorControls(scope: .content)</c>
/// 자리이며, 여러 장을 한 판에 놓는 모드에서만 나옵니다.
/// </summary>
public sealed partial class PrintContentTab : UserControl
{
    internal PrintWorkspaceView? Owner { get; set; }

    public PrintContentTab() => InitializeComponent();

    private void OnContentPickerChanged(object? sender, System.EventArgs args) =>
        Owner?.OnPrintInspectorChanged();

    private void OnAddCaptionClicked(object sender, Microsoft.UI.Xaml.RoutedEventArgs args) =>
        Owner?.OnAddCustomCaptionClicked();
}
