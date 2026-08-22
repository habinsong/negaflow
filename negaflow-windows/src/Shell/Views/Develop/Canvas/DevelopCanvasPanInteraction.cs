using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Negaflow.Shell.Develop;
using Microsoft.UI.Xaml.Input;
using Windows.Foundation;

namespace Negaflow.Shell.Views.Develop.Canvas;

/// <summary>
/// 캔버스를 눌러 끌어서 사진을 옮깁니다. macOS <c>CanvasView</c> 의 <c>DragGesture</c> 가
/// <c>viewport.updatePan</c> 을 부르는 자리와 같습니다.
/// </summary>
/// <remarks>
/// <para>
/// 옮길 수 있는 것은 사진이 캔버스보다 클 때뿐입니다 — 다 보이는 사진을 끌면 macOS 도
/// 움직이지 않습니다. 그 판단은 <see cref="CanvasViewportState.UpdatePan"/> 안의
/// 클램프가 이미 합니다.
/// </para>
/// <para>
/// 다른 도구(크롭 · 브러시 · 스포이드)가 먼저 집으면 여기까지 오지 않습니다. 끌기는
/// 맨 마지막 차례입니다.
/// </para>
/// </remarks>
internal sealed class DevelopCanvasPanInteraction
{
    /// <summary>이만큼 움직여야 끌기로 봅니다. 손이 조금 떨려도 사진이 흔들리지 않습니다.</summary>
    private const double DragThreshold = 2.0;

    private readonly FrameworkElement host;
    private readonly Func<CanvasViewportState?> viewport;
    private readonly Func<(double Width, double Height)?> imageSize;
    private readonly Action apply;

    /// <summary>
    /// 끄는 동안 커서를 바꿉니다. <c>ProtectedCursor</c> 는 그 컨트롤 안에서만 쓸 수 있어
    /// 캔버스가 설정자를 넘겨 줍니다.
    /// </summary>
    private readonly Action<InputSystemCursorShape?> setCursor;

    private Point origin;
    private bool armed;
    private bool panning;

    internal DevelopCanvasPanInteraction(
        FrameworkElement host,
        Func<CanvasViewportState?> viewport,
        Func<(double Width, double Height)?> imageSize,
        Action apply,
        Action<InputSystemCursorShape?> setCursor)
    {
        this.host = host;
        this.viewport = viewport;
        this.imageSize = imageSize;
        this.apply = apply;
        this.setCursor = setCursor;
    }

    internal bool IsPanning => panning;

    internal bool TryBegin(PointerRoutedEventArgs args)
    {
        if (viewport() is null || imageSize() is null)
        {
            return false;
        }
        PointerPoint point = args.GetCurrentPoint(host);
        // 왼쪽 단추만입니다. 오른쪽은 배경색 메뉴 자리입니다.
        if (point.Properties.IsRightButtonPressed || point.Properties.IsMiddleButtonPressed)
        {
            return false;
        }
        origin = point.Position;
        armed = true;
        panning = false;
        return false;
    }

    internal bool TryContinue(PointerRoutedEventArgs args)
    {
        if (!armed || viewport() is not { } state || imageSize() is not { } size)
        {
            return false;
        }
        Point position = args.GetCurrentPoint(host).Position;
        double dx = position.X - origin.X;
        double dy = position.Y - origin.Y;
        if (!panning)
        {
            if (Math.Abs(dx) < DragThreshold && Math.Abs(dy) < DragThreshold)
            {
                return false;
            }
            panning = true;
            _ = host.CapturePointer(args.Pointer);
            setCursor(InputSystemCursorShape.SizeAll);
        }

        state.UpdatePan(dx, dy, size.Width, size.Height, host.ActualWidth, host.ActualHeight);
        apply();
        return true;
    }

    internal bool End(PointerRoutedEventArgs args)
    {
        if (!armed)
        {
            return false;
        }
        armed = false;
        if (!panning)
        {
            return false;
        }
        panning = false;
        host.ReleasePointerCapture(args.Pointer);
        viewport()?.EndPan();
        setCursor(null);
        return true;
    }
}
