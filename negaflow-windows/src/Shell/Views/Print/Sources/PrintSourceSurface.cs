using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Shell.Views;

namespace Negaflow.Shell.Views.Print.Sources;

/// <summary>인화 소스 트리가 쓰는 화면 자리입니다.</summary>
internal sealed class PrintSourceSurface
{
    public required TreeView FilesTree { get; init; }
    public required TextBlock LeftHeader { get; init; }
    public required TextBlock RightHeader { get; init; }
    public required UIElement NoFrameLeftPanel { get; init; }
    public required FilmstripView Filmstrip { get; init; }
}
