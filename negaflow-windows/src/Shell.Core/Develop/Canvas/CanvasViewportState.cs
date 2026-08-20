namespace Negaflow.Shell.Develop;

/// <summary>macOS <c>CanvasViewportState</c>.</summary>
public sealed class CanvasViewportState
{
    public const double MinScale = 0.2;
    public const double MaxScale = 12;

    public double Scale { get; private set; } = 1;
    public double LastScale { get; private set; } = 1;
    public double OffsetX { get; private set; }
    public double OffsetY { get; private set; }
    public double LastOffsetX { get; private set; }
    public double LastOffsetY { get; private set; }

    public string ZoomText =>
        $"{(int)Math.Round(Scale * 100, MidpointRounding.AwayFromZero)}%";

    public void Reset()
    {
        Scale = 1;
        LastScale = 1;
        OffsetX = 0;
        OffsetY = 0;
        LastOffsetX = 0;
        LastOffsetY = 0;
    }

    public void SetScale(
        double newScale,
        double imageWidth,
        double imageHeight,
        double canvasWidth,
        double canvasHeight)
    {
        double clamped = ClampScale(newScale);
        Scale = clamped;
        LastScale = clamped;
        (OffsetX, OffsetY) = CanvasViewportGeometry.ClampedOffset(
            OffsetX,
            OffsetY,
            imageWidth,
            imageHeight,
            canvasWidth,
            canvasHeight,
            clamped);
        LastOffsetX = OffsetX;
        LastOffsetY = OffsetY;
    }

    public double ActualSizeScale(double imageWidth, double imageHeight, double canvasWidth, double canvasHeight) =>
        CanvasViewportGeometry.ActualSizeScale(
            imageWidth,
            imageHeight,
            canvasWidth,
            canvasHeight,
            MinScale,
            MaxScale);

    public void UpdatePan(
        double translationX,
        double translationY,
        double imageWidth,
        double imageHeight,
        double canvasWidth,
        double canvasHeight)
    {
        (OffsetX, OffsetY) = CanvasViewportGeometry.ClampedOffset(
            LastOffsetX + translationX,
            LastOffsetY + translationY,
            imageWidth,
            imageHeight,
            canvasWidth,
            canvasHeight,
            Scale);
    }

    public void EndPan()
    {
        LastOffsetX = OffsetX;
        LastOffsetY = OffsetY;
    }

    public void ApplyScrollPan(
        double translationX,
        double translationY,
        double imageWidth,
        double imageHeight,
        double canvasWidth,
        double canvasHeight)
    {
        (OffsetX, OffsetY) = CanvasViewportGeometry.ClampedOffset(
            OffsetX + translationX,
            OffsetY + translationY,
            imageWidth,
            imageHeight,
            canvasWidth,
            canvasHeight,
            Scale);
        LastOffsetX = OffsetX;
        LastOffsetY = OffsetY;
    }

    public void UpdateMagnification(
        double value,
        double imageWidth,
        double imageHeight,
        double canvasWidth,
        double canvasHeight)
    {
        double next = ClampScale(LastScale * value);
        Scale = next;
        (OffsetX, OffsetY) = CanvasViewportGeometry.ClampedOffset(
            OffsetX,
            OffsetY,
            imageWidth,
            imageHeight,
            canvasWidth,
            canvasHeight,
            next);
    }

    public void EndMagnification()
    {
        LastScale = Scale;
        LastOffsetX = OffsetX;
        LastOffsetY = OffsetY;
    }

    /// <summary>macOS HUD <c>scale * 1.25</c> / <c>scale / 1.25</c>.</summary>
    public void ZoomBy(
        double multiplier,
        double imageWidth,
        double imageHeight,
        double canvasWidth,
        double canvasHeight) =>
        SetScale(Scale * multiplier, imageWidth, imageHeight, canvasWidth, canvasHeight);

    public void SetZoomPercent(
        double percent,
        double imageWidth,
        double imageHeight,
        double canvasWidth,
        double canvasHeight) =>
        SetScale(percent / 100, imageWidth, imageHeight, canvasWidth, canvasHeight);

    /// <summary>macOS <c>CanvasToolHUD.applyZoomPercent</c>.</summary>
    public bool TryApplyZoomPercentText(
        string text,
        double imageWidth,
        double imageHeight,
        double canvasWidth,
        double canvasHeight)
    {
        if (!CanvasToolHudPolicy.TryParseZoomPercent(text, out double percent))
        {
            return false;
        }

        SetZoomPercent(percent, imageWidth, imageHeight, canvasWidth, canvasHeight);
        return true;
    }

    private static double ClampScale(double value) => Math.Min(Math.Max(value, MinScale), MaxScale);
}
