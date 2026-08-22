using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Negaflow.Shell.Views.Library.Sources;

/// <summary>
/// 라이브러리 왼쪽 소스 패널입니다. 소스 레일·가져오기 절·스캔 카드·파일 트리·컬렉션이
/// 여기 모입니다.
/// </summary>
/// <remarks>
/// XAML 은 <c>LibraryWorkspaceView.xaml</c> 에서 그대로 옮겨 왔고, 이벤트는 옮기기 전과 같은
/// <see cref="LibraryWorkspaceView"/> 메서드로 그대로 넘깁니다 — 레일 로직은
/// <c>Library/Host/LibrarySourceRail.cs</c> 에 그대로 있습니다.
/// </remarks>
public sealed partial class LibrarySourcePanel : UserControl
{
    internal LibraryWorkspaceView? Owner;

    public LibrarySourcePanel() => InitializeComponent();

    private void OnSourceRailClicked(object sender, RoutedEventArgs args) =>
        Owner?.OnSourceRailClicked(sender, args);

    private void OnImportClicked(object sender, RoutedEventArgs args) =>
        Owner?.OnImportClicked(sender, args);

    private void OnImportFoldersClicked(object sender, RoutedEventArgs args) =>
        Owner?.OnImportFoldersClicked(sender, args);

    private void OnImportScannerClicked(object sender, RoutedEventArgs args) =>
        Owner?.OnImportScannerClicked(sender, args);
}
