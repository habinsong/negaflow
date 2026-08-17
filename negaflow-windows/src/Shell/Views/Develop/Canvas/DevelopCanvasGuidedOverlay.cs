using Microsoft.UI.Xaml;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.Views.Develop.Canvas;

/// <summary>
/// 가이드 검출의 드래그 사각형입니다. 검출 자체는 뷰가 맡습니다.
/// </summary>
internal sealed class DevelopCanvasGuidedOverlay
{
    private readonly DevelopPreviewCanvas view;

    internal DevelopCanvasGuidedOverlay(DevelopPreviewCanvas view) => this.view = view;

    internal void Hide() => view.GuidedDefectOverlay.Visibility = Visibility.Collapsed;

    internal void Render(CropDisplayPoint start, CropDisplayPoint current, PreviewFrame frame)
    {
        double x = Math.Min(start.X, current.X);
        double y = Math.Min(start.Y, current.Y);
        double selectionWidth = Math.Abs(current.X - start.X);
        double selectionHeight = Math.Abs(current.Y - start.Y);
        DevelopCropOverlayPresenter.Place(
            view.GuidedDefectSelection,
            frame.Left + x * frame.Width,
            frame.Top + y * frame.Height,
            selectionWidth * frame.Width,
            selectionHeight * frame.Height);
        view.GuidedDefectOverlay.Visibility = Visibility.Visible;
    }
}
