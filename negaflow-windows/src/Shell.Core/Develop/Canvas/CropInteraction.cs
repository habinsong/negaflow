using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

public enum CropDragMode
{
    None,
    Create,
    Move,
    TopLeft,
    Top,
    TopRight,
    Right,
    BottomRight,
    Bottom,
    BottomLeft,
    Left,
}

/// <summary>크롭 오버레이 한 요소의 캔버스 좌표입니다.</summary>
public readonly record struct CropOverlayPlacement(
    double Left,
    double Top,
    double Width,
    double Height);

/// <summary>크롭 오버레이의 표시 기하입니다. WinUI 컨트롤은 이 값을 그대로 배치합니다.</summary>
public sealed record CropOverlayLayout(
    CropOverlayPlacement DimTop,
    CropOverlayPlacement DimBottom,
    CropOverlayPlacement DimLeft,
    CropOverlayPlacement DimRight,
    CropOverlayPlacement Selection,
    CropOverlayPlacement HandleTopLeft,
    CropOverlayPlacement HandleTop,
    CropOverlayPlacement HandleTopRight,
    CropOverlayPlacement HandleRight,
    CropOverlayPlacement HandleBottomRight,
    CropOverlayPlacement HandleBottom,
    CropOverlayPlacement HandleBottomLeft,
    CropOverlayPlacement HandleLeft,
    (double X1, double Y1, double X2, double Y2) ThirdVerticalFirst,
    (double X1, double Y1, double X2, double Y2) ThirdVerticalSecond,
    (double X1, double Y1, double X2, double Y2) ThirdHorizontalFirst,
    (double X1, double Y1, double X2, double Y2) ThirdHorizontalSecond,
    double ActionBarLeft,
    double ActionBarTop);

/// <summary>
/// 크롭 드래그·히트테스트·오버레이 기하입니다. 미리보기 렌더, GrainMend, 내보내기와 다른
/// 변경 이유를 가지므로 Develop 뷰 밖에 둡니다.
/// </summary>
public static class CropInteraction
{
    public const double HandleHitRadius = 0.025;
    public const double HandleSize = 14.0;
    public const double LongHandleSize = 24.0;
    public const double ActionBarHalfWidth = 86.0;
    public const double ActionBarInsetY = 28.0;
    public const double ActionBarOffsetY = 30.0;

    public static CropDragMode BeginDrag(CropDisplayPoint point, CropDisplayRect selection)
    {
        return HitHandle(point, selection) ??
            (Contains(selection, point) && !selection.IsFull
                ? CropDragMode.Move
                : CropDragMode.Create);
    }

    /// <summary>
    /// 프레임 크기를 알고 있을 때의 판정입니다. 히트 영역이 <b>그려진 핸들</b>과 같아집니다.
    /// </summary>
    public static CropDragMode BeginDrag(
        CropDisplayPoint point,
        CropDisplayRect selection,
        double frameWidth,
        double frameHeight)
    {
        return HitHandle(point, selection, frameWidth, frameHeight) ??
            (Contains(selection, point) && !selection.IsFull
                ? CropDragMode.Move
                : CropDragMode.Create);
    }

    /// <summary>
    /// 그려진 핸들 사각형 그대로 판정합니다. macOS 는 핸들마다 뷰가 있어 그 사각형이 곧
    /// 히트 영역입니다(<c>CropOverlay.handleView</c>: 14×14, 위·아래는 24×14,
    /// 좌·우는 14×24).
    /// </summary>
    public static CropDragMode? HitHandle(
        CropDisplayPoint point,
        CropDisplayRect rect,
        double frameWidth,
        double frameHeight)
    {
        if (frameWidth <= 0.0 || frameHeight <= 0.0)
        {
            return HitHandle(point, rect);
        }
        foreach ((CropDragMode mode, double x, double y, bool wide, bool tall) candidate in new[]
                 {
                     (CropDragMode.TopLeft, rect.X, rect.Y, false, false),
                     (CropDragMode.Top, rect.X + rect.Width / 2.0, rect.Y, true, false),
                     (CropDragMode.TopRight, rect.Right, rect.Y, false, false),
                     (CropDragMode.Right, rect.Right, rect.Y + rect.Height / 2.0, false, true),
                     (CropDragMode.BottomRight, rect.Right, rect.Bottom, false, false),
                     (CropDragMode.Bottom, rect.X + rect.Width / 2.0, rect.Bottom, true, false),
                     (CropDragMode.BottomLeft, rect.X, rect.Bottom, false, false),
                     (CropDragMode.Left, rect.X, rect.Y + rect.Height / 2.0, false, true),
                 })
        {
            double halfX = (candidate.wide ? LongHandleSize : HandleSize) / 2.0 / frameWidth;
            double halfY = (candidate.tall ? LongHandleSize : HandleSize) / 2.0 / frameHeight;
            if (Math.Abs(point.X - candidate.x) <= halfX &&
                Math.Abs(point.Y - candidate.y) <= halfY)
            {
                return candidate.mode;
            }
        }

        return null;
    }

