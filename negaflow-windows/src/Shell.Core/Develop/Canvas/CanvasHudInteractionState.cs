namespace Negaflow.Shell.Develop;

/// <summary>macOS <c>CanvasHUDInteractionState</c> + <c>canvasHUDDragGesture</c>.</summary>
public sealed class CanvasHudInteractionState
{
    /// <summary>macOS <c>DragGesture(minimumDistance: 4)</c>.</summary>
    public const double MinimumDragDistance = 4;

    public double? CompareOriginX { get; private set; }

    public double? CompareOriginY { get; private set; }

    public double? ZoomOriginX { get; private set; }

    public double? ZoomOriginY { get; private set; }

    public double? CompareDragStartX { get; private set; }

    public double? CompareDragStartY { get; private set; }

    public double? ZoomDragStartX { get; private set; }

    public double? ZoomDragStartY { get; private set; }

    public double CompareWidth { get; private set; } = CanvasHudPlacement.DefaultCompareWidth;

    public double CompareHeight { get; private set; } = CanvasHudPlacement.DefaultCompareHeight;

    public double ZoomWidth { get; private set; } = CanvasHudPlacement.DefaultZoomWidth;

    public double ZoomHeight { get; private set; } = CanvasHudPlacement.DefaultZoomHeight;

    /// <summary>macOS <c>reportCanvasHUDSize</c>.</summary>
    public void SetMeasuredSize(CanvasHudKind kind, double width, double height)
    {
        if (width <= 0 || height <= 0)
        {
            return;
        }

        if (kind == CanvasHudKind.Compare)
        {
            CompareWidth = width;
            CompareHeight = height;
        }
        else
        {
            ZoomWidth = width;
            ZoomHeight = height;
        }
    }

    /// <summary>macOS <c>resolvedCanvasHUDOrigins</c>.</summary>
    public CanvasHudOrigins Resolve(double canvasWidth, double canvasHeight)
    {
        CanvasHudOrigins defaults = CanvasHudPlacement.DefaultOrigins(
            canvasWidth,
            canvasHeight,
            CompareWidth,
            CompareHeight,
            ZoomWidth,
            ZoomHeight);
        (double compareX, double compareY) = CanvasHudPlacement.ClampedOrigin(
            CompareOriginX ?? defaults.CompareX,
            CompareOriginY ?? defaults.CompareY,
            CompareWidth,
            CompareHeight,
            canvasWidth,
            canvasHeight);
        (double zoomX, double zoomY) = CanvasHudPlacement.AvoidingOverlap(
            ZoomOriginX ?? defaults.ZoomX,
            ZoomOriginY ?? defaults.ZoomY,
            ZoomWidth,
            ZoomHeight,
            compareX,
            compareY,
            CompareWidth,
            CompareHeight,
            canvasWidth,
            canvasHeight);
        return new CanvasHudOrigins(compareX, compareY, zoomX, zoomY);
    }

    /// <summary>macOS <c>canvasHUDDragGesture.onChanged</c>.</summary>
    /// <summary>
    /// 인화 캔버스에는 줌 캡슐 <b>하나뿐</b>입니다. 기본 자리가 현상과 다르고, 피할 상대도
    /// 없으므로 가장자리만 잡습니다.
    /// </summary>
    public CanvasHudOrigins ResolvePrintZoom(double canvasWidth, double canvasHeight)
    {
        (double defaultX, double defaultY) = CanvasHudPlacement.PrintZoomOrigin(
            canvasWidth,
            canvasHeight,
            ZoomWidth,
            ZoomHeight);
        (double x, double y) = CanvasHudPlacement.ClampedOrigin(
            ZoomOriginX ?? defaultX,
            ZoomOriginY ?? defaultY,
            ZoomWidth,
            ZoomHeight,
            canvasWidth,
            canvasHeight);
        return new CanvasHudOrigins(0, 0, x, y);
    }

    /// <summary>인화 캔버스의 줌 캡슐 끌기입니다. 피할 상대가 없습니다.</summary>
    public void UpdatePrintZoomDrag(
        double translationX,
        double translationY,
        double currentOriginX,
        double currentOriginY,
        double canvasWidth,
        double canvasHeight)
    {
        ZoomDragStartX ??= currentOriginX;
        ZoomDragStartY ??= currentOriginY;
        if (ZoomDragStartX is not { } startX || ZoomDragStartY is not { } startY)
        {
            return;
        }
        (double x, double y) = CanvasHudPlacement.ClampedOrigin(
            startX + translationX,
            startY + translationY,
            ZoomWidth,
            ZoomHeight,
            canvasWidth,
            canvasHeight);
        ZoomOriginX = x;
        ZoomOriginY = y;
    }

    public void BeginOrUpdateDrag(
        CanvasHudKind kind,
        double translationX,
        double translationY,
        double currentOriginX,
        double currentOriginY,
        double canvasWidth,
        double canvasHeight)
    {
        CanvasHudOrigins origins = Resolve(canvasWidth, canvasHeight);
        if (kind == CanvasHudKind.Compare)
        {
            CompareDragStartX ??= currentOriginX;
            CompareDragStartY ??= currentOriginY;
            if (CompareDragStartX is not { } startX || CompareDragStartY is not { } startY)
            {
                return;
            }

            (double x, double y) = CanvasHudPlacement.AvoidingOverlap(
                startX + translationX,
                startY + translationY,
                CompareWidth,
                CompareHeight,
                origins.ZoomX,
                origins.ZoomY,
                ZoomWidth,
                ZoomHeight,
                canvasWidth,
                canvasHeight);
            CompareOriginX = x;
            CompareOriginY = y;
            return;
        }

        ZoomDragStartX ??= currentOriginX;
        ZoomDragStartY ??= currentOriginY;
        if (ZoomDragStartX is not { } zoomStartX || ZoomDragStartY is not { } zoomStartY)
        {
            return;
        }

        (double zoomX, double zoomY) = CanvasHudPlacement.AvoidingOverlap(
            zoomStartX + translationX,
            zoomStartY + translationY,
            ZoomWidth,
            ZoomHeight,
            origins.CompareX,
            origins.CompareY,
            CompareWidth,
            CompareHeight,
            canvasWidth,
            canvasHeight);
        ZoomOriginX = zoomX;
        ZoomOriginY = zoomY;
    }

    /// <summary>macOS <c>canvasHUDDragGesture.onEnded</c>.</summary>
    public void EndDrag(CanvasHudKind kind)
    {
        if (kind == CanvasHudKind.Compare)
        {
            CompareDragStartX = null;
            CompareDragStartY = null;
            return;
        }

        ZoomDragStartX = null;
        ZoomDragStartY = null;
    }
}
