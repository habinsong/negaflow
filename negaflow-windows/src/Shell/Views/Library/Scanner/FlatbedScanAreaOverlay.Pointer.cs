using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Negaflow.Catalog;
using Windows.Foundation;
using Windows.System;
using Windows.UI;
using Windows.UI.Core;

namespace Negaflow.Shell.Views.Library.Scanner;

/// <summary>
/// 프레임을 고르고, 끌어서 옮기고, 손잡이로 크기를 바꿉니다.
/// </summary>
/// <remarks>
/// **빈 자리를 끄는 것은 사진을 옮기는 동작입니다.**
///
/// 앞 판은 빈 자리에서 끌면 새 사각형을 그렸습니다. 그 자리는 캔버스가 사진을 잡고 끄는
/// 자리와 같아서, 오버레이가 포인터를 먼저 잡고 <c>Handled</c> 로 막는 순간 사진을 움직일
/// 방법이 사라졌습니다 - 두 동작이 같은 몸짓을 두고 다툰 것입니다. 새 프레임은 더하기 단추와
/// 복사·붙여넣기(Ctrl+C / Ctrl+V)로 만들고, 만든 사각형을 끌어서 자리를 잡습니다.
/// </remarks>
public sealed partial class FlatbedScanAreaOverlay
{
    private FlatbedOverlayRect dragStartRect;

    private Point dragStartPoint;

    private string? draggingRegionId;

    private HandleTag? resizingHandle;

    private void OnRegionPointerPressed(object sender, PointerRoutedEventArgs e)
    {
        if (sender is not Border body || body.Tag is not string regionId || session is null)
        {
            return;
        }
        _ = Focus(FocusState.Pointer);
        session.SelectRegion(regionId);
        LayoutRegions();
        if (Regions.FirstOrDefault(region =>
                string.Equals(region.Id, regionId, StringComparison.Ordinal)) is not { } region)
        {
            return;
        }
        draggingRegionId = regionId;
        dragStartRect = ScreenRect(region);
        dragStartPoint = e.GetCurrentPoint(Host).Position;
        _ = body.CapturePointer(e.Pointer);
        e.Handled = true;
    }

    private void OnRegionPointerMoved(object sender, PointerRoutedEventArgs e)
    {
        if (draggingRegionId is not { } regionId || session is null)
        {
            return;
        }
        Point point = e.GetCurrentPoint(Host).Position;
        FlatbedOverlayRect moved = FlatbedOverlayGeometry.ClampedScreenRect(
            dragStartRect.OffsetBy(point.X - dragStartPoint.X, point.Y - dragStartPoint.Y),
            ImageFrame);
        ApplyScreenRect(regionId, moved);
        e.Handled = true;
    }

    private void OnRegionPointerReleased(object sender, PointerRoutedEventArgs e)
    {
        if (sender is Border body)
        {
            body.ReleasePointerCapture(e.Pointer);
        }
        if (draggingRegionId is null)
        {
            return;
        }
        draggingRegionId = null;
        NotifyChanged();
    }

    private void OnHandlePointerPressed(object sender, PointerRoutedEventArgs e)
    {
        if (sender is not Border grip || grip.Tag is not HandleTag tag || session is null)
        {
            return;
        }
        if (Regions.FirstOrDefault(region =>
                string.Equals(region.Id, tag.RegionId, StringComparison.Ordinal)) is not { } region)
        {
            return;
        }
        _ = Focus(FocusState.Pointer);
        resizingHandle = tag;
        dragStartRect = ScreenRect(region);
        _ = grip.CapturePointer(e.Pointer);
        e.Handled = true;
    }

    private void OnHandlePointerMoved(object sender, PointerRoutedEventArgs e)
    {
        if (resizingHandle is not { } tag || session is null)
        {
            return;
        }
        Point point = e.GetCurrentPoint(Host).Position;
        FlatbedOverlayRect proposed = FlatbedOverlayGeometry.ResizedRect(
            dragStartRect, point.X, point.Y, tag.Handle, ImageFrame);
        ApplyScreenRect(tag.RegionId, proposed, anchoredTo: dragStartRect);
        e.Handled = true;
    }

