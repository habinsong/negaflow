using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Negaflow.Shell.Views.Print.Settings;

/// <summary>
/// 인화 검사기의 출력 탭 카드입니다. 출력 방식·C-print·인화 프루프·내보내기가 여기 모입니다.
/// </summary>
/// <remarks>
/// XAML 은 <c>PrintWorkspaceView.xaml</c> 에서 그대로 옮겨 왔고, 이벤트는 옮기기 전과 같은
/// <see cref="PrintWorkspaceView"/> 메서드로 그대로 넘깁니다.
/// </remarks>
public sealed partial class PrintOutputTab : UserControl
{
    internal PrintWorkspaceView? Owner;

    public PrintOutputTab() => InitializeComponent();

    private void OnCprintTextChanged(object sender, TextChangedEventArgs args) =>
        Owner?.OnCprintTextChanged(sender, args);

    private void OnPrintProofChooseClicked(object sender, RoutedEventArgs args) =>
        Owner?.OnPrintProofChooseClicked(sender, args);

    private void OnPrintProofClearClicked(object sender, RoutedEventArgs args) =>
        Owner?.OnPrintProofClearClicked(sender, args);

}
