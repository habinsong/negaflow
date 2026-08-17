using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Negaflow.Shell.Views.Print.Preview;

/// <summary>인화 미리보기 캔버스가 쓰는 자리입니다.</summary>
internal sealed class PrintPreviewSurface
{
    public required FrameworkElement CanvasHost { get; init; }
    public required Border PageBorder { get; init; }
    public required Canvas PageCanvas { get; init; }
    public required Canvas RulerCanvas { get; init; }
    public required UIElement NoFramePanel { get; init; }
    public required TextBlock PageCountText { get; init; }
    public required TextBlock PageSizeSummaryText { get; init; }
    public required Button PrintExportButton { get; init; }
}
