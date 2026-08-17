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
        if (!view.TryMapPointer(args, out CropDisplayPoint point) || !crop.TryBeginDrag(point))
        {
            return false;
        }
        view.CaptureHost(args.Pointer);
        args.Handled = true;
        return true;
    }

    internal bool TryContinueDrag(PointerRoutedEventArgs args, CropWorkspaceState crop)
    {
        if (!view.TryMapPointer(args, out CropDisplayPoint point) || !crop.TryContinueDrag(point))
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
