using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>덮개에 칠할 한 색입니다. 알파는 0~1 입니다.</summary>
public readonly record struct DefectOverlayColor(byte Red, byte Green, byte Blue, double Alpha);

/// <summary>
/// 분류별 고정 색입니다. macOS <c>DefectClass.overlayColor</c> 가 쓰는 SwiftUI 시스템 색을
/// 그대로 옮겼습니다 — 분류가 한눈에 구분되어야 하므로 종류마다 색이 정해져 있습니다.
/// </summary>
public static class DefectClassPalette
{
    /// <summary>macOS <c>Color.orange</c>. 브러시·복제 도장 경로도 이 색을 씁니다.</summary>
    public static readonly DefectOverlayColor Orange = new(255, 149, 0, 1.0);

    /// <summary>
    /// macOS <c>BrushOverlay.paint</c> 의 <c>Color.red.opacity(0.45)</c> 입니다. 칠하는
    /// 동안 보이는 라이브 색이며, 적용된 레이어를 그리는 주황(<see cref="Orange"/> 0.4)과
    /// 다릅니다 — macOS 도 두 표면이 서로 다른 색을 씁니다.
    /// </summary>
    public static readonly DefectOverlayColor BrushPaint = new(255, 59, 48, 0.45);

    public static DefectOverlayColor For(DefectClassification classification) =>
        classification switch
        {
            // .orange
            DefectClassification.Dust => new(255, 149, 0, 1.0),
            // .yellow
            DefectClassification.Pinhole => new(255, 204, 0, 1.0),
            // .red
            DefectClassification.ScratchHorizontal => new(255, 59, 48, 1.0),
            // .pink
            DefectClassification.ScratchVertical => new(255, 45, 85, 1.0),
            // .purple
            DefectClassification.ScratchDiagonal => new(175, 82, 222, 1.0),
            // .cyan
            DefectClassification.EmulsionDamage => new(50, 173, 230, 1.0),
            // .mint
            DefectClassification.MicroSpeck => new(0, 199, 190, 1.0),
            _ => Orange,
        };

    /// <summary>
    /// 확신이 높을수록 진하게 냅니다. macOS
    /// <c>overlayColor.opacity(0.35 + 0.5 * confidence)</c> 와 같은 식입니다.
    /// </summary>
    public static DefectOverlayColor ForComponent(
        DefectClassification classification,
        double confidence)
    {
        DefectOverlayColor color = For(classification);
        double alpha = 0.35 + (0.5 * Math.Clamp(
            double.IsFinite(confidence) ? confidence : 0.0,
            0.0,
            1.0));
        return color with { Alpha = alpha };
    }
}
