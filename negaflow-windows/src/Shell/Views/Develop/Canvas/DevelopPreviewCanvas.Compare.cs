using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.Views.Develop.Canvas;

/// <summary>
/// 비교 보기의 배치와 가운데 손잡이 끌기입니다.
/// </summary>
/// <remarks>
/// macOS <c>beforeAfterCompare</c> — 좌우/상하로 가른 두 그림과 그 사이를 끄는 손잡이입니다.
/// </remarks>
public sealed partial class DevelopPreviewCanvas
{
    private void ApplyCompareLayout(PreviewFrame frame)
    {
        CanvasCompareOrientation? split = compare is null
            ? null
            : CanvasCompareHudPolicy.SplitOrientation(compare.ActiveMode);
        bool showSplit = split is not null && compareBeforeBitmap is not null;
        CompareBeforeImage.Visibility = showSplit ? Visibility.Visible : Visibility.Collapsed;
        CompareDividerLayer.Visibility = showSplit ? Visibility.Visible : Visibility.Collapsed;
        CompareLabels.Visibility = showSplit ? Visibility.Visible : Visibility.Collapsed;
        if (showSplit && split is { } labelOrientation)
        {
            CompareLabels.Place(frame, labelOrientation);
            CompareLabels.Refresh();
        }
        if (!showSplit || compare is null || split is not { } orientation)
        {
            CompareBeforeImage.Clip = null;
            return;
        }

        PositionSurface(CompareBeforeImage, frame);
        double fraction = compare.Divider.Fraction(orientation);
        (double clipX, double clipY, double clipW, double clipH) = CanvasCompareDividerState.BeforeClip(
            0,
            0,
            frame.Width,
            frame.Height,
            orientation,
            fraction);
        CompareBeforeImage.Clip = new RectangleGeometry
        {
            Rect = new Windows.Foundation.Rect(clipX, clipY, clipW, clipH),
        };

        double line = compare.Divider.LinePosition(
            orientation == CanvasCompareOrientation.Vertical ? frame.Left : frame.Top,
            orientation == CanvasCompareOrientation.Vertical ? frame.Width : frame.Height,
            orientation);
        if (orientation == CanvasCompareOrientation.Vertical)
        {
            CompareDividerLine.Width = 1;
            CompareDividerLine.Height = frame.Height;
            Microsoft.UI.Xaml.Controls.Canvas.SetLeft(CompareDividerLine, line - 0.5);
            Microsoft.UI.Xaml.Controls.Canvas.SetTop(CompareDividerLine, frame.Top);
            CompareDividerHandle.Width = CanvasCompareDividerState.HandleShort;
            CompareDividerHandle.Height = CanvasCompareDividerState.HandleLong;
            Microsoft.UI.Xaml.Controls.Canvas.SetLeft(CompareDividerHandle, line - (CanvasCompareDividerState.HandleShort / 2));
            Microsoft.UI.Xaml.Controls.Canvas.SetTop(CompareDividerHandle, frame.Top + (frame.Height / 2) - (CanvasCompareDividerState.HandleLong / 2));
        }
        else
        {
            CompareDividerLine.Width = frame.Width;
            CompareDividerLine.Height = 1;
            Microsoft.UI.Xaml.Controls.Canvas.SetLeft(CompareDividerLine, frame.Left);
            Microsoft.UI.Xaml.Controls.Canvas.SetTop(CompareDividerLine, line - 0.5);
            CompareDividerHandle.Width = CanvasCompareDividerState.HandleLong;
            CompareDividerHandle.Height = CanvasCompareDividerState.HandleShort;
            Microsoft.UI.Xaml.Controls.Canvas.SetLeft(CompareDividerHandle, frame.Left + (frame.Width / 2) - (CanvasCompareDividerState.HandleLong / 2));
            Microsoft.UI.Xaml.Controls.Canvas.SetTop(CompareDividerHandle, line - (CanvasCompareDividerState.HandleShort / 2));
        }
    }

    private static void PositionSurface(FrameworkElement element, PreviewFrame frame)
    {
        element.HorizontalAlignment = HorizontalAlignment.Left;
        element.VerticalAlignment = VerticalAlignment.Top;
        element.Margin = new Thickness(frame.Left, frame.Top, 0, 0);
        element.Width = frame.Width;
        element.Height = frame.Height;
    }

    private bool TryBeginCompareDivider(PointerRoutedEventArgs args)
    {
        if (compare is null ||
            CanvasCompareHudPolicy.SplitOrientation(compare.ActiveMode) is not { } orientation ||
            compareBeforeBitmap is null ||
            !TryGetPreviewFrame(out PreviewFrame frame))
        {
            return false;
        }

        Windows.Foundation.Point point = args.GetCurrentPoint(CanvasHost).Position;
        if (!compare.Divider.HitTest(
                point.X,
                point.Y,
                frame.Left,
                frame.Top,
                frame.Width,
                frame.Height,
                orientation))
        {
            return false;
        }

        draggingCompareDivider = true;
        double pointer = orientation == CanvasCompareOrientation.Vertical ? point.X : point.Y;
        double origin = orientation == CanvasCompareOrientation.Vertical ? frame.Left : frame.Top;
        double length = orientation == CanvasCompareOrientation.Vertical ? frame.Width : frame.Height;
        compare.Divider.BeginOrUpdateDrag(pointer, 0, origin, length, orientation);
        CaptureHost(args.Pointer);
        args.Handled = true;
        ApplyImageFrame();
        return true;
    }

    private bool TryContinueCompareDivider(PointerRoutedEventArgs args)
    {
        if (!draggingCompareDivider ||
            compare is null ||
            CanvasCompareHudPolicy.SplitOrientation(compare.ActiveMode) is not { } orientation ||
            !TryGetPreviewFrame(out PreviewFrame frame))
        {
            return false;
        }

        Windows.Foundation.Point point = args.GetCurrentPoint(CanvasHost).Position;
        double pointer = orientation == CanvasCompareOrientation.Vertical ? point.X : point.Y;
        double origin = orientation == CanvasCompareOrientation.Vertical ? frame.Left : frame.Top;
        double length = orientation == CanvasCompareOrientation.Vertical ? frame.Width : frame.Height;
        compare.Divider.BeginOrUpdateDrag(pointer, 1, origin, length, orientation);
        args.Handled = true;
        ApplyImageFrame();
        return true;
    }

    private bool EndCompareDivider(PointerRoutedEventArgs args)
    {
        if (!draggingCompareDivider)
        {
            return false;
        }

        draggingCompareDivider = false;
        compare?.Divider.EndDrag();
        ReleaseHost(args.Pointer);
        args.Handled = true;
        return true;
    }
}
