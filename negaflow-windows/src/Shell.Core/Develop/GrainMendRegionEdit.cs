using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>
/// 네이티브 GrainMend 검출 결과를 catalog 의 결함 항목으로 옮깁니다.
/// </summary>
/// <remarks>
/// <para>
/// 두 표현이 다릅니다. 검출기는 <b>화소당 1바이트</b> 마스크를 내주고, catalog 의 region 항목은
/// <b>RGBA8</b> 을 담습니다(`DefectRecipeValidator` 가 4바이트/화소를 요구하고, 네이티브 region
/// 편집도 stride 를 width×4 로 받습니다). 그래서 여기서 한 번 넓혀 줍니다.
/// </para>
/// <para>
/// 네 채널에 같은 값을 넣습니다. 수리는 첫 채널만 읽지만(적외선 경로가 <c>[pixel * 4]</c> 를
/// 꺼내 쓰는 것과 같습니다), 나머지를 0 으로 두면 마스크를 눈으로 확인할 때 왜 검은지 매번
/// 다시 알아내야 합니다.
/// </para>
/// </remarks>
public static class GrainMendRegionEdit
{
    /// <summary>
    /// 검출 마스크 한 장을 region 항목으로 만듭니다. 채택된 화소가 없으면 <see langword="null"/>
    /// 입니다 — 아무것도 고치지 않는 편집을 recipe 에 남기지 않습니다.
    /// </summary>
    /// <param name="mask">화소당 1바이트, <paramref name="width"/>×<paramref name="height"/>.</param>
    /// <param name="sourceWidth">현상 파이프라인이 검출한 원본 폭입니다.</param>
    /// <param name="sourceHeight">현상 파이프라인이 검출한 원본 높이입니다.</param>
    /// <param name="roiX">검출 원본 사각형의 좌상단 x입니다.</param>
    /// <param name="roiY">검출 원본 사각형의 좌상단 y입니다.</param>
    /// <param name="roiWidth">검출 원본 사각형의 폭입니다.</param>
    /// <param name="roiHeight">검출 원본 사각형의 높이입니다.</param>
    public static DefectEditItem? From(
        ReadOnlySpan<byte> mask,
        int width,
        int height,
        uint sourceWidth,
        uint sourceHeight,
        uint roiX,
        uint roiY,
        uint roiWidth,
        uint roiHeight,
        ulong acceptedPixels,
        bool automatic)
    {
        if (width <= 2 || height <= 2 ||
            mask.Length != checked(width * height) ||
            sourceWidth <= 2U || sourceHeight <= 2U ||
            roiWidth == 0U || roiHeight == 0U ||
            roiX > sourceWidth || roiY > sourceHeight ||
            roiWidth > sourceWidth - roiX || roiHeight > sourceHeight - roiY ||
            acceptedPixels == 0U || acceptedPixels > int.MaxValue)
        {
            return null;
        }

        int firstX = width;
        int firstY = height;
        int lastX = -1;
        int lastY = -1;
        for (int y = 0; y < height; ++y)
        {
            for (int x = 0; x < width; ++x)
            {
                if (mask[(y * width) + x] == 0)
                {
                    continue;
                }
                firstX = Math.Min(firstX, x);
                firstY = Math.Min(firstY, y);
                lastX = Math.Max(lastX, x);
                lastY = Math.Max(lastY, y);
            }
        }
        if (lastX < firstX || lastY < firstY)
        {
            return null;
        }

        // The capped analysis mask cannot be replayed as though its pixels were raw
        // pixels. Expand its nonzero bounds back into the exact native source ROI,
        // retain a small repair context, and resample only that bounded window.
        const int repairContextPixels = 8;
        int left = Math.Max(
            0,
            checked((int)roiX) +
                (int)Math.Floor(firstX * (double)roiWidth / width) - repairContextPixels);
        int top = Math.Max(
            0,
            checked((int)roiY) +
                (int)Math.Floor(firstY * (double)roiHeight / height) - repairContextPixels);
        int right = Math.Min(
            checked((int)sourceWidth),
            checked((int)roiX) +
                (int)Math.Ceiling((lastX + 1) * (double)roiWidth / width) + repairContextPixels);
        int bottom = Math.Min(
            checked((int)sourceHeight),
            checked((int)roiY) +
                (int)Math.Ceiling((lastY + 1) * (double)roiHeight / height) + repairContextPixels);
        if (right - left <= 2 || bottom - top <= 2)
        {
            return null;
        }

        int storedWidth = right - left;
        int storedHeight = bottom - top;
        byte[] rgba = new byte[checked(storedWidth * storedHeight * 4)];
        for (int y = 0; y < storedHeight; ++y)
        {
            double analysisY = ((top - (double)roiY + y + 0.5) * height / roiHeight) - 0.5;
            for (int x = 0; x < storedWidth; ++x)
            {
                double analysisX = ((left - (double)roiX + x + 0.5) * width / roiWidth) - 0.5;
                byte value = SampleMask(mask, width, height, analysisX, analysisY);
                if (value == 0)
                {
                    continue;
                }
                int target = ((y * storedWidth) + x) * 4;
                rgba[target] = value;
                rgba[target + 1] = value;
                rgba[target + 2] = value;
                rgba[target + 3] = value;
            }
        }

        return new DefectEditItem(
            Guid.NewGuid(),
            DefectEditKind.Region,
            Enabled: true,
            Strength: 1.0,
            new DefectEditLabel(
                automatic ? DefectEditLabelKind.Automatic : DefectEditLabelKind.Guided,
                checked((int)acceptedPixels)),
            new DefectEditSummary(
                DefectEditSummaryKind.ClassBreakdown,
                // 검출기는 먼지와 스크래치를 한 마스크로 합쳐 내주므로 종류별로 나눌 수
                // 없습니다. 지어내지 않고 하나로 셉니다.
                new DefectClassBreakdown(
                    [new DefectClassCount(DefectClassification.Dust, checked((int)acceptedPixels))],
                    1.0)),
            new DefectSize(sourceWidth, sourceHeight),
            [])
        {
            RegionMask = new DefectMask(false, rgba),
            // The catalog's region recipe is raw y-up while its bitmap rows remain
            // top-first. `bottom` is the y-down edge of this stored window.
            RegionRoi = new DefectRect(left, checked((int)sourceHeight) - bottom, storedWidth, storedHeight),
            RegionWidth = storedWidth,
            RegionHeight = storedHeight,
        };
    }

    private static byte SampleMask(
        ReadOnlySpan<byte> mask,
        int width,
        int height,
        double x,
        double y)
    {
        int x0 = (int)Math.Floor(x);
        int y0 = (int)Math.Floor(y);
        double fx = x - x0;
        double fy = y - y0;
        double top = MaskValue(mask, width, height, x0, y0) * (1.0 - fx) +
            MaskValue(mask, width, height, x0 + 1, y0) * fx;
        double bottom = MaskValue(mask, width, height, x0, y0 + 1) * (1.0 - fx) +
            MaskValue(mask, width, height, x0 + 1, y0 + 1) * fx;
        return (byte)Math.Clamp((int)Math.Round(
            (top * (1.0 - fy) + bottom * fy) * 255.0), 0, 255);
    }

    private static double MaskValue(
        ReadOnlySpan<byte> mask,
        int width,
        int height,
        int x,
        int y)
    {
        int clampedX = Math.Clamp(x, 0, width - 1);
        int clampedY = Math.Clamp(y, 0, height - 1);
        return mask[(clampedY * width) + clampedX] / 255.0;
    }
}
