namespace Negaflow.Shell.Develop;

/// <summary>macOS <c>CanvasGeometry.swift</c> 줌·팬 수식.</summary>
public static class CanvasViewportGeometry
{
    public static double FitScale(double imageWidth, double imageHeight, double canvasWidth, double canvasHeight)
    {
        if (imageWidth <= 0 || imageHeight <= 0 || canvasWidth <= 0 || canvasHeight <= 0)
        {
            return 1;
        }

        double padding = canvasWidth > 180 && canvasHeight > 180 ? 32 : 12;
        double availableWidth = Math.Max(1, canvasWidth - (padding * 2));
        double availableHeight = Math.Max(1, canvasHeight - (padding * 2));
        return Math.Min(availableWidth / imageWidth, availableHeight / imageHeight);
    }

    public static double ActualSizeScale(
        double imageWidth,
        double imageHeight,
        double canvasWidth,
        double canvasHeight,
        double minScale,
        double maxScale)
    {
        double fit = FitScale(imageWidth, imageHeight, canvasWidth, canvasHeight);
        return Math.Min(Math.Max(1 / fit, minScale), maxScale);
    }

    public static (double X, double Y, double Width, double Height) FittedImageFrame(
        double imageWidth,
        double imageHeight,
        double canvasWidth,
        double canvasHeight,
        double scale,
        double offsetX,
        double offsetY)
    {
        double fit = FitScale(imageWidth, imageHeight, canvasWidth, canvasHeight) * scale;
        double width = imageWidth * fit;
        double height = imageHeight * fit;
        return (
            ((canvasWidth - width) / 2) + offsetX,
            ((canvasHeight - height) / 2) + offsetY,
            width,
            height);
    }

    public static (double X, double Y) ClampedOffset(
        double proposedX,
        double proposedY,
        double imageWidth,
        double imageHeight,
        double canvasWidth,
        double canvasHeight,
        double scale)
    {
        double fit = FitScale(imageWidth, imageHeight, canvasWidth, canvasHeight) * scale;
        double drawnWidth = imageWidth * fit;
        double drawnHeight = imageHeight * fit;
        double limitX = Math.Max(48, ((drawnWidth - canvasWidth) / 2) + 96);
        double limitY = Math.Max(48, ((drawnHeight - canvasHeight) / 2) + 96);
        return (
            Math.Min(Math.Max(proposedX, -limitX), limitX),
            Math.Min(Math.Max(proposedY, -limitY), limitY));
    }
}
