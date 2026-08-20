namespace Negaflow.Shell.Develop;

/// <summary>macOS <c>CanvasHUDKind</c>.</summary>
public enum CanvasHudKind
{
    Compare,
    Zoom,
}

/// <summary>macOS <c>CanvasHUDOrigins</c>.</summary>
public readonly record struct CanvasHudOrigins(double CompareX, double CompareY, double ZoomX, double ZoomY);

/// <summary>macOS <c>CanvasHUDPlacement</c>.</summary>
public static class CanvasHudPlacement
{
    public const double Margin = 12;
    public const double CollisionGap = 8;
    public const double DefaultCompareWidth = 220;
    public const double DefaultCompareHeight = 32;
    public const double DefaultZoomWidth = 136;
    public const double DefaultZoomHeight = 32;

    public static CanvasHudOrigins DefaultOrigins(
        double canvasWidth,
        double canvasHeight,
        double compareWidth,
        double compareHeight,
        double zoomWidth,
        double zoomHeight)
    {
        (double compareX, double compareY) = ClampedOrigin(
            Margin,
            Margin,
            compareWidth,
            compareHeight,
            canvasWidth,
            canvasHeight);
        (double proposedZoomX, double proposedZoomY) = ClampedOrigin(
            canvasWidth - Margin - zoomWidth,
            Margin,
            zoomWidth,
            zoomHeight,
            canvasWidth,
            canvasHeight);
        (double zoomX, double zoomY) = AvoidingOverlap(
            proposedZoomX,
            proposedZoomY,
            zoomWidth,
            zoomHeight,
            compareX,
            compareY,
            compareWidth,
            compareHeight,
            canvasWidth,
            canvasHeight);
        return new CanvasHudOrigins(compareX, compareY, zoomX, zoomY);
    }

    public static (double X, double Y) ClampedOrigin(
        double originX,
        double originY,
        double hudWidth,
        double hudHeight,
        double canvasWidth,
        double canvasHeight)
    {
        double maximumX = Math.Max(Margin, canvasWidth - Margin - hudWidth);
        double maximumY = Math.Max(Margin, canvasHeight - Margin - hudHeight);
        return (
            Math.Min(Math.Max(originX, Margin), maximumX),
            Math.Min(Math.Max(originY, Margin), maximumY));
    }

    public static (double X, double Y) AvoidingOverlap(
        double proposedX,
        double proposedY,
        double movingWidth,
        double movingHeight,
        double otherX,
        double otherY,
        double otherWidth,
        double otherHeight,
        double canvasWidth,
        double canvasHeight)
    {
        (proposedX, proposedY) = ClampedOrigin(
            proposedX,
            proposedY,
            movingWidth,
            movingHeight,
            canvasWidth,
            canvasHeight);
        double movingRight = proposedX + movingWidth;
        double movingBottom = proposedY + movingHeight;
        double otherLeft = otherX - CollisionGap;
        double otherTop = otherY - CollisionGap;
        double otherRight = otherX + otherWidth + CollisionGap;
        double otherBottom = otherY + otherHeight + CollisionGap;
        if (movingRight <= otherLeft ||
            proposedX >= otherRight ||
            movingBottom <= otherTop ||
            proposedY >= otherBottom)
        {
            return (proposedX, proposedY);
        }

        double movingCenterX = proposedX + (movingWidth / 2);
        double movingCenterY = proposedY + (movingHeight / 2);
        double otherMidX = (otherLeft + otherRight) / 2;
        double otherMidY = (otherTop + otherBottom) / 2;
        double deltaX = movingCenterX - otherMidX;
        double deltaY = movingCenterY - otherMidY;
        foreach (HudSide side in SidePriority(deltaX, deltaY))
        {
            (double candidateX, double candidateY) = CandidateOrigin(
                side,
                proposedX,
                proposedY,
                movingWidth,
                movingHeight,
                otherLeft,
                otherTop,
                otherRight,
                otherBottom,
                canvasWidth,
                canvasHeight);
            double candidateRight = candidateX + movingWidth;
            double candidateBottom = candidateY + movingHeight;
            if (candidateRight <= otherLeft ||
                candidateX >= otherRight ||
                candidateBottom <= otherTop ||
                candidateY >= otherBottom)
            {
                return (candidateX, candidateY);
            }
        }

        return (proposedX, proposedY);
    }

    private enum HudSide
    {
        Left,
        Right,
        Top,
        Bottom,
    }

    private static HudSide[] SidePriority(double deltaX, double deltaY)
    {
        HudSide firstHorizontal = deltaX < 0 ? HudSide.Left : HudSide.Right;
        HudSide secondHorizontal = deltaX < 0 ? HudSide.Right : HudSide.Left;
        HudSide firstVertical = deltaY < 0 ? HudSide.Top : HudSide.Bottom;
        HudSide secondVertical = deltaY < 0 ? HudSide.Bottom : HudSide.Top;
        return Math.Abs(deltaX) >= Math.Abs(deltaY)
            ? [firstHorizontal, firstVertical, secondVertical, secondHorizontal]
            : [firstVertical, firstHorizontal, secondHorizontal, secondVertical];
    }

    private static (double X, double Y) CandidateOrigin(
        HudSide side,
        double proposedX,
        double proposedY,
        double movingWidth,
        double movingHeight,
        double otherLeft,
        double otherTop,
        double otherRight,
        double otherBottom,
        double canvasWidth,
        double canvasHeight)
    {
        double rawX = side switch
        {
            HudSide.Left => otherLeft - movingWidth,
            HudSide.Right => otherRight,
            _ => proposedX,
        };
        double rawY = side switch
        {
            HudSide.Top => otherTop - movingHeight,
            HudSide.Bottom => otherBottom,
            _ => proposedY,
        };
        return ClampedOrigin(
            rawX,
            rawY,
            movingWidth,
            movingHeight,
            canvasWidth,
            canvasHeight);
    }
}
