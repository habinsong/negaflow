using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Print;

namespace Negaflow.Shell.Views;

/// <summary>
/// 인화 캔버스의 확대·이동과 줌 캡슐입니다. macOS <c>PrintCanvasView</c> 의 <c>viewport</c> ·
/// <c>CanvasToolHUD</c> 자리이며, 판을 그리는 것과 다른 이유로 바뀌므로 파일을 나눕니다.
/// </summary>
public sealed partial class PrintWorkspaceView
{
    /// <summary>macOS <c>@State private var viewport = CanvasViewportState()</c>.</summary>
    private readonly CanvasViewportState printViewport = new();

    /// <summary>줌 캡슐의 자리입니다. 현상뷰와 같은 계산을 씁니다.</summary>
    private readonly CanvasHudInteractionState printHud = new();

    private bool printPanning;
    private bool printHudPressed;
    private bool printHudDragging;
    private double printHudPressX;
    private double printHudPressY;
    private double printHudOriginX;
    private double printHudOriginY;
    private double printPanOriginX;
    private double printPanOriginY;

    /// <summary>
    /// 캔버스의 확대·이동과 줌 캡슐을 잇습니다.
    /// </summary>
    /// <remarks>
    /// 캡슐 끌기는 <b>이미 처리된 이벤트도</b> 받습니다 — 안쪽 단추가 눌림을 먼저 먹으면
    /// 보통 방식으로는 캡슐이 꿈쩍도 하지 않습니다(현상뷰에서 실측한 것과 같은 문제).
    /// 눌림을 여기서 끝내므로 판 끌기가 함께 시작되지도 않습니다.
    /// </remarks>
    private void HookPrintViewport()
    {
        PrintZoomHud.Bind(
            printViewport,
            () => (CanvasHost.ActualWidth, CanvasHost.ActualHeight),
            () => (CanvasHost.ActualWidth, CanvasHost.ActualHeight),
            ApplyPrintViewport);
        PrintZoomHud.AddHandler(
            UIElement.PointerPressedEvent,
            new PointerEventHandler(OnPrintHudPressed),
            handledEventsToo: true);
        PrintZoomHud.AddHandler(
            UIElement.PointerMovedEvent,
            new PointerEventHandler(OnPrintHudMoved),
            handledEventsToo: true);
        PrintZoomHud.AddHandler(
            UIElement.PointerReleasedEvent,
            new PointerEventHandler(OnPrintHudReleased),
            handledEventsToo: true);
        PrintZoomHud.AddHandler(
            UIElement.PointerCanceledEvent,
            new PointerEventHandler(OnPrintHudReleased),
            handledEventsToo: true);
        PrintZoomHud.AddHandler(
            UIElement.PointerCaptureLostEvent,
            new PointerEventHandler(OnPrintHudReleased),
            handledEventsToo: true);

        CanvasHost.PointerPressed += OnPrintCanvasPressed;
        CanvasHost.PointerMoved += OnPrintCanvasMoved;
        CanvasHost.PointerReleased += OnPrintCanvasReleased;
        CanvasHost.PointerCanceled += OnPrintCanvasReleased;
        CanvasHost.PointerCaptureLost += OnPrintCanvasReleased;
        CanvasHost.PointerWheelChanged += OnPrintCanvasWheel;
    }

    /// <summary>
    /// macOS <c>usesVerticalPageStack</c> — 여러 장을 세로로 늘어놓는 동안에는 끌기가
    /// 스크롤과 싸우므로 캔버스 끌기를 끕니다.
    /// </summary>
    private bool PrintPanIsAllowed() =>
        workspaceState is { } state &&
        !PrintPreferences.UsesVerticalPageStack(
            state.Current.Print.LayoutMode,
            PrintSources.Count);

    private void ApplyPrintViewport()
    {
        TransformGroup transform = new();
        transform.Children.Add(new ScaleTransform
        {
            ScaleX = printViewport.Scale,
            ScaleY = printViewport.Scale,
        });
        transform.Children.Add(new TranslateTransform
        {
            X = printViewport.OffsetX,
            Y = printViewport.OffsetY,
        });
        PageBorder.RenderTransformOrigin = new Windows.Foundation.Point(0.5, 0.5);
        PageBorder.RenderTransform = transform;
        PrintZoomHud.RefreshZoomText();
    }