    public static CropHandle? HandleFor(CropDragMode mode) => mode switch
    {
        CropDragMode.TopLeft => CropHandle.TopLeft,
        CropDragMode.Top => CropHandle.Top,
        CropDragMode.TopRight => CropHandle.TopRight,
        CropDragMode.Right => CropHandle.Right,
        CropDragMode.BottomRight => CropHandle.BottomRight,
        CropDragMode.Bottom => CropHandle.Bottom,
        CropDragMode.BottomLeft => CropHandle.BottomLeft,
        CropDragMode.Left => CropHandle.Left,
        _ => null,
    };

    public static CropDragMode? HitHandle(CropDisplayPoint point, CropDisplayRect rect)
    {
        foreach ((CropDragMode mode, double x, double y) candidate in new[]
                 {
                     (CropDragMode.TopLeft, rect.X, rect.Y),
                     (CropDragMode.Top, rect.X + rect.Width / 2.0, rect.Y),
                     (CropDragMode.TopRight, rect.Right, rect.Y),
                     (CropDragMode.Right, rect.Right, rect.Y + rect.Height / 2.0),
                     (CropDragMode.BottomRight, rect.Right, rect.Bottom),
                     (CropDragMode.Bottom, rect.X + rect.Width / 2.0, rect.Bottom),
                     (CropDragMode.BottomLeft, rect.X, rect.Bottom),
                     (CropDragMode.Left, rect.X, rect.Y + rect.Height / 2.0),
                 })
        {
            if (Math.Abs(point.X - candidate.x) <= HandleHitRadius &&
                Math.Abs(point.Y - candidate.y) <= HandleHitRadius)
            {
                return candidate.mode;
            }
        }

        return null;
    }

    public static bool Contains(CropDisplayRect rect, CropDisplayPoint point) =>
        point.X >= rect.X && point.X <= rect.Right && point.Y >= rect.Y && point.Y <= rect.Bottom;

    /// <summary>
    /// 잠긴 비율을 <b>정규</b> 값으로 냅니다. macOS <c>cropAspectLockRatio(for:)</c> 그대로입니다 —
    /// 고른 비율이 있으면 그것을, 없으면 <b>지금 사각형의 화소 비율</b>을 잠급니다.
    /// </summary>
    /// <remarks>
    /// 앞 판은 고른 비율이 없으면 <c>null</c> 을 냈습니다. 비율 고르개의 기본값이 "원본"
    /// 이므로 자물쇠를 눌러도 아무 일도 일어나지 않았습니다 — 사용자가 "잠금 기능이
    /// 미구현" 이라고 한 것이 이것입니다. macOS 는 그때 지금 사각형의 비율을 잠급니다.
    /// </remarks>
    public static double? LockedNormalizedAspectRatio(
        bool isLocked,
        double? cropAspect,
        uint pixelWidth,
        uint pixelHeight,
        ImageRotation rotation,
        CropDisplayRect? selection = null)
    {
        if (!isLocked || pixelWidth == 0U || pixelHeight == 0U)
        {
            return null;
        }

        double width = pixelWidth;
        double height = pixelHeight;
        if (rotation is ImageRotation.Degrees90 or ImageRotation.Degrees270)
        {
            (width, height) = (height, width);
        }

        double aspect;
        if (cropAspect is { } chosen && double.IsFinite(chosen) && chosen > 0.0)
        {
            aspect = chosen;
        }
        else if (selection is { } visible && visible.Width > 0.0 && visible.Height > 0.0)
        {
            // macOS: max(0.05, min(20, (visible.width * imageW) / (visible.height * imageH)))
            aspect = Math.Clamp(
                visible.Width * width / (visible.Height * height),
                0.05,
                20.0);
        }
        else
        {
            aspect = width / height;
        }

        return aspect * height / width;
    }

