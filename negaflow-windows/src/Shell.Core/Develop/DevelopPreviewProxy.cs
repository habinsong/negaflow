namespace Negaflow.Shell;

/// <summary>
/// macOS <c>DevelopFrameRenderer</c> 의 프록시 치수입니다. 상수와 식을 그대로 옮겼습니다.
/// </summary>
public static class DevelopPreviewProxy
{
    // DevelopFrameRenderer.fullMaxDimension
    public const double FullMaxDimension = 3600;

    // DevelopFrameRenderer.interactiveMaxDimension
    public const double InteractiveMaxDimension = 2560;

    // DevelopFrameRenderer.fastPreviewMaxDimension
    public const double FastPreviewMaxDimension = 720;

    // DevelopFrameRenderer.interactiveMinDimension
    public const double InteractiveMinDimension = 1024;

    // DevelopFrameRenderer.interactiveDimensionStep
    public const double InteractiveDimensionStep = 256;

    // AppModel.waitForDevelopSettle
    public static readonly TimeSpan SettleWindow = TimeSpan.FromMilliseconds(140);

    /// <summary>
    /// macOS <c>interactiveProxyDimension(displayTargetPixels:)</c>.
    /// 표시 픽셀을 256 으로 올리고 1024…3600 으로 접습니다.
    /// </summary>
    public static double InteractiveProxyDimension(double displayTargetPixels)
    {
        if (displayTargetPixels <= 0)
        {
            return InteractiveMaxDimension;
        }

        double quantized = Math.Ceiling(displayTargetPixels / InteractiveDimensionStep) *
            InteractiveDimensionStep;
        return Math.Min(Math.Max(quantized, InteractiveMinDimension), FullMaxDimension);
    }

    /// <summary>
    /// 정사각형 버퍼에 넣을 한 변입니다. 네이티브 Preview 는 폭·높이 상한을 받습니다.
    /// </summary>
    public static uint BufferEdge(double longEdge)
    {
        double clamped = Math.Clamp(Math.Ceiling(longEdge), 1, FullMaxDimension);
        return (uint)clamped;
    }
}