    private void ApplyPrintHudLayout()
    {
        if (CanvasHost.ActualWidth <= 0 || CanvasHost.ActualHeight <= 0)
        {
            return;
        }
        if (PrintZoomHud.ActualWidth > 0 && PrintZoomHud.ActualHeight > 0)
        {
            printHud.SetMeasuredSize(
                CanvasHudKind.Zoom,
                PrintZoomHud.ActualWidth,
                PrintZoomHud.ActualHeight);
        }
        CanvasHudOrigins origins = printHud.ResolvePrintZoom(
            CanvasHost.ActualWidth,
            CanvasHost.ActualHeight);
        PrintZoomHud.Margin = new Thickness(origins.ZoomX, origins.ZoomY, 0, 0);
    }

    private void OnPrintZoomHudSizeChanged(object sender, SizeChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        ApplyPrintHudLayout();
    }

    private void OnPrintHudPressed(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        Windows.Foundation.Point point = args.GetCurrentPoint(CanvasHost).Position;
        CanvasHudOrigins origins = printHud.ResolvePrintZoom(
            CanvasHost.ActualWidth,
            CanvasHost.ActualHeight);
        printHudPressed = true;
        printHudDragging = false;
        printHudPressX = point.X;
        printHudPressY = point.Y;
        printHudOriginX = origins.ZoomX;
        printHudOriginY = origins.ZoomY;
        // 캔버스가 판 끌기를 함께 시작하지 않게 여기서 끝냅니다.
        args.Handled = true;
    }

    private void OnPrintHudMoved(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        if (!printHudPressed)
        {
            return;
        }
        Windows.Foundation.Point point = args.GetCurrentPoint(CanvasHost).Position;
        double dx = point.X - printHudPressX;
        double dy = point.Y - printHudPressY;
        if (!printHudDragging)
        {
            if ((dx * dx) + (dy * dy) <
                CanvasHudInteractionState.MinimumDragDistance *
                CanvasHudInteractionState.MinimumDragDistance)
            {
                return;
            }
            printHudDragging = true;
            _ = PrintZoomHud.CapturePointer(args.Pointer);
        }
        printHud.UpdatePrintZoomDrag(
            dx,
            dy,
            printHudOriginX,
            printHudOriginY,
            CanvasHost.ActualWidth,
            CanvasHost.ActualHeight);
        ApplyPrintHudLayout();
        args.Handled = true;
    }

    private void OnPrintHudReleased(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        if (!printHudPressed)
        {
            return;
        }
        if (printHudDragging)
        {
            printHud.EndDrag(CanvasHudKind.Zoom);
            PrintZoomHud.ReleasePointerCapture(args.Pointer);
            args.Handled = true;
        }
        printHudPressed = false;
        printHudDragging = false;
    }

    private void OnPrintCanvasPressed(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        if (!PrintPanIsAllowed())
        {
            return;
        }
        Microsoft.UI.Input.PointerPoint point = args.GetCurrentPoint(CanvasHost);
        // 오른쪽은 배경색 메뉴 자리입니다.
        if (point.Properties.IsRightButtonPressed || point.Properties.IsMiddleButtonPressed)
        {
            return;
        }
        printPanning = true;
        printPanOriginX = point.Position.X;
        printPanOriginY = point.Position.Y;
        _ = CanvasHost.CapturePointer(args.Pointer);
    }

    private void OnPrintCanvasMoved(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        if (!printPanning)
        {
            return;
        }
        Windows.Foundation.Point point = args.GetCurrentPoint(CanvasHost).Position;
        printViewport.UpdatePan(
            point.X - printPanOriginX,
            point.Y - printPanOriginY,
            CanvasHost.ActualWidth,
            CanvasHost.ActualHeight,
            CanvasHost.ActualWidth,
            CanvasHost.ActualHeight);
        ApplyPrintViewport();
        args.Handled = true;
    }

    private void OnPrintCanvasReleased(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        if (!printPanning)
        {
            return;
        }
        printPanning = false;
        printViewport.EndPan();
        CanvasHost.ReleasePointerCapture(args.Pointer);
    }

    /// <summary>macOS <c>MagnifyGesture</c> 자리입니다 — 휠은 Windows 의 같은 손짓입니다.</summary>
    private void OnPrintCanvasWheel(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        int delta = args.GetCurrentPoint(CanvasHost).Properties.MouseWheelDelta;
        if (delta == 0)
        {
            return;
        }
        printViewport.ZoomBy(
            delta > 0 ? CanvasToolHudPolicy.ZoomStep : 1 / CanvasToolHudPolicy.ZoomStep,
            CanvasHost.ActualWidth,
            CanvasHost.ActualHeight,
            CanvasHost.ActualWidth,
            CanvasHost.ActualHeight);
        ApplyPrintViewport();
        args.Handled = true;
    }
}
