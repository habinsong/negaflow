using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>검출 review를 preview 크기의 BGRA8 오버레이로 투영합니다.</summary>
public static class GrainMendOverlayRenderer
{
    public static byte[]? Render(
        LibraryFrameSnapshot frame,
        int previewWidth,
        int previewHeight,
        DefectEditItem edit,
        GrainMendReviewSession? review)
    {
        ArgumentNullException.ThrowIfNull(frame);
        ArgumentNullException.ThrowIfNull(edit);
        // 검출기가 종류를 냈으면 분류색으로 그립니다 — macOS `RegionDefectOverlay` 와 같이
        // 먼지·핀홀·가로/세로/대각 스크래치·유제손상·미세입자가 서로 다른 색입니다.
        // 검토에서 제외한 성분은 회색으로 남겨 무엇을 빼고 있는지 보이게 합니다.
        if (edit.Preview.Count > 0)
        {
            byte[]? classified = DefectMaskOverlayRenderer.RenderPreview(
                frame,
                previewWidth,
                previewHeight,
                edit.Preview,
                point => review?.IsExcludedAtRaw(point) == true);
            if (classified is not null)
            {
                return classified;
            }
        }
        if (previewWidth <= 0 || previewHeight <= 0 ||
            edit.RegionMask is not { } mask || edit.RegionRoi is not { } roi ||
            edit.RegionWidth is not { } maskWidth || edit.RegionHeight is not { } maskHeight ||
            edit.BaseSize is not { } sourceSize ||
            !DefectMaskCodec.TryDecodeRgba8(mask, maskWidth, maskHeight, out byte[] rgba))
        {
            return null;
        }

        byte[] bgra = new byte[checked(previewWidth * previewHeight * 4)];
        double rawTop = sourceSize.Height - roi.Y - roi.Height;
        for (int y = 0; y < previewHeight; ++y)
        {
            double displayY = previewHeight == 1 ? 0.0 : (double)y / (previewHeight - 1);
            for (int x = 0; x < previewWidth; ++x)
            {
                double displayX = previewWidth == 1 ? 0.0 : (double)x / (previewWidth - 1);
                if (!DevelopDisplayGeometry.TryMapDisplayToRaw(
                        frame.ImageTransform,
                        checked((uint)sourceSize.Width),
                        checked((uint)sourceSize.Height),
                        displayX,
                        displayY,
                        out double rawX,
                        out double rawY))
                {
                    continue;
                }
                int localX = (int)Math.Round(rawX * (sourceSize.Width - 1.0) - roi.X);
                int localY = (int)Math.Round(rawY * (sourceSize.Height - 1.0) - rawTop);
                if (localX < 0 || localX >= maskWidth || localY < 0 || localY >= maskHeight ||
                    rgba[((localY * maskWidth) + localX) * 4] == 0)
                {
                    continue;
                }

                int pixel = ((y * previewWidth) + x) * 4;
                bool excluded = review?.IsExcludedAtRaw(new DefectPoint(rawX, rawY)) == true;
                bgra[pixel] = excluded ? (byte)115 : (byte)30;
                bgra[pixel + 1] = excluded ? (byte)115 : (byte)30;
                bgra[pixel + 2] = excluded ? (byte)115 : (byte)200;
                bgra[pixel + 3] = excluded ? (byte)100 : (byte)200;
            }
        }
        return bgra;
    }
}
