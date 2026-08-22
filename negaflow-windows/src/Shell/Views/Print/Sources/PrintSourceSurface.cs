using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Shell.Views;

namespace Negaflow.Shell.Views.Print.Sources;

/// <summary>인화 소스 트리가 쓰는 화면 자리입니다.</summary>
internal sealed class PrintSourceSurface
{
    public required Negaflow.Shell.Views.Library.Sources.LibraryFolderTreeView FilesTree { get; init; }
    public required TextBlock LeftHeader { get; init; }
    public required TextBlock RightHeader { get; init; }
    public required UIElement NoFrameLeftPanel { get; init; }
    public required FilmstripView Filmstrip { get; init; }

    /// <summary>
    /// 좌측 레일이 어느 탭인지에 따라 트리·안내를 보일지 정하는 자리입니다. 컨트롤러가
    /// 직접 Visibility 를 만지면 내보내기 탭을 열어 둔 채 새로고침이 오면 트리가 다시
    /// 튀어나옵니다 — 그래서 판단은 뷰가 합니다.
    /// </summary>
    public required Action<bool> ApplySourcePane { get; init; }
}