    private void OnHandlePointerReleased(object sender, PointerRoutedEventArgs e)
    {
        if (sender is Border grip)
        {
            grip.ReleasePointerCapture(e.Pointer);
        }
        if (resizingHandle is null)
        {
            return;
        }
        resizingHandle = null;
        NotifyChanged();
    }

    protected override void OnKeyDown(KeyRoutedEventArgs e)
    {
        base.OnKeyDown(e);
        if (session is null)
        {
            return;
        }
        bool shift = IsDown(VirtualKey.Shift);
        bool control = IsDown(VirtualKey.Control);
        if (e.Key is VirtualKey.Delete or VirtualKey.Back)
        {
            if (session.DeleteSelectedRegion())
            {
                LayoutRegions();
                NotifyChanged();
                e.Handled = true;
            }
            return;
        }
        // Ctrl+C / Ctrl+V 는 macOS 의 Cmd+C / Cmd+V 자리입니다. 포커스가 이 오버레이에
        // 있을 때만 살아 있어 옆 글상자의 복사를 빼앗지 않습니다.
        if (control && e.Key == VirtualKey.C)
        {
            if (session.CopySelectedRegion())
            {
                e.Handled = true;
            }
            return;
        }
        if (control && e.Key == VirtualKey.V)
        {
            if (session.PasteRegion())
            {
                LayoutRegions();
                NotifyChanged();
                e.Handled = true;
            }
            return;
        }
        (double dx, double dy) = e.Key switch
        {
            VirtualKey.Left => (-1.0, 0.0),
            VirtualKey.Right => (1.0, 0.0),
            VirtualKey.Up => (0.0, -1.0),
            VirtualKey.Down => (0.0, 1.0),
            _ => (0.0, 0.0),
        };
        if (dx == 0 && dy == 0)
        {
            return;
        }
        bool transformed = TryPreviewTransform(
            out ImageTransformRecipe transform,
            out uint sourceWidth,
            out uint sourceHeight);
        if (session.NudgeSelectedRegion(
                dx,
                dy,
                shift,
                transformed ? transform : null,
                sourceWidth,
                sourceHeight))
        {
            LayoutRegions();
            NotifyChanged();
            e.Handled = true;
        }
    }

    /// <summary>
    /// 화면 사각형을 프레임 비율로 되돌려 기록합니다. 크기를 바꾼 조작이면 규격 비율로
    /// 맞춥니다 - Alt 를 누르고 있으면 자유 비율입니다(규격에 없는 필름용 탈출구).
    /// </summary>
    private void ApplyScreenRect(
        string regionId,
        FlatbedOverlayRect screenRect,
        FlatbedOverlayRect? anchoredTo = null)
    {
        if (session is null)
        {
            return;
        }
        FlatbedScanRegion moved = ToRegion(regionId, screenRect);
        if (anchoredTo is { } anchor && !IsDown(VirtualKey.Menu))
        {
            moved = FlatbedScanRegionLayout.SnappedToFrameAspect(
                moved,
                ToRegion(regionId, anchor),
                session.Options.FrameFormat,
                session.PreviewArea);
        }
        if (session.UpdateRegion(regionId, moved))
        {
            LayoutRegions();
        }
    }

    private FlatbedScanRegion ToRegion(string regionId, FlatbedOverlayRect screenRect)
    {
        (double x, double y, double width, double height) =
            TryPreviewTransform(out ImageTransformRecipe transform, out uint sourceWidth,
                out uint sourceHeight)
                ? FlatbedOverlayGeometry.UnitRect(
                    screenRect, ImageFrame, transform, sourceWidth, sourceHeight)
                : FlatbedOverlayGeometry.UnitRect(screenRect, ImageFrame);
        return new FlatbedScanRegion(regionId, x, y, width, height).Clamped();
    }

    private static bool IsDown(VirtualKey key) =>
        InputKeyboardSource.GetKeyStateForCurrentThread(key)
            .HasFlag(CoreVirtualKeyStates.Down);
}
