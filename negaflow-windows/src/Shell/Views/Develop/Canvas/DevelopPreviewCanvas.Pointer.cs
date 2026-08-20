using Microsoft.UI.Xaml.Input;

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
        if (crop is not null)
        {
            cropInteraction.TryBeginDrag(args, crop);
        }
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
        if (crop is not null)
        {
            cropInteraction.TryContinueDrag(args, crop);
        }
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
    }

    private void OnCanvasPointerCancelled(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        EndCompareDivider(args);
        HandlePointerCancelled?.Invoke(args);
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
        if (crop is not null)
        {
            cropInteraction.EndDrag(args, crop);
        }
    }

    private void OnCanvasKeyDown(object sender, KeyRoutedEventArgs args)
    {
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
