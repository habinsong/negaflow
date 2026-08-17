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
