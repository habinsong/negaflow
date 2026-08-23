using Microsoft.UI.Input;
using Microsoft.UI.Xaml.Input;
using Negaflow.Shell.Develop;
using Windows.System;
using Windows.UI.Core;

namespace Negaflow.Shell.Views.Develop.Canvas;

/// <summary>
/// 캔버스 위의 크롭 드래그와 화살표 키입니다. 카탈로그 쓰기는 뷰가 이벤트에서 맡습니다.
/// </summary>
internal sealed class DevelopCanvasCropInteraction
{
    private readonly DevelopPreviewCanvas view;

    internal DevelopCanvasCropInteraction(DevelopPreviewCanvas view) => this.view = view;

    internal bool TryBeginDrag(PointerRoutedEventArgs args, CropWorkspaceState crop)
    {
        // 핸들은 절반이 그림 밖에 그려집니다. 그 절반까지 받아야 눈에 보이는 대로 잡힙니다.
        if (!view.TryMapPointerForCrop(
                args,
                CropInteraction.LongHandleSize / 2.0,
                out CropDisplayPoint point,
                out bool inside,
                out double frameWidth,
                out double frameHeight) ||
            !crop.TryBeginDrag(point, frameWidth, frameHeight, allowCreate: inside))
        {
            return false;
        }
        view.CaptureHost(args.Pointer);
        args.Handled = true;
        return true;
    }

    internal bool TryContinueDrag(PointerRoutedEventArgs args, CropWorkspaceState crop)
    {
        // 끄는 동안에는 그림 밖으로 나가도 가장자리에 붙여 이어 갑니다 — macOS 도 제스처가
        // 잡혀 있는 동안 좌표를 그대로 받습니다.
        if (!view.TryMapPointerForCrop(
                args,
                double.MaxValue / 4.0,
                out CropDisplayPoint point,
                out _,
                out _,
                out _) ||
            !crop.TryContinueDrag(point))
        {
            return false;
        }
        view.RenderCropOverlay();
        args.Handled = true;
        return true;
    }

    internal void EndDrag(PointerRoutedEventArgs args, CropWorkspaceState crop)
    {
        if (!crop.EndDrag())
        {
            return;
        }
        view.ReleaseHost(args.Pointer);
        args.Handled = true;
    }

    internal bool TryHandleKey(KeyRoutedEventArgs args, CropWorkspaceState crop)
    {
        if (!crop.IsActive)
        {
            return false;
        }
        if (args.Key == VirtualKey.Escape)
        {
            view.RaiseCropCancel();
            args.Handled = true;
            return true;
        }

        double step = InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Shift)
            .HasFlag(CoreVirtualKeyStates.Down) ? 0.02 : 0.005;
        switch (args.Key)
        {
            case VirtualKey.Left:
                crop.TryMove(-step, 0.0);
                break;
            case VirtualKey.Right:
                crop.TryMove(step, 0.0);
                break;
            case VirtualKey.Up:
                crop.TryMove(0.0, -step);
                break;
            case VirtualKey.Down:
                crop.TryMove(0.0, step);
                break;
            default:
                return false;
        }
        view.RenderCropOverlay();
        args.Handled = true;
        return true;
    }
}
