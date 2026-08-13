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
    /// <param name="roi">
    /// 검출을 돌린 범위입니다. 자동은 프레임 전체, 가이드는 사용자가 끈 사각형이며 값은
    /// 검출 이미지 기준 정규 좌표입니다.
    /// </param>
    /// <param name="baseSize">검출 이미지의 크기입니다. 원본 해상도가 아닙니다.</param>
    public static DefectEditItem? From(
        ReadOnlySpan<byte> mask,
        int width,
        int height,
        DefectRect roi,
        DefectSize baseSize,
        bool automatic)
    {
        if (width <= 2 || height <= 2 ||
            mask.Length != checked(width * height))
        {
            return null;
        }

        byte[] rgba = new byte[checked(width * height * 4)];
        int accepted = 0;
        for (int pixel = 0; pixel < mask.Length; ++pixel)
        {
            byte value = mask[pixel];
            if (value == 0)
            {
                continue;
            }
            ++accepted;
            int target = pixel * 4;
            rgba[target] = value;
            rgba[target + 1] = value;
            rgba[target + 2] = value;
            rgba[target + 3] = value;
        }
        if (accepted == 0)
        {
            return null;
        }

        return new DefectEditItem(
            Guid.NewGuid(),
            DefectEditKind.Region,
            Enabled: true,
            Strength: 1.0,
            new DefectEditLabel(
                automatic ? DefectEditLabelKind.Automatic : DefectEditLabelKind.Guided,
                accepted),
            new DefectEditSummary(
                DefectEditSummaryKind.ClassBreakdown,
                // 검출기는 먼지와 스크래치를 한 마스크로 합쳐 내주므로 종류별로 나눌 수
                // 없습니다. 지어내지 않고 하나로 셉니다.
                new DefectClassBreakdown(
                    [new DefectClassCount(DefectClassification.Dust, accepted)],
                    1.0)),
            baseSize,
            [])
        {
            RegionMask = new DefectMask(false, rgba),
            RegionRoi = roi,
            RegionWidth = width,
            RegionHeight = height,
        };
    }
}
