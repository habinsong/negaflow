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

    /// <summary>
    /// HUD 의 포인터를 잇습니다. <b>이미 처리된 이벤트도</b> 받습니다.
    /// </summary>
    /// <remarks>
    /// macOS 는 <c>highPriorityGesture(DragGesture(minimumDistance: 4))</c> 를 HUD 통째에
    /// 겁니다 — 캡슐의 <b>어디를 잡아도</b> 끌리고, 4 미만으로 움직이면 안쪽 단추가 눌립니다.
    ///
    /// WinUI 에서는 단추가 눌림을 먼저 처리해 버리므로, 보통 방식으로 걸면 단추 위에서
    /// 눌림이 <b>오지 않습니다</b>. 실측: 단추 위에서 끌면 hud.press 0 · hud.drag 0 으로
    /// HUD 가 꿈쩍도 하지 않았고, 3px 테두리에서만 끌렸는데 그때는 눌림이 캔버스까지
    /// 올라가 <b>사진도 같이 끌렸습니다</b>(pan.move 1).
    /// </remarks>
    private void HookHud(FrameworkElement hud, CanvasHudKind kind)
    {
        hud.AddHandler(
            UIElement.PointerPressedEvent,
            new PointerEventHandler((_, args) => BeginHudPress(hud, kind, args)),
            handledEventsToo: true);
        hud.AddHandler(
            UIElement.PointerMovedEvent,
            new PointerEventHandler(OnHudPointerMoved),
            handledEventsToo: true);
        hud.AddHandler(
            UIElement.PointerReleasedEvent,
            new PointerEventHandler(OnHudPointerReleased),
            handledEventsToo: true);
        hud.AddHandler(
            UIElement.PointerCanceledEvent,
            new PointerEventHandler(OnHudPointerCanceled),
            handledEventsToo: true);
        hud.AddHandler(
            UIElement.PointerCaptureLostEvent,
            new PointerEventHandler(OnHudPointerCanceled),
            handledEventsToo: true);
    }

    private void BeginHudPress(FrameworkElement hud, CanvasHudKind kind, PointerRoutedEventArgs args)
    {
        Windows.Foundation.Point point = args.GetCurrentPoint(CanvasHost).Position;
        CanvasHudOrigins origins = hudInteraction.Resolve(CanvasHost.ActualWidth, CanvasHost.ActualHeight);
        hudPressKind = kind;
        hudPressX = point.X;
        hudPressY = point.Y;
        hudPressOriginX = kind == CanvasHudKind.Compare ? origins.CompareX : origins.ZoomX;
        hudPressOriginY = kind == CanvasHudKind.Compare ? origins.CompareY : origins.ZoomY;
        hudDragging = false;
        hudPressElement = hud;
        // 눌림을 여기서 끝냅니다. 그러지 않으면 캔버스까지 올라가 사진 끌기가 함께
        // 시작됩니다 — 실측으로 확인한 충돌입니다.
        args.Handled = true;
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
            // 포인터를 HUD 가 붙듭니다. 안쪽 단추는 캡처를 잃어 <b>클릭이 나지 않고</b>,
            // 뒤따르는 움직임은 계속 HUD 로 옵니다.
            _ = hudPressElement?.CapturePointer(args.Pointer);
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
            hudPressElement?.ReleasePointerCapture(args.Pointer);
            args.Handled = true;
        }

        hudPressKind = null;
        hudPressElement = null;
        hudDragging = false;
    }

    /// <summary>지금 눌린 HUD 입니다. 끌기가 시작되면 이것이 포인터를 붙듭니다.</summary>
    private FrameworkElement? hudPressElement;
}
