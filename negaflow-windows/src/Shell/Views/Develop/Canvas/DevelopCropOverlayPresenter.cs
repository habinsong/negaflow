using Microsoft.UI.Xaml;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.Views.Develop.Canvas;

/// <summary>
/// 계산된 크롭 오버레이 기하를 캔버스 요소에 놓습니다. 히트테스트는
/// <see cref="CropInteraction"/> 이 맡습니다.
/// </summary>
internal sealed class DevelopCropOverlayPresenter
{
    private readonly DevelopPreviewCanvas view;

    internal DevelopCropOverlayPresenter(DevelopPreviewCanvas view) => this.view = view;

    internal void Hide() => view.CropOverlay.Visibility = Visibility.Collapsed;

    internal void Render(CropWorkspaceState crop, PreviewFrame frame)
    {
        if (crop.Session is not { } session || crop.AwaitingPreview)
        {
            Hide();
            return;
        }

        // 기하는 CropInteraction 이 계산합니다. 뷰는 계산된 자리에 요소를 놓기만 합니다.
        CropOverlayLayout layout = CropInteraction.Layout(
            frame,
            session.Selection,
            view.CropActionBar.ActualHeight);
        view.CropOverlay.Visibility = Visibility.Visible;
        Place(view.CropDimTop, layout.DimTop);
        Place(view.CropDimBottom, layout.DimBottom);
        Place(view.CropDimLeft, layout.DimLeft);
        Place(view.CropDimRight, layout.DimRight);
        Place(view.CropSelection, layout.Selection);
        Place(view.CropThirdVerticalFirst, layout.ThirdVerticalFirst);
        Place(view.CropThirdVerticalSecond, layout.ThirdVerticalSecond);
        Place(view.CropThirdHorizontalFirst, layout.ThirdHorizontalFirst);
        Place(view.CropThirdHorizontalSecond, layout.ThirdHorizontalSecond);
        Place(view.CropHandleTopLeft, layout.HandleTopLeft);
        Place(view.CropHandleTop, layout.HandleTop);
        Place(view.CropHandleTopRight, layout.HandleTopRight);
        Place(view.CropHandleRight, layout.HandleRight);
        Place(view.CropHandleBottomRight, layout.HandleBottomRight);
        Place(view.CropHandleBottom, layout.HandleBottom);
        Place(view.CropHandleBottomLeft, layout.HandleBottomLeft);
        Place(view.CropHandleLeft, layout.HandleLeft);
        Microsoft.UI.Xaml.Controls.Canvas.SetLeft(view.CropActionBar, layout.ActionBarLeft);
        Microsoft.UI.Xaml.Controls.Canvas.SetTop(view.CropActionBar, layout.ActionBarTop);
    }

    internal static void Place(FrameworkElement element, double left, double top, double width, double height)
    {
        element.Width = width;
        element.Height = height;
        Microsoft.UI.Xaml.Controls.Canvas.SetLeft(element, left);
        Microsoft.UI.Xaml.Controls.Canvas.SetTop(element, top);
    }

    internal static void Place(FrameworkElement element, CropOverlayPlacement placement) =>
        Place(element, placement.Left, placement.Top, placement.Width, placement.Height);

    internal static void Place(
        Microsoft.UI.Xaml.Shapes.Line line,
        (double X1, double Y1, double X2, double Y2) segment)
    {
        line.X1 = segment.X1;
        line.Y1 = segment.Y1;
        line.X2 = segment.X2;
        line.Y2 = segment.Y2;
    }
}
