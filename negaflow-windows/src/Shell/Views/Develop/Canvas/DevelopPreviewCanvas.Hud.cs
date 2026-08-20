using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.Views.Develop.Canvas;

/// <summary>
/// 캔버스 위에 떠 있는 HUD(확대·비교)의 자리와 끌기입니다.
/// </summary>
/// <remarks>
/// macOS 는 HUD 를 사진 위에 얹고 사용자가 끌어 옮길 수 있게 둡니다. 자리 계산과 끌기는
/// 그림을 그리는 것과 다른 이유로 바뀌므로 파일을 나눕니다.
/// </remarks>
public sealed partial class DevelopPreviewCanvas
{
    private void ApplyHudLayout()
    {
        if (CanvasHost.ActualWidth <= 0 || CanvasHost.ActualHeight <= 0)
        {
            return;
        }

        if (CompareHud.ActualWidth > 0 && CompareHud.ActualHeight > 0)
        {
            hudInteraction.SetMeasuredSize(
                CanvasHudKind.Compare,
                CompareHud.ActualWidth,
                CompareHud.ActualHeight);
        }

        if (ZoomHud.ActualWidth > 0 && ZoomHud.ActualHeight > 0)
        {
            hudInteraction.SetMeasuredSize(
                CanvasHudKind.Zoom,
                ZoomHud.ActualWidth,
                ZoomHud.ActualHeight);
        }

        CanvasHudOrigins origins = hudInteraction.Resolve(CanvasHost.ActualWidth, CanvasHost.ActualHeight);
        CompareHud.Margin = new Thickness(origins.CompareX, origins.CompareY, 0, 0);
        ZoomHud.Margin = new Thickness(origins.ZoomX, origins.ZoomY, 0, 0);
    }

    private void OnCompareHudSizeChanged(object sender, SizeChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        ApplyHudLayout();
    }

    private void OnZoomHudSizeChanged(object sender, SizeChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        ApplyHudLayout();
    }

    private void OnCompareHudPointerPressed(object sender, PointerRoutedEventArgs args) =>
        BeginHudPress(CanvasHudKind.Compare, args);

    private void OnZoomHudPointerPressed(object sender, PointerRoutedEventArgs args) =>
        BeginHudPress(CanvasHudKind.Zoom, args);

    private void BeginHudPress(CanvasHudKind kind, PointerRoutedEventArgs args)
    {
        if (IsHudInteractiveSource(args.OriginalSource))
        {
            return;
        }

        Windows.Foundation.Point point = args.GetCurrentPoint(CanvasHost).Position;
        CanvasHudOrigins origins = hudInteraction.Resolve(CanvasHost.ActualWidth, CanvasHost.ActualHeight);
        hudPressKind = kind;
        hudPressX = point.X;
        hudPressY = point.Y;
        hudPressOriginX = kind == CanvasHudKind.Compare ? origins.CompareX : origins.ZoomX;
        hudPressOriginY = kind == CanvasHudKind.Compare ? origins.CompareY : origins.ZoomY;
        hudDragging = false;
    }

    private void OnHudPointerMoved(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        if (hudPressKind is not { } kind)
        {
            return;
        }

        Windows.Foundation.Point point = args.GetCurrentPoint(CanvasHost).Position;
        double translationX = point.X - hudPressX;
        double translationY = point.Y - hudPressY;
        if (!hudDragging)
        {
            if ((translationX * translationX) + (translationY * translationY) <
                CanvasHudInteractionState.MinimumDragDistance * CanvasHudInteractionState.MinimumDragDistance)
            {
                return;
            }

            hudDragging = true;
            CaptureHost(args.Pointer);
        }

        hudInteraction.BeginOrUpdateDrag(
            kind,
            translationX,
            translationY,
            hudPressOriginX,
            hudPressOriginY,
            CanvasHost.ActualWidth,
            CanvasHost.ActualHeight);
        ApplyHudLayout();
        args.Handled = true;
    }

    private void OnHudPointerReleased(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        EndHudDrag(args);
    }

    private void OnHudPointerCanceled(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        EndHudDrag(args);
    }

    private void EndHudDrag(PointerRoutedEventArgs args)
    {
        if (hudPressKind is not { } kind)
        {
            return;
        }

        if (hudDragging)
        {
            hudInteraction.EndDrag(kind);
            ReleaseHost(args.Pointer);
            args.Handled = true;
        }

        hudPressKind = null;
        hudDragging = false;
    }

    private static bool IsHudInteractiveSource(object source)
    {
        DependencyObject? current = source as DependencyObject;
        while (current is not null)
        {
            if (current is Button or TextBox)
            {
                return true;
            }

            current = VisualTreeHelper.GetParent(current);
        }

        return false;
    }
}
