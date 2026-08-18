namespace Negaflow.Shell.Print;

/// <summary>
/// macOS <c>PrintPackagePreviewResolution</c> 입니다. 인화 칸이 썸네일보다 크면
/// 표시 크기의 현상본을 올리고, 이미 더 큰 래스터가 있으면 그대로 둡니다.
/// </summary>
public static class PrintPreviewResolution
{
    /// <summary>macOS <c>DevelopFrameRenderer.interactiveMaxDimension</c>.</summary>
    public static double MaximumDimension => DevelopPreviewProxy.InteractiveMaxDimension;

    public static double PixelDimension(int width, int height) =>
        Math.Max(width, height);

    public static double RequiredDisplayDimension(double displayTargetPixels)
    {
        if (!double.IsFinite(displayTargetPixels) || displayTargetPixels <= 0)
        {
            return 0;
        }

        return Math.Min(displayTargetPixels, MaximumDimension);
    }

    /// <summary>
    /// macOS <c>renderDimension(for:)</c> — 표시 픽셀을 256 으로 올리고
    /// 720…2560 으로 접습니다.
    /// </summary>
    public static double RenderDimension(double displayTargetPixels)
    {
        double required = RequiredDisplayDimension(displayTargetPixels);
        if (required <= 0)
        {
            return 0;
        }

        double quantized = Math.Ceiling(required / DevelopPreviewProxy.InteractiveDimensionStep) *
            DevelopPreviewProxy.InteractiveDimensionStep;
        return Math.Min(
            Math.Max(quantized, DevelopPreviewProxy.FastPreviewMaxDimension),
            MaximumDimension);
    }

    public static bool NeedsUpgrade(int currentLongEdge, double displayTargetPixels)
    {
        double required = RequiredDisplayDimension(displayTargetPixels);
        return required > 0 && currentLongEdge + 0.5 < required;
    }

    /// <summary>
    /// macOS <c>bestImage</c> — 현상본·패키지 프리뷰·썸네일 중 긴 변이 큰 것, 없으면 raw.
    /// </summary>
    public static int? BestLongEdge(
        int? developed,
        int? packagePreview,
        int? thumbnail,
        int? raw)
    {
        int? best = Longer(developed, packagePreview);
        best = Longer(best, thumbnail);
        return best ?? raw;
    }

    private static int? Longer(int? left, int? right)
    {
        if (left is null)
        {
            return right;
        }
        if (right is null)
        {
            return left;
        }
        return left.Value >= right.Value ? left : right;
    }
}
