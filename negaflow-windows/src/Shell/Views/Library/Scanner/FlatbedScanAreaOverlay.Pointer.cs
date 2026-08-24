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
/// 프레임을 고르고, 끌어서 옮기고, 손잡이로 크기를 바꾸고, 빈 자리에서 끌어 새로 그립니다.
/// macOS <c>createGesture</c> / <c>moveGesture</c> / <c>resizeGesture</c> 와 같은 규칙입니다.
/// </summary>
public sealed partial class FlatbedScanAreaOverlay
{
    /// <summary>이만큼은 끌어야 그리기로 봅니다. macOS `minimumDistance: 4` 와 같습니다.</summary>
    private const double CreateThreshold = 4.0;

    private Rectangle? draftRectangle;

    private Point createStart;

    private Point createCurrent;

    private bool creating;

    private bool createArmed;

    private FlatbedOverlayRect dragStartRect;

    private Point dragStartPoint;

    private string? draggingRegionId;

    private HandleTag? resizingHandle;

    protected override void OnPointerPressed(PointerRoutedEventArgs e)
    {
        base.OnPointerPressed(e);
        if (session is null || ImageFrame.Width <= 0)
        {
            return;
        }
        _ = Focus(FocusState.Pointer);
        Point point = e.GetCurrentPoint(Host).Position;
        // 이미 놓인 프레임 근처에서 시작하면 그리기가 아닙니다 - macOS
        // `canBeginCreation(at:existingRects:)` 와 같은 판단입니다.
        if (!FlatbedOverlayGeometry.CanBeginCreation(point.X, point.Y, ScreenRects))
        {
            return;
        }
        createStart = point;
        createCurrent = point;
        createArmed = true;
        creating = false;
        _ = CapturePointer(e.Pointer);
        e.Handled = true;
    }

    protected override void OnPointerMoved(PointerRoutedEventArgs e)
    {
        base.OnPointerMoved(e);
        if (!createArmed || session is null)
        {
            return;
        }
        createCurrent = e.GetCurrentPoint(Host).Position;
        if (!creating)
        {
            double moved = Math.Max(
                Math.Abs(createCurrent.X - createStart.X),
                Math.Abs(createCurrent.Y - createStart.Y));
            if (moved < CreateThreshold)
            {
                return;
            }
            creating = true;
        }
        LayoutDraftRectangle();
        e.Handled = true;
    }

    protected override void OnPointerReleased(PointerRoutedEventArgs e)
    {
        base.OnPointerReleased(e);
        ReleasePointerCapture(e.Pointer);
        if (!createArmed)
        {
            return;
        }
        createArmed = false;
        if (!creating || session is null)
        {
            creating = false;
            LayoutDraftRectangle();
            return;
        }
        creating = false;
        createCurrent = e.GetCurrentPoint(Host).Position;
        FlatbedScanRegion? drawn = DrawnRegion(createStart, createCurrent);
        LayoutDraftRectangle();
        if (drawn is not null && session.AddRegion(drawn) is not null)
        {
            LayoutRegions();
            NotifyChanged();
        }
        e.Handled = true;
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

    /// <summary>끌어서 그린 사각형입니다. 규격 비율로 맞춥니다(Alt 로 해제).</summary>
    private FlatbedScanRegion? DrawnRegion(Point start, Point current)
    {
        if (session is null)
        {
            return null;
        }
        bool transformed = TryPreviewTransform(
            out ImageTransformRecipe transform,
            out uint sourceWidth,
            out uint sourceHeight);
        (double startX, double startY) = transformed
            ? FlatbedOverlayGeometry.UnitPoint(
                start.X, start.Y, ImageFrame, transform, sourceWidth, sourceHeight)
            : FlatbedOverlayGeometry.UnitPoint(start.X, start.Y, ImageFrame);
        (double currentX, double currentY) = transformed
            ? FlatbedOverlayGeometry.UnitPoint(
                current.X, current.Y, ImageFrame, transform, sourceWidth, sourceHeight)
            : FlatbedOverlayGeometry.UnitPoint(current.X, current.Y, ImageFrame);
        FlatbedScanRegion drawn = FlatbedScanRegion.Create(
            Math.Min(startX, currentX),
            Math.Min(startY, currentY),
            Math.Abs(currentX - startX),
            Math.Abs(currentY - startY));
        if (drawn.UnitWidth < FlatbedScanRegionLayout.MinimumUnitExtent ||
            drawn.UnitHeight < FlatbedScanRegionLayout.MinimumUnitExtent)
        {
            return null;
        }
        if (IsDown(VirtualKey.Menu))
        {
            return drawn;
        }
        return FlatbedScanRegionLayout.SnappedToFrameAspect(
            drawn,
            drawn with { UnitX = startX, UnitY = startY, UnitWidth = 0, UnitHeight = 0 },
            session.Options.FrameFormat,
            session.PreviewArea);
    }

    /// <summary>그리는 중인 점선 사각형입니다. macOS 의 파선 6-4 와 같습니다.</summary>
    private void LayoutDraftRectangle()
    {
        if (!creating)
        {
            if (draftRectangle is not null)
            {
                _ = RegionLayer.Children.Remove(draftRectangle);
                draftRectangle = null;
            }
            return;
        }

        FlatbedOverlayRect rect = FlatbedOverlayGeometry.ClampedScreenRect(
            FlatbedOverlayGeometry.RectBetween(
                createStart.X, createStart.Y, createCurrent.X, createCurrent.Y),
            ImageFrame,
            minimum: 0);
        draftRectangle ??= NewDraftRectangle();
        if (!RegionLayer.Children.Contains(draftRectangle))
        {
            RegionLayer.Children.Add(draftRectangle);
        }
        draftRectangle.Width = Math.Max(rect.Width, 0);
        draftRectangle.Height = Math.Max(rect.Height, 0);
        Canvas.SetLeft(draftRectangle, rect.X);
        Canvas.SetTop(draftRectangle, rect.Y);
    }

    private Rectangle NewDraftRectangle() => new()
    {
        Fill = AccentBrush(0.08),
        Stroke = AccentBrush(1.0),
        StrokeThickness = 1.5,
        StrokeDashArray = [6, 4],
        IsHitTestVisible = false,
    };

    private static bool IsDown(VirtualKey key) =>
        InputKeyboardSource.GetKeyStateForCurrentThread(key)
            .HasFlag(CoreVirtualKeyStates.Down);
}
