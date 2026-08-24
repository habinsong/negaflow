using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 스캐너 preview의 Guided 영역을 첫 전체 스캔으로 옮길 때 쓰는 표시 좌표와 민감도입니다.
/// 하드웨어 요청과 무관한 Develop 상태이므로 scanner plugin protocol에는 넣지 않습니다.
/// </summary>
public sealed record GrainMendGuidedCarryover(
    ImageTransformRecipe Transform,
    DefectRect? DisplayRoi,
    double Sensitivity)
{
    public static GrainMendGuidedCarryover? Capture(
        LibraryFrameSnapshot? previewFrame,
        DefectRect? rawRoi,
        double sensitivity)
    {
        if (previewFrame is not { IsPreviewScan: true, SourceMetadata: { } metadata } ||
            !previewFrame.ImageTransform.IsValid ||
            !double.IsFinite(sensitivity) || sensitivity <= 0.0)
        {
            return null;
        }

        DefectRect? displayRoi = rawRoi is { } roi &&
            TryMapRawRectToDisplay(previewFrame, metadata, roi, out DefectRect mapped)
                ? mapped
                : null;
        return new GrainMendGuidedCarryover(
            previewFrame.ImageTransform,
            displayRoi,
            sensitivity);
    }

    public bool TryMapToRaw(LibraryFrameSnapshot? frame, out DefectRect rawRoi)
    {
        rawRoi = default;
        return DisplayRoi is { } displayRoi &&
            DevelopDefectEditor.TryMapDisplayRectToRaw(frame, displayRoi, out rawRoi);
    }

    private static bool TryMapRawRectToDisplay(
        LibraryFrameSnapshot frame,
        LibrarySourceMetadata metadata,
        DefectRect rawRoi,
        out DefectRect displayRoi)
    {
        displayRoi = default;
        if (!IsPositiveFinite(rawRoi))
        {
            return false;
        }

        DefectPoint[] corners =
        [
            new(rawRoi.X, rawRoi.Y),
            new(rawRoi.X + rawRoi.Width, rawRoi.Y),
            new(rawRoi.X, rawRoi.Y + rawRoi.Height),
            new(rawRoi.X + rawRoi.Width, rawRoi.Y + rawRoi.Height),
        ];
        double minX = double.PositiveInfinity;
        double minY = double.PositiveInfinity;
        double maxX = double.NegativeInfinity;
        double maxY = double.NegativeInfinity;
        foreach (DefectPoint corner in corners)
        {
            if (!DevelopDisplayGeometry.TryMapRawToDisplay(
                    frame.ImageTransform,
                    metadata.PixelWidth,
                    metadata.PixelHeight,
                    corner.X,
                    corner.Y,
                    out double displayX,
                    out double displayY))
            {
                return false;
            }
            minX = Math.Min(minX, displayX);
            minY = Math.Min(minY, displayY);
            maxX = Math.Max(maxX, displayX);
            maxY = Math.Max(maxY, displayY);
        }

        if (maxX <= minX || maxY <= minY)
        {
            return false;
        }
        displayRoi = new DefectRect(minX, minY, maxX - minX, maxY - minY);
        return true;
    }

    private static bool IsPositiveFinite(DefectRect rect) =>
        double.IsFinite(rect.X) && double.IsFinite(rect.Y) &&
        double.IsFinite(rect.Width) && double.IsFinite(rect.Height) &&
        rect.Width > 0.0 && rect.Height > 0.0;
}
