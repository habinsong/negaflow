using Microsoft.UI.Xaml.Input;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.Views.Develop.Canvas;

/// <summary>
/// 캔버스로 들어온 포인터와 키를 도구들에 나눠 줍니다.
/// </summary>
/// <remarks>
/// 순서가 곧 우선순위입니다 — 바깥에서 꽂아 준 도구(부분 보정·베이스 스포이드·GrainMend)가
/// 먼저 보고, 아무도 집지 않으면 비교 손잡이와 크롭이 받습니다.
/// </remarks>
public sealed partial class DevelopPreviewCanvas
{
    private void OnCanvasPointerPressed(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        if (TryBeginCompareDivider(args))
        {
            return;
        }
        if (TryHandlePointerPressed?.Invoke(args) == true)
        {
            return;
        }
        // 크롭 상태는 늘 있습니다 - 자르기 중인지는 `TryBeginDrag` 가 스스로 봅니다.
        // 여기서 `crop is not null` 만 보고 돌아서면 자르기를 켜지 않았는데도 끌기가
        // 통째로 막힙니다.
        if (crop is not null && cropInteraction.TryBeginDrag(args, crop))
        {
            return;
        }
        // 아무 도구도 집지 않았으면 끌기로 사진을 옮깁니다 - 맨 마지막 차례입니다.
        _ = pan.TryBegin(args);
    }

    /// <summary>
    /// 휠로 사진을 확대·축소합니다. macOS <c>zoomGesture</c>(<c>MagnificationGesture</c>)
    /// 자리이며, 줌 캡슐과 <b>같은 뷰포트</b>를 쓰므로 캡슐의 값도 함께 따라갑니다.
    /// </summary>
    private void OnCanvasPointerWheel(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        if (viewport is not { } state || previewBitmap is null)
        {
            return;
        }
        int delta = args.GetCurrentPoint(CanvasHost).Properties.MouseWheelDelta;
        if (delta == 0)
        {
            return;
        }
        state.ZoomBy(
            delta > 0 ? CanvasToolHudPolicy.ZoomStep : 1 / CanvasToolHudPolicy.ZoomStep,
            previewBitmap.PixelWidth,
            previewBitmap.PixelHeight,
            CanvasHost.ActualWidth,
            CanvasHost.ActualHeight);
        ApplyImageFrame();
        ZoomHud.RefreshZoomText();
        args.Handled = true;
    }

    private void OnCanvasPointerMoved(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        // 샘플러는 다른 도구를 막지 않습니다 — 값을 읽기만 하므로 크롭이나 브러시와 함께
        // 돌아도 서로 방해하지 않습니다.
        sampler.Update(args);
        if (TryContinueCompareDivider(args))
        {
            return;
        }
        if (TryHandlePointerMoved?.Invoke(args) == true)
        {
            return;
        }
        if (crop is not null && cropInteraction.TryContinueDrag(args, crop))
        {
            return;
        }
        _ = pan.TryContinue(args);
    }

    private void OnCanvasPointerReleased(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        if (EndCompareDivider(args))
        {
            return;
        }
        if (TryHandlePointerReleased?.Invoke(args) == true)
        {
            return;
        }
        if (crop is not null)
        {
            cropInteraction.EndDrag(args, crop);
        }
        _ = pan.End(args);
    }

    private void OnCanvasPointerCancelled(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        EndCompareDivider(args);
        HandlePointerCancelled?.Invoke(args);
        _ = pan.End(args);
        if (crop is not null)
        {
            cropInteraction.EndDrag(args, crop);
        }
    }

    private void OnCanvasPointerCaptureLost(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        EndCompareDivider(args);
        HandlePointerCancelled?.Invoke(args);
        _ = pan.End(args);
        if (crop is not null)
        {
            cropInteraction.EndDrag(args, crop);
        }
    }

    private void OnCanvasKeyDown(object sender, KeyRoutedEventArgs args)
    {
        Negaflow.Shell.Views.WorkspaceShellView.TraceKey(
            $"canvas keydown: key={args.Key} handled={args.Handled}");
        _ = sender;
        if (TryHandleKeyDown?.Invoke(args) == true)
        {
            return;
        }
        if (crop is not null)
        {
            cropInteraction.TryHandleKey(args, crop);
        }
    }
}
