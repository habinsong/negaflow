using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 저장된 결함 마스크 한 장이 원본 어디에 놓이는지입니다.
/// </summary>
/// <remarks>
/// recipe 의 ROI 는 y-up 이고 마스크 행은 위에서부터입니다. 그 한 번의 뒤집기를 여기 한 곳에만
/// 둡니다 — 두 벌이 되면 언젠가 한쪽만 고쳐지고, 덮개와 클릭이 서로 다른 자리를 가리킵니다.
/// 정규 좌표 0 과 1 은 첫 화소와 마지막 화소의 <b>중심</b>입니다
/// (<see cref="DevelopDisplayGeometry"/> 와 같은 규약).
/// </remarks>
public readonly record struct GrainMendMaskWindow(
    int Width,
    int Height,
    DefectRect Roi,
    DefectSize BaseSize)
{
    public bool IsValid =>
        Width > 0 && Height > 0 && BaseSize.Width > 1.0 && BaseSize.Height > 1.0;

    /// <summary>원본 정규 좌표 한 점이 놓인 마스크 화소입니다.</summary>
    public bool TryLocate(DefectPoint rawPoint, out int x, out int y)
    {
        x = 0;
        y = 0;
        if (!IsValid ||
            !double.IsFinite(rawPoint.X) || !double.IsFinite(rawPoint.Y) ||
            rawPoint.X is < 0.0 or > 1.0 || rawPoint.Y is < 0.0 or > 1.0)
        {
            return false;
        }

        double rawTop = BaseSize.Height - Roi.Y - Roi.Height;
        x = (int)Math.Round((rawPoint.X * (BaseSize.Width - 1.0)) - Roi.X);
        y = (int)Math.Round((rawPoint.Y * (BaseSize.Height - 1.0)) - rawTop);
        return x >= 0 && x < Width && y >= 0 && y < Height;
    }

    /// <summary>편집 항목이 마스크를 담고 있으면 그 창입니다.</summary>
    public static GrainMendMaskWindow? For(DefectEditItem item)
    {
        ArgumentNullException.ThrowIfNull(item);
        if (item.RegionRoi is not { } roi || item.RegionWidth is not { } width ||
            item.RegionHeight is not { } height || item.BaseSize is not { } baseSize)
        {
            return null;
        }
        GrainMendMaskWindow window = new(width, height, roi, baseSize);
        return window.IsValid ? window : null;
    }
}
