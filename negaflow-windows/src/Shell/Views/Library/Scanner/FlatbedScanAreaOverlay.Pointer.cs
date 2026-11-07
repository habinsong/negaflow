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
    private FlatbedRegionScreenShape dragStartShape;

    private FlatbedScanRegion? dragStartRegion;

    private Point dragStartPoint;

    private string? draggingRegionId;

    private HandleTag? resizingHandle;

    /// <summary>
    /// 끌기 기준을 새 사진 자리로 옮깁니다. 끌고 있지 않으면 아무것도 하지 않습니다.
    /// </summary>
    /// <remarks>
    /// 기준(<see cref="dragStartShape"/>, <see cref="dragStartPoint"/>)은 누른 순간의 화면
    /// 좌표입니다. 그 사이 휠 확대·축소나 창 크기 변경으로 사진 자리가 움직이면 기준만 옛
    /// 자리에 남아, 다음 이동에서 옛 좌표를 새 자리에 대고 재게 됩니다 — 스캔 영역이 줌
    /// 배율만큼 함께 커지거나 작아집니다. 사진 위에서의 비율은 그대로 두고 화면 좌표만
    /// 옮겨 그 어긋남을 없앱니다.
    /// </remarks>
    private void RebaseDrag(FlatbedOverlayRect previousFrame)
    {
        if ((draggingRegionId is null && resizingHandle is null) ||
            previousFrame.Width <= 0 || previousFrame.Height <= 0 ||
            ImageFrame.Width <= 0 || ImageFrame.Height <= 0)
        {
            return;
        }
        (double centerX, double centerY) = FlatbedOverlayGeometry.RebasedPoint(
            dragStartShape.CenterX, dragStartShape.CenterY, previousFrame, ImageFrame);
        double scale = ImageFrame.Width / previousFrame.Width;
        dragStartShape = dragStartShape with
        {
            CenterX = centerX,
            CenterY = centerY,
            Width = dragStartShape.Width * scale,
            Height = dragStartShape.Height * scale,
        };
        (double x, double y) = FlatbedOverlayGeometry.RebasedPoint(
            dragStartPoint.X, dragStartPoint.Y, previousFrame, ImageFrame);
        dragStartPoint = new Point(x, y);
    }

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
        dragStartShape = Shape(region);
        dragStartRegion = region;
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
        double dx = point.X - dragStartPoint.X, dy = point.Y - dragStartPoint.Y;
        // 누르기만 하면 아무것도 바꾸지 않습니다. 이동 0 으로 다시 쓰면 경계 상자 왕복만큼 커졌습니다.
        if (Math.Sqrt((dx * dx) + (dy * dy)) < 0.5 || dragStartRegion is not { } startRegion)
        {
            return;
        }
        FlatbedRegionScreenShape moved = dragStartShape with
        {
            CenterX = dragStartShape.CenterX + dx,
            CenterY = dragStartShape.CenterY + dy,
        };
        ApplyShape(regionId, moved, startRegion.StraightenAngle);
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
        dragStartShape = Shape(region);
        dragStartRegion = region;
        dragStartPoint = e.GetCurrentPoint(Host).Position;
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
        double dx = point.X - dragStartPoint.X, dy = point.Y - dragStartPoint.Y;
        if (Math.Sqrt((dx * dx) + (dy * dy)) < 0.5 || dragStartRegion is not { } startRegion)
        {
            return;
        }
        // 기운 칸은 자기 좌표에서 크기를 바꿉니다. 사진 경계도 그 좌표로 옮겨 씁니다.
        (double localX, double localY) = dragStartShape.LocalPoint(point.X, point.Y);
        FlatbedOverlayRect proposed = FlatbedOverlayGeometry.ResizedRect(
            new FlatbedOverlayRect(0, 0, dragStartShape.Width, dragStartShape.Height),
            localX, localY, tag.Handle, LocalImageBounds(dragStartShape));
        ApplyShape(tag.RegionId, dragStartShape.Reshaped(proposed), startRegion.StraightenAngle, startRegion);
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
    /// 화면 칸을 프레임으로 되돌려 기록합니다. 크기를 바꾼 조작이면 규격 비율로 맞춥니다 — Alt 를
    /// 누르고 있으면 자유 비율입니다(규격에 없는 필름용 탈출구). 비율은 칸을 자기 방향으로 눕힌
    /// 좌표에서 맞춥니다. 기운 칸의 경계 상자는 규격 비율이 아닙니다.
    /// </summary>
    private void ApplyShape(
        string regionId,
        FlatbedRegionScreenShape shape,
        double angle,
        FlatbedScanRegion? anchoredTo = null)
    {
        if (session is null)
        {
            return;
        }
        bool transformed = TryPreviewTransform(out ImageTransformRecipe transform, out uint sourceWidth,
            out uint sourceHeight);
        (double x, double y, double width, double height) = FlatbedRegionFrameGeometry.UnitRect(
            shape, ImageFrame, transformed ? transform : null, sourceWidth, sourceHeight);
        FlatbedScanRegion moved = new FlatbedScanRegion(regionId, x, y, width, height, angle).Clamped();
        if (anchoredTo is { } anchor && !IsDown(VirtualKey.Menu))
        {
            FlatbedScanRegion local = LocalRegion(moved, angle, sourceWidth, sourceHeight);
            FlatbedScanRegion anchorLocal = LocalRegion(anchor, angle, sourceWidth, sourceHeight);
            FlatbedScanRegion snapped = FlatbedScanRegionLayout.SnappedToFrameAspect(
                local, anchorLocal, session.FrameSize, session.PreviewArea);
            (x, y, width, height) = FlatbedRegionFrameGeometry.UnitRectFromFrameLocal(
                (snapped.UnitX, snapped.UnitY, snapped.UnitWidth, snapped.UnitHeight),
                angle, sourceWidth, sourceHeight);
            moved = new FlatbedScanRegion(regionId, x, y, width, height, angle).Clamped();
        }
        if (session.UpdateRegion(regionId, moved))
        {
            LayoutRegions();
        }
    }

    private static FlatbedScanRegion LocalRegion(
        FlatbedScanRegion region, double angle, uint sourceWidth, uint sourceHeight)
    {
        (double x, double y, double width, double height) = FlatbedRegionFrameGeometry.FrameLocalRect(
            region.UnitX, region.UnitY, region.UnitWidth, region.UnitHeight,
            region.StraightenAngle, angle, sourceWidth, sourceHeight);
        return region with { UnitX = x, UnitY = y, UnitWidth = width, UnitHeight = height, StraightenAngle = 0.0 };
    }

    /// <summary>사진 자리를 칸 자기 좌표로 옮긴 경계입니다. 손잡이를 끌어도 사진 밖으로 나가지 않습니다.</summary>
    private FlatbedOverlayRect LocalImageBounds(FlatbedRegionScreenShape shape)
    {
        (double X, double Y)[] corners =
        [
            shape.LocalPoint(ImageFrame.X, ImageFrame.Y),
            shape.LocalPoint(ImageFrame.MaxX, ImageFrame.Y),
            shape.LocalPoint(ImageFrame.MaxX, ImageFrame.MaxY),
            shape.LocalPoint(ImageFrame.X, ImageFrame.MaxY),
        ];
        double minX = corners.Min(point => point.X), maxX = corners.Max(point => point.X);
        double minY = corners.Min(point => point.Y), maxY = corners.Max(point => point.Y);
        return new FlatbedOverlayRect(minX, minY, maxX - minX, maxY - minY);
    }

    private static bool IsDown(VirtualKey key) =>
        InputKeyboardSource.GetKeyStateForCurrentThread(key)
            .HasFlag(CoreVirtualKeyStates.Down);
}