    public static CropOverlayLayout Layout(
        PreviewFrame frame,
        CropDisplayRect selection,
        double actionBarHeight)
    {
        double cropLeft = frame.Left + selection.X * frame.Width;
        double cropTop = frame.Top + selection.Y * frame.Height;
        double cropWidth = selection.Width * frame.Width;
        double cropHeight = selection.Height * frame.Height;
        double barHalfHeight = actionBarHeight > 0.0 ? actionBarHeight / 2.0 : 21.0;
        double actionBarLeft = Math.Clamp(
            cropLeft + cropWidth / 2.0,
            frame.Left + ActionBarHalfWidth,
            Math.Max(frame.Left + ActionBarHalfWidth, frame.Right - ActionBarHalfWidth)) -
            ActionBarHalfWidth;
        double actionBarTop = Math.Clamp(
            cropTop + cropHeight + ActionBarOffsetY,
            frame.Top + ActionBarInsetY,
            Math.Max(frame.Top + ActionBarInsetY, frame.Bottom - ActionBarInsetY)) -
            barHalfHeight;

        return new CropOverlayLayout(
            new CropOverlayPlacement(frame.Left, frame.Top, frame.Width, Math.Max(0.0, cropTop - frame.Top)),
            new CropOverlayPlacement(
                frame.Left,
                cropTop + cropHeight,
                frame.Width,
                Math.Max(0.0, frame.Bottom - (cropTop + cropHeight))),
            new CropOverlayPlacement(frame.Left, cropTop, Math.Max(0.0, cropLeft - frame.Left), cropHeight),
            new CropOverlayPlacement(
                cropLeft + cropWidth,
                cropTop,
                Math.Max(0.0, frame.Right - (cropLeft + cropWidth)),
                cropHeight),
            new CropOverlayPlacement(cropLeft, cropTop, cropWidth, cropHeight),
            Handle(cropLeft, cropTop, false, false),
            Handle(cropLeft + cropWidth / 2.0, cropTop, true, false),
            Handle(cropLeft + cropWidth, cropTop, false, false),
            Handle(cropLeft + cropWidth, cropTop + cropHeight / 2.0, false, true),
            Handle(cropLeft + cropWidth, cropTop + cropHeight, false, false),
            Handle(cropLeft + cropWidth / 2.0, cropTop + cropHeight, true, false),
            Handle(cropLeft, cropTop + cropHeight, false, false),
            Handle(cropLeft, cropTop + cropHeight / 2.0, false, true),
            (cropLeft + cropWidth / 3.0, cropTop, cropLeft + cropWidth / 3.0, cropTop + cropHeight),
            (cropLeft + cropWidth * 2.0 / 3.0, cropTop, cropLeft + cropWidth * 2.0 / 3.0, cropTop + cropHeight),
            (cropLeft, cropTop + cropHeight / 3.0, cropLeft + cropWidth, cropTop + cropHeight / 3.0),
            (cropLeft, cropTop + cropHeight * 2.0 / 3.0, cropLeft + cropWidth, cropTop + cropHeight * 2.0 / 3.0),
            actionBarLeft,
            actionBarTop);
    }

    private static CropOverlayPlacement Handle(
        double centerX,
        double centerY,
        bool horizontal,
        bool vertical)
    {
        double width = horizontal ? LongHandleSize : HandleSize;
        double height = vertical ? LongHandleSize : HandleSize;
        return new CropOverlayPlacement(centerX - width / 2.0, centerY - height / 2.0, width, height);
    }
}
